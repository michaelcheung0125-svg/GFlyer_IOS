#!/usr/bin/env python3
"""
掃描公開版（GFlyerPublic）會編譯的檔案，有親友版的字就失敗（docs/APP_STORE_PLAN.md 第 10 項）。

    python3 scripts/check_public_sources.py              掃描 git 追蹤的檔案
    python3 scripts/check_public_sources.py --app APP    掃描建好的公開版 .app
    python3 scripts/check_public_sources.py --self-test  確認每一條規則都擋得住

照 Android 匯出工具的禁用字檢查（GFlyer 的 tools/export-public/export.py）：檔名和內容都掃，
二進位檔也掃（例如圖片的中繼資料），連註解；另外不可以有和親友版一模一樣的檔案（改了名也算）。
範圍是公開版 App、通道 extension 和公開版測試的 sources（project.yml 的 GFlyerPublic、
GFlyerPublicTunnel、GFlyerPublicTests）：GFlyerIOS/、GFlyerPublicTunnel/ 和 GFlyerIOSTests/，
扣掉 Vendor/ 和兩個 Family/。改了 project.yml 的 sources，這裏的 PUBLIC_SCOPES 和
EXPECTED_SOURCES 要一起改，否則這個檢查會失敗。

--app 掃的是建好的 App：檔名、Info.plist，和每個檔案裏以 NUL 分開的字串（執行檔的字串、
符號和 debug map 的檔名都在裏面）。原始碼掃描管的是寫進 repo 的字；這一步管建置時才加進來的，
例如建置設定、資源和連結進來的程式庫。Swift 把 15 bytes 以下的字串放在指令裏，這一步看不到，
所以它不能取代原始碼掃描。
"""
from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# 公開版會編譯或放進 App 的資料夾，和要扣掉的子資料夾
PUBLIC_SCOPES = [
    ("GFlyerIOS/", ("GFlyerIOS/Vendor/", "GFlyerIOS/Family/")),
    ("GFlyerPublicTunnel/", ()),
    ("GFlyerIOSTests/", ("GFlyerIOSTests/Family/",)),
]
FAMILY_ONLY = ("GFlyerIOS/Family/", "GFlyerIOSTests/Family/")
# project.yml 裏公開版各個 target 的 sources，和 PUBLIC_SCOPES 描述的是同一件事
EXPECTED_SOURCES = {
    "GFlyerPublic": [
        "- path: GFlyerIOS",
        "excludes:",
        "- Vendor",
        "- Family",
        "- Public",
        "- path: GFlyerIOS/Public",
    ],
    "GFlyerPublicTunnel": [
        "- path: GFlyerPublicTunnel",
        "- path: GFlyerIOS/Public/Tunnel/PacketReflector.swift",
    ],
    "GFlyerPublicTests": [
        "- path: GFlyerIOSTests",
        "excludes:",
        "- Family",
    ],
}

# ── 禁用字 ─────────────────────────────────────────────────────
# 和 Android 的清單相同，再加上 iOS 親友版才有的：明信片、SideStore、AltStore 和 LocalDevVPN。
FORBIDDEN = [
    (re.compile(r"mushroom", re.I), "親友版的找菇"),
    (re.compile(r"找菇"), "親友版的找菇"),
    (re.compile(r"鳥瞰跳點"), "親友版的找菇"),
    (re.compile(r"birds?eye", re.I), "親友版的找菇（鳥瞰跳點）"),
    (re.compile(r"種花"), "親友版的種花"),
    # overflowError 不算：連結進來的 idevice（Rust 的 regex 套件）有這個字
    (re.compile(r"(?<!over)flower", re.I), "親友版的種花"),
    (re.compile(r"圖鑑"), "親友版的座標圖鑑"),
    (re.compile(r"coordinate[-_ ]?librar", re.I), "親友版的座標圖鑑"),
    (re.compile(r"明信片|postcard", re.I), "遊戲用語"),
    (re.compile(r"遊戲|游戏"), "公開版不提遊戲"),
    (re.compile(r"\bgam(e|es|ing)\b", re.I), "公開版不提遊戲"),
    (re.compile(r"pikmin|皮克敏", re.I), "遊戲名稱"),
    (re.compile(r"pok[eé]mon|寶可夢|宝可梦", re.I), "遊戲名稱"),
    (re.compile(r"niantic", re.I), "遊戲公司名稱"),
    (re.compile(r"talll?kai", re.I), "親友版座標圖鑑的資料來源"),
    (re.compile(r"sidestore", re.I), "親友版的安裝方式"),
    (re.compile(r"altstore", re.I), "親友版的安裝方式"),
    (re.compile(r"localdevvpn", re.I), "親友版的本機通道（公開版用 App 內建的通道）"),
    # 公開的 Nominatim 只准全部用戶合計每秒一次；公開版的地名反查用 Apple 的地點服務（第 17 項，DRIFT D33）
    (re.compile(r"nominatim\.openstreetmap\.org", re.I), "公開版不連 Nominatim"),
    (re.compile(r"michaelcheung", re.I), "個人帳戶"),
    (re.compile(r"michael", re.I), "個人姓名"),
    (re.compile(r"xyz91", re.I), "本機使用者名稱"),
    (re.compile(r"gmail\.com", re.I), "私人電郵"),
    (re.compile(r"\.workers\.dev", re.I), "Cloudflare Worker 網址（私人後端）"),
    (re.compile(r"\.github\.io", re.I), "GitHub Pages 網址（私人網站和更新來源）"),
    (re.compile(r"[A-Za-z]:[\\/]+(Users|Project)\b", re.I), "本機路徑"),
    (re.compile(r"/[a-z]/(Users|Project)/", re.I), "本機路徑"),
    (re.compile(r"AIza[0-9A-Za-z_\-]{20,}"), "Google API key"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "私鑰"),
]
# 提醒：私人 repo 的名字。只出現在註解裏的出處說明，不是連結；每次都列出來給人看。
WARN = [
    (re.compile(r"GFlyer-Suite"), "私人 repo 名稱（跨平台規格）"),
    (re.compile(r"GFlyer-updates"), "私人 repo 名稱（親友版更新來源）"),
    (re.compile(r"GFlyer_IOS"), "私人 repo 名稱（iOS）"),
]
# 「開放原始碼授權」頁的清單（第 18 項，scripts/open_source_licenses.py 產生；App 裏放在根目錄）。
# 授權全文要原樣附上，裏面第三方版權人的名字和電郵會撞到上面的「個人姓名」「私人電郵」。只有這個檔、
# 只有下面這幾段字放行，其餘規則照舊。清單換了內容又撞到時，確認是第三方的版權人才加在這裏。
NOTICES_FILE = "OpenSourceLicenses.json"
NOTICES_ALLOWED = ["Michael Wright", "keepsimple@gmail.com", "jpixton@gmail.com"]
# 不應出現在公開版的檔案（不論在哪個資料夾）：簽署用的檔案、Pairing File、DDI 和建置產物
FORBIDDEN_FILE_SUFFIXES = {
    ".p12", ".pem", ".cer", ".mobileprovision", ".mobiledevicepairing", ".dmg", ".a", ".ipa",
}
# 太小的檔案（空白檔、`{}` 之類）不比較是不是和親友版一模一樣
MIN_HASHED_BYTES = 64


def without_allowed_notices(name: str, text: str) -> str:
    """授權清單裏放行的第三方名字換成不會撞到規則的字，其他檔案原樣。"""
    if Path(name).name != NOTICES_FILE:
        return text
    for allowed in NOTICES_ALLOWED:
        text = text.replace(allowed, "#" * len(allowed))
    return text


def in_public_scope(path: str) -> bool:
    return any(path.startswith(base) and not path.startswith(excluded)
               for base, excluded in PUBLIC_SCOPES)


def tracked_files() -> list[str]:
    output = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, check=True
    ).stdout.decode("utf-8")
    return sorted(name for name in output.split("\0") if name)


def target_sources(project_yml: str, target: str) -> list[str]:
    """project.yml 裏一個 target 的 sources 那幾行（去掉縮排和註解）。"""
    lines = project_yml.splitlines()
    start = next((i for i, line in enumerate(lines) if line == f"  {target}:"), None)
    if start is None:
        return []
    sources: list[str] = []
    inside = False
    for line in lines[start + 1:]:
        if re.match(r"  \S", line):
            break
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if line.startswith("    ") and not line.startswith("     "):
            inside = stripped == "sources:"
            continue
        if inside:
            sources.append(stripped)
    return sources


def check_scope(project_yml: str) -> list[str]:
    problems = []
    for target, expected in EXPECTED_SOURCES.items():
        actual = target_sources(project_yml, target)
        if actual != expected:
            problems.append(
                f"project.yml 的 {target} sources 和這個檢查的範圍不同：{actual}；"
                f"改 scripts/check_public_sources.py 的 PUBLIC_SCOPES 和 EXPECTED_SOURCES"
            )
    return problems


def scan(files: dict[str, bytes]) -> tuple[list[str], list[str]]:
    """`files` 是 repo 裏的路徑和內容。回傳（問題，提醒）。"""
    family: dict[str, list[str]] = {}
    for path, data in files.items():
        if path.startswith(FAMILY_ONLY) and len(data) >= MIN_HASHED_BYTES:
            family.setdefault(hashlib.sha256(data).hexdigest(), []).append(path)
    problems: list[str] = []
    warnings: list[str] = []
    for path, data in sorted(files.items()):
        if not in_public_scope(path):
            continue
        if Path(path).suffix.lower() in FORBIDDEN_FILE_SUFFIXES:
            problems.append(f"{path}：不應放進公開版的檔案")
        if len(data) >= MIN_HASHED_BYTES:
            for same in family.get(hashlib.sha256(data).hexdigest(), []):
                problems.append(f"{path}：和親友版的 {same} 一模一樣")
        for pattern, reason in FORBIDDEN:
            match = pattern.search(path)
            if match:
                problems.append(f"{path}：檔名有「{match.group(0)}」（{reason}）")
        text = without_allowed_notices(path, data.decode("utf-8", errors="replace"))
        for number, line in enumerate(text.splitlines(), start=1):
            for pattern, reason in FORBIDDEN:
                match = pattern.search(line)
                if match:
                    problems.append(f"{path}:{number}：「{match.group(0)}」（{reason}）")
            for pattern, reason in WARN:
                if pattern.search(line):
                    warnings.append(f"{path}:{number}：{reason}")
    return problems, warnings


def plist_strings(value) -> list[str]:
    """plist 裏所有的鍵和字串值。"""
    if isinstance(value, dict):
        return [text for key, item in value.items() for text in [key, *plist_strings(item)]]
    if isinstance(value, list):
        return [text for item in value for text in plist_strings(item)]
    return [value] if isinstance(value, str) else []


def binary_strings(data: bytes) -> set[str]:
    """以 NUL 分開、整段是可以印出來的 UTF-8 的字串，4 bytes 以上（和 scripts/ipa_summary.py 相同）。
    執行檔裏機器碼的 bytes 碰巧拼出禁用字時，前後通常不會剛好是 NUL，所以不會誤報。"""
    found = set()
    for chunk in data.split(b"\x00"):
        if len(chunk) < 4:
            continue
        try:
            text = chunk.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if all(c.isprintable() or c in "\n\t" for c in text):
            found.add(text)
    return found


def scan_app(app: Path) -> tuple[list[str], list[str]]:
    """建好的 .app 裏的檔名、Info.plist 和字串。回傳（問題，提醒），同一段字串只列一次。"""
    problems: list[str] = []
    warnings: list[str] = []

    def check(where: str, text: str) -> None:
        shown = text if len(text) <= 120 else text[:117] + "..."
        for pattern, reason in FORBIDDEN:
            match = pattern.search(text)
            if match:
                problems.append(f"{where}：「{match.group(0)}」（{reason}）：{shown!r}")
        for pattern, reason in WARN:
            if pattern.search(text):
                warnings.append(f"{where}：{reason}：{shown!r}")

    for path in sorted(p for p in app.rglob("*") if p.is_file()):
        name = path.relative_to(app).as_posix()
        check(f"{name}（檔名）", name)
        data = path.read_bytes()
        texts = plist_strings(plistlib.loads(data)) if name == "Info.plist" else binary_strings(data)
        for text in sorted(set(texts)):
            check(name, without_allowed_notices(name, text))
    return problems, warnings


def self_test() -> list[str]:
    """每一條規則都要擋得住一個例子；親友版和 Vendor 裏的不算。"""
    failures = []
    clean = {"GFlyerIOS/UI/Clean.swift": b"let title = \"GFlyer\"\nlet overflowError = 1\n"}
    if scan(clean)[0]:
        failures.append("乾淨的檔案被當成有問題")
    samples = {
        "mushroom": "找菇", "鳥瞰跳點": "birdseye", "種花": "flower", "圖鑑": "coordinate library",
        "明信片": "postcard", "遊戲": "game", "pikmin": "皮克敏", "pokémon": "niantic",
        "talllkai": "SideStore", "AltStore": "LocalDevVPN", "michaelcheung": "michael", "xyz91": "gmail.com",
        "example.workers.dev": "example.github.io", r"C:\Project\GFlyer_IOS": "/c/Users/someone/",
        "AIza" + "x" * 30: "-----BEGIN RSA PRIVATE KEY-----",
        "https://nominatim.openstreetmap.org/reverse": "NOMINATIM.OpenStreetMap.org",
    }
    words = [word for pair in samples.items() for word in pair]
    for pattern, _ in FORBIDDEN:
        if not any(pattern.search(word) for word in words):
            failures.append(f"規則 {pattern.pattern} 沒有例子")
    for word in words:
        for path in ("GFlyerIOS/Services/Sample.swift", "GFlyerPublicTunnel/Sample.swift",
                     "GFlyerIOSTests/SampleTests.swift"):
            if not scan({path: f"// {word}\n".encode("utf-8")})[0]:
                failures.append(f"{path} 裏的「{word}」沒有被擋下")
        for path in ("GFlyerIOS/Family/Sample.swift", "GFlyerIOSTests/Family/SampleTests.swift",
                     "GFlyerIOS/Vendor/idevice/include/sample.h", "docs/sample.md"):
            if scan({path: f"// {word}\n".encode("utf-8")})[0]:
                failures.append(f"範圍外的 {path} 也被擋下")
    if not scan({"GFlyerIOS/Resources/Flower.png": b"\x89PNG"})[0]:
        failures.append("檔名的禁用字沒有被擋下")
    if not scan({"GFlyerIOS/Resources/pairing.mobiledevicepairing": b"x"})[0]:
        failures.append("Pairing File 沒有被擋下")
    copied = b"x" * MIN_HASHED_BYTES
    if not scan({"GFlyerIOS/Family/Art.png": copied, "GFlyerIOS/Resources/Renamed.png": copied})[0]:
        failures.append("和親友版一模一樣的檔案沒有被擋下")
    if scan({"GFlyerIOS/Family/Art.png": copied[:-1], "GFlyerIOS/Resources/Small.png": copied[:-1]})[0]:
        failures.append("太小的檔案不應該比較")
    if not scan({"GFlyerIOS/Sample.swift": b"// GFlyer-Suite docs\n"})[1]:
        failures.append("私人 repo 名稱沒有提醒")
    notices = f"GFlyerIOS/Resources/{NOTICES_FILE}"
    allowed = " ".join(NOTICES_ALLOWED)
    if scan({notices: f"Copyright {allowed}\n".encode("utf-8")})[0]:
        failures.append("授權清單裏放行的第三方名字被當成有問題")
    for word in ("michaelcheung", "Michael Cheung", "someone@gmail.com", "xyz91", "game"):
        if not scan({notices: f"Copyright {word}\n".encode("utf-8")})[0]:
            failures.append(f"授權清單裏的「{word}」沒有被擋下")
    if not scan({"GFlyerIOS/Services/Sample.swift": f"// {NOTICES_ALLOWED[0]}\n".encode("utf-8")})[0]:
        failures.append("授權清單以外的檔案也放行了第三方名字")
    project = (ROOT / "project.yml").read_text(encoding="utf-8").replace("\r\n", "\n")
    if check_scope(project):
        failures.append("現在的 project.yml 和範圍不同")
    widened = project.replace("      - path: GFlyerIOS/Public\n",
                              "      - path: GFlyerIOS/Public\n      - path: GFlyerIOS/Family\n", 1)
    if widened == project or not check_scope(widened):
        failures.append("project.yml 的公開版 sources 改了也沒有發現")
    failures += self_test_app()
    return failures


def self_test_app() -> list[str]:
    failures = []
    plist = {"CFBundleName": "GFlyer", "CFBundleURLTypes": [{"CFBundleURLSchemes": ["jetpiggy-gflyer"]}]}
    executable = "\0\0\x01\x02game\x03\0overflowError\0CoreDevice 通道已驗證\0".encode("utf-8")
    dirty = {
        "Info.plist 的字串": {"Info.plist": plistlib.dumps(
            {**plist, "LSApplicationQueriesSchemes": ["localdevvpn"]}, fmt=plistlib.FMT_BINARY)},
        "執行檔的字串": {"GFlyerPublic": executable + "LocalDevVPN/CoreDevice 通道已驗證\0".encode("utf-8")},
        "檔名": {"Flower.png": b"\x89PNG"},
        "授權清單": {NOTICES_FILE: f'{{"text": "Copyright {NOTICES_ALLOWED[0]}, xyz91"}}'.encode("utf-8")},
    }
    with tempfile.TemporaryDirectory() as temp:
        for case, extra in [("乾淨的 App", {}), *dirty.items()]:
            app = Path(temp) / f"{len(list(Path(temp).iterdir()))}.app"
            app.mkdir()
            files = {"Info.plist": plistlib.dumps(plist, fmt=plistlib.FMT_BINARY),
                     "GFlyerPublic": executable,
                     NOTICES_FILE: f'{{"text": "Copyright {" ".join(NOTICES_ALLOWED)}"}}'.encode("utf-8"),
                     **extra}
            for name, data in files.items():
                (app / name).write_bytes(data)
            problems = scan_app(app)[0]
            if extra and not problems:
                failures.append(f"建好的 App 裏{case}的禁用字沒有被擋下")
            if not extra and problems:
                failures.append(f"乾淨的 App 被當成有問題：{problems}")
    return failures


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--self-test", action="store_true", help="確認每一條規則都擋得住")
    parser.add_argument("--app", type=Path, help="掃描建好的公開版 .app")
    args = parser.parse_args()

    if args.self_test:
        failures = self_test()
        for failure in failures:
            print(f"self-test：{failure}", file=sys.stderr)
        if failures:
            return 1
        print(f"self-test 通過：{len(FORBIDDEN)} 條禁用字、檔案類型、和親友版相同的檔案、"
              f"project.yml 的範圍、建好的 App")
        return 0

    if args.app:
        if not (args.app / "Info.plist").is_file():
            print(f"{args.app} 不是建好的 .app", file=sys.stderr)
            return 2
        problems, warnings = scan_app(args.app)
        for warning in warnings:
            print(f"提醒 {warning}")
        if problems:
            print(f"建好的公開版 App 掃描沒有通過（{len(problems)} 項）：", file=sys.stderr)
            for problem in problems:
                print(f"  {problem}", file=sys.stderr)
            return 1
        print(f"建好的公開版 App 掃描通過：{len(warnings)} 個提醒")
        return 0

    problems = check_scope((ROOT / "project.yml").read_text(encoding="utf-8"))
    names = tracked_files()
    bases = tuple(base for base, _ in PUBLIC_SCOPES)
    files = {name: (ROOT / name).read_bytes() for name in names
             if name.startswith(bases) and (ROOT / name).is_file()}
    scanned = sum(1 for name in files if in_public_scope(name))
    found, warnings = scan(files)
    problems += found
    for warning in warnings:
        print(f"提醒 {warning}")
    if problems:
        print(f"公開版的原始碼掃描沒有通過（{len(problems)} 項）：", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print("改寫成不提親友版的說法，或搬進 GFlyerIOS/Family/（docs/APP_STORE_PLAN.md 第 10 項）。", file=sys.stderr)
        return 1
    print(f"公開版的原始碼掃描通過：{scanned} 個檔案，{len(warnings)} 個提醒")
    return 0


if __name__ == "__main__":
    sys.exit(main())
