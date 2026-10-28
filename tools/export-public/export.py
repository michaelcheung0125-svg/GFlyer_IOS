#!/usr/bin/env python3
"""
把這個 repo 的一個 commit 匯出成公開版（GFlyerPublic）的原始碼，放進公開 repo 的資料夾
（docs/APP_STORE_PLAN.md 第 28 項，照 Android GFlyer 的 tools/export-public/export.py）。

    python -I tools/export-public/export.py                  匯出 HEAD 到 ../GFlyer-iOS-public
    python -I tools/export-public/export.py --commit abc123
    python -I tools/export-public/export.py --dest D:/somewhere/GFlyer-iOS-public
    python3 -I tools/export-public/export.py --build         匯出之後在那裏跑公開 repo 的 CI（只限 Mac）

步驟（任何一步失敗就停，不會只做一半）：
1. git archive 這個 commit（未 commit 的改動不會匯出），解開到暫存資料夾。
2. 頂層路徑，和 GFlyerIOS/、GFlyerIOSTests/ 底下的資料夾、scripts/ 底下的每一項，都要在下面的清單分類；
   未分類的就停，讓人決定公不公開。
3. 拿走不公開的路徑，從 project.yml 產生只有公開版的 project.yml，再蓋上 overlay/ 的公開版檔案
   （README、AGENTS.md、LICENSE、NOTICE、CI 等）。
4. 掃描禁用字（scripts/check_public_sources.py 的同一份清單，加上親友版的 Bundle ID 和私人網址）、
   不應出現的檔案，以及和親友版一模一樣的檔案（改了名也算）；掃到就停。
5. 同步到目的資料夾：保留 .git、CLAUDE.local.md、建置資料夾和建好的 idevice 程式庫，其他換成新的。
6. 加 --build 的話，在目的資料夾跑公開 repo 的 CI 步驟（scripts/ci.sh：授權清單、idevice、模擬器測試、
   未簽署的 archive 和檢查）。要 macOS、Xcode、XcodeGen 和 Rust；Windows 只能匯出和掃描。

只匯出和建置，不 commit、不 push：那兩步要使用者確認公開內容之後才做（見 AGENTS.md「匯出公開版」）。
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OVERLAY = Path(__file__).resolve().parent / "overlay"
DEFAULT_DEST = ROOT.parent / "GFlyer-iOS-public"

# ── 公開與否的清單 ──────────────────────────────────────────────
# 頂層路徑每一個都要分類。SPLIT 的資料夾逐項分類，不整個公開或不公開：
# True 表示直接放在資料夾裏的檔案照公開，只有子資料夾要分類；False 表示每一項都要分類。
SPLIT = {"GFlyerIOS": True, "GFlyerIOSTests": True, "scripts": False}
INCLUDE = {
    "GFlyerPublicTunnel",
    "THIRD_PARTY_NOTICES.md",
    "GFlyerIOS/Edition",
    "GFlyerIOS/Model",
    "GFlyerIOS/Public",
    "GFlyerIOS/Resources",
    "GFlyerIOS/Services",
    "GFlyerIOS/UI",
    "GFlyerIOSTests/Public",
    "scripts/build_idevice.sh",
    "scripts/check_privacy_manifest.py",
    "scripts/licenses",
    "scripts/open_source_licenses.py",
}
# 用 overlay/ 的公開版取代
REPLACED = {
    ".github",
    ".gitignore",
    "AGENTS.md",
    "README.md",
    "GFlyerIOS/Vendor",
}
# 由這個工具從開發 repo 的版本產生
GENERATED = {"project.yml"}
EXCLUDE = {
    "GFlyerIOS/Family": "親友版專屬的程式和設定（座標圖鑑、留言板、檢查新版、補錄步數、LocalDevVPN、Nominatim）",
    "GFlyerIOSTests/Family": "親友版的測試",
    ".claude": "開發用的 Claude Code skill（write-swift 和第三方的演示動畫範本），和 App 無關",
    "docs": "上架計劃、發佈流程、私隱政策正本、教學和截圖：寫到親友版的功能和私人網址",
    "HANDOFF.md": "開發交接紀錄",
    "tools": "這個匯出工具（含禁用字清單）",
    "scripts/check_public_sources.py": "公開版的禁用字掃描：清單本身就是禁用字",
    "scripts/ipa_summary.py": "比較兩次建置的開發工具，只有開發 repo 的 CI 用",
    "scripts/make_brand_art.py": "從品牌中心的正本轉出 App 圖示和飛豬圖，要讀品牌中心；轉好的圖已經在 Assets.xcassets",
}

# ── project.yml ─────────────────────────────────────────────────
FAMILY_TARGETS = {"GFlyerIOS", "GFlyerIOSTests"}
PUBLIC_TARGETS = {"GFlyerPublic", "GFlyerPublicTunnel", "GFlyerPublicTests"}
FAMILY_SCHEMES = {"GFlyerIOS", "GFlyerIOS-Idevice"}
PUBLIC_SCHEMES = {"GFlyerPublic", "GFlyerPublic-Idevice"}
PROJECT_HEADER = """\
# 公開版的 XcodeGen 設定，由維護者的匯出工具產生（見 AGENTS.md）。
#   GFlyerPublic        App（Bundle ID com.jetpiggy.gflyer）
#   GFlyerPublicTunnel  App 內建的本機通道（Packet Tunnel extension），放進 App 的 PlugIns/
#   GFlyerPublicTests   單元測試，在 GFlyerPublic 裏跑
# scheme：GFlyerPublic 用預覽的定位後端，在模擬器跑；GFlyerPublic-Idevice 連結 libidevice_ffi.a，
# 在 iPhone 上用（先跑 scripts/build_idevice.sh，見 README.md）。GFlyerPublic-Idevice 執行時用 Idevice
# 設定（debug 類），archive 用 AppStore 設定（release 類：有 dSYM，執行檔經過 strip），上傳
# App Store Connect 的就是它。兩個設定的內容相同，改其中一個時兩個一起改。
# Assets.xcassets 經 sources 加進 App：XcodeGen 沒有 target 層級的 resources 欄位。
"""

# ── 禁用字 ─────────────────────────────────────────────────────
# 主要的清單在 scripts/check_public_sources.py（公開版的原始碼每次 push 都用它掃）；匯出的全部檔案
# 都用同一份再掃一次，連 overlay、scripts 和產生的 project.yml。下面是匯出才要加的。
EXTRA_FORBIDDEN = [
    (re.compile(r"com\.geopilot\.gflyer\.ios\b"), "親友版的 Bundle ID"),
]
EXTRA_WARN = [
    (re.compile(r"github(?:usercontent)?\.com/(?!JetPiggy/)[A-Za-z0-9_.-]+", re.I),
     "連到 GitHub 上 JetPiggy 以外的帳戶（第三方程式庫和下載來源；品牌規則第 5 節）"),
    (re.compile(r"(?<![\w./])docs/[\w./-]+|HANDOFF\.md|make_brand_art|ipa_summary|check_public_sources"),
     "提到開發 repo 才有的文件或工具"),
]
# 親友版的檔案：公開版不可以有一模一樣的檔案（例如改了名的親友版圖檔）
FAMILY_ONLY = ("GFlyerIOS/Family", "GFlyerIOSTests/Family")
FAMILY_INFO_PLIST = "GFlyerIOS/Family/Info.plist"
# 不應出現在公開 repo 的檔案（不論在哪個資料夾），加上 check_public_sources.py 的 FORBIDDEN_FILE_SUFFIXES
FORBIDDEN_FILE_NAMES = {"CLAUDE.local.md", ".env"}
EXTRA_FORBIDDEN_SUFFIXES = {".p8", ".pfx", ".jks", ".keystore"}

# 目的資料夾裏要保留的東西：git 本身、不進版控的本機檔案和建置產物
PRESERVE = {".git", "CLAUDE.local.md", ".build", "build", "DerivedData", "GFlyerIOS.xcodeproj",
            "GFlyerIOS/Vendor/idevice"}
# 公開 repo 的 CI 步驟，--build 照這個次序跑
CI_STEPS = ("xcode", "licences", "idevice", "test", "archive")


class ExportError(Exception):
    pass


def step(message: str) -> None:
    print(f"\n== {message}", flush=True)


def load_rules():
    """scripts/check_public_sources.py 的禁用字清單（用這個 repo 現在的版本）。"""
    path = ROOT / "scripts" / "check_public_sources.py"
    sys.dont_write_bytecode = True  # 不在 scripts/ 留下 __pycache__
    spec = importlib.util.spec_from_file_location("check_public_sources", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(*args: str) -> str:
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise ExportError(f"git {' '.join(args)} 失敗：{result.stderr.strip()}")
    return result.stdout.strip()


def archive(commit: str, staging: Path) -> None:
    tar_path = staging.parent / "export.tar"
    with open(tar_path, "wb") as out:
        result = subprocess.run(["git", "-C", str(ROOT), "archive", "--format=tar", commit], stdout=out)
    if result.returncode != 0:
        raise ExportError("git archive 失敗")
    with tarfile.open(tar_path) as tar:
        for member in tar.getmembers():
            if member.issym() or member.islnk():
                raise ExportError(f"不處理連結：{member.name}")
            target = (staging / member.name).resolve()
            if staging.resolve() not in target.parents and target != staging.resolve():
                raise ExportError(f"路徑跑出暫存資料夾：{member.name}")
        try:
            tar.extractall(staging, filter="data")
        except TypeError:  # 沒有 filter 參數的舊版 Python；上面已逐個檢查過路徑
            tar.extractall(staging)
    tar_path.unlink()


def classify(staging: Path) -> None:
    known = INCLUDE | REPLACED | GENERATED | set(EXCLUDE)
    unknown = []
    for entry in sorted(staging.iterdir()):
        name = entry.name
        if name in SPLIT and entry.is_dir():
            for child in sorted(entry.iterdir()):
                path = f"{name}/{child.name}"
                if path not in known and not (SPLIT[name] and child.is_file()):
                    unknown.append(path)
        elif name not in known:
            unknown.append(name)
    if unknown:
        raise ExportError(
            "這些路徑還沒決定公不公開：" + "、".join(unknown)
            + "\n在 tools/export-public/export.py 的 INCLUDE / EXCLUDE 分類（拿不準就排除，並問使用者）。"
        )


def remove_excluded(staging: Path) -> list[str]:
    """拿走不公開的路徑和會被 overlay 取代的檔案；回傳拿走了哪些不公開的路徑和原因。"""
    removed = []
    for path in list(EXCLUDE) + sorted(REPLACED):
        target = staging / path
        if not target.exists():
            continue
        is_dir = target.is_dir()
        shutil.rmtree(target) if is_dir else target.unlink()
        if path in EXCLUDE:
            removed.append(f"{path}{'/' if is_dir else ''}（{EXCLUDE[path]}）")
    return removed


def public_project_yml(text: str) -> str:
    """開發 repo 的 project.yml 拿走親友版的 target 和 scheme、`- Family` 和全部註解（註解寫到親友版）。"""
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").split("\n")]
    kept: list[str] = []
    seen = {"targets": set(), "schemes": set()}
    section = None
    skipping = False
    for line in lines:
        if line.lstrip().startswith("#"):
            continue
        if line and not line.startswith(" "):
            section = line.split(":", 1)[0]
            skipping = False
        elif section in seen and re.fullmatch(r"  [A-Za-z0-9_-]+:", line):
            name = line.strip()[:-1]
            seen[section].add(name)
            skipping = name in (FAMILY_TARGETS if section == "targets" else FAMILY_SCHEMES)
        if not skipping:
            kept.append(line)

    for section, public, family in (("targets", PUBLIC_TARGETS, FAMILY_TARGETS),
                                    ("schemes", PUBLIC_SCHEMES, FAMILY_SCHEMES)):
        if seen[section] - public - family:
            raise ExportError(f"project.yml 有還沒分類的 {section}：" + "、".join(sorted(seen[section] - public - family))
                              + "\n在 tools/export-public/export.py 的 PUBLIC_ / FAMILY_ 清單分類。")
        if not public <= seen[section]:
            raise ExportError(f"project.yml 少了公開版的 {section}：" + "、".join(sorted(public - seen[section])))

    # 親友版的資料夾不匯出，排除它的 `- Family` 就不用了；排除清單因此空了的話，連 `excludes:` 一起拿走
    kept = [line for line in kept if line.strip() != "- Family"]
    result: list[str] = []
    for index, line in enumerate(kept):
        if line.strip() == "excludes:":
            following = kept[index + 1] if index + 1 < len(kept) else ""
            indent = len(line) - len(line.lstrip())
            if not (following.strip().startswith("- ") and len(following) - len(following.lstrip()) > indent):
                continue
        result.append(line)
    while result and not result[-1]:
        result.pop()
    output = PROJECT_HEADER + "\n".join(result) + "\n"

    # 剩下的引用全部要指向公開版的 target
    problems = []
    for number, line in enumerate(output.splitlines(), start=1):
        reference = (re.fullmatch(r"\s+- target: (\S+)", line)
                     or re.fullmatch(r"\s{8}(\S+): (?:all|\[.*\])", line)
                     or re.fullmatch(r"\s{8}- (\S+)", line))
        if reference and reference.group(1) not in PUBLIC_TARGETS:
            problems.append(f"第 {number} 行指向 {reference.group(1)}")
        if "Family" in line:
            problems.append(f"第 {number} 行有 Family")
    if problems:
        raise ExportError("產生的 project.yml 還有親友版的東西：" + "、".join(problems))
    return output


def apply_overlay(staging: Path) -> list[str]:
    applied = []
    for source in sorted(OVERLAY.rglob("*")):
        if source.is_file():
            relative = source.relative_to(OVERLAY)
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            applied.append(relative.as_posix())
    missing = [name for name in REPLACED if not (staging / name).exists()]
    if missing:
        raise ExportError("overlay 缺少公開版的檔案：" + "、".join(sorted(missing)))
    for name in ("LICENSE", "NOTICE", "CLAUDE.md"):
        if not (staging / name).is_file():
            raise ExportError(f"overlay 缺少 {name}")
    return applied


def files_under(base: Path) -> list[Path]:
    return sorted(p for p in base.rglob("*") if p.is_file())


def family_hashes(staging: Path, min_bytes: int) -> dict[str, str]:
    """親友版每個檔案的雜湊（改了名也認得出來），在拿走親友版之前算。"""
    hashes = {}
    for folder in FAMILY_ONLY:
        base = staging / folder
        if base.is_dir():
            for path in files_under(base):
                if path.stat().st_size >= min_bytes:
                    hashes[hashlib.sha256(path.read_bytes()).hexdigest()] = path.relative_to(staging).as_posix()
    return hashes


def family_settings(staging: Path) -> list[str]:
    """親友版 Info.plist 裏的私人設定（留言板、座標圖鑑、更新來源的網址）：公開版一個都不可以有。"""
    path = staging / FAMILY_INFO_PLIST
    if not path.is_file():
        raise ExportError(f"找不到 {FAMILY_INFO_PLIST}")
    info = plistlib.loads(path.read_bytes())
    return [value for key, value in info.items()
            if key.startswith("GFlyer") and isinstance(value, str) and value.strip()]


def scan(staging: Path, rules, family: dict[str, str], secrets: list[str]) -> list[tuple[str, str]]:
    forbidden = list(rules.FORBIDDEN) + EXTRA_FORBIDDEN
    forbidden += [(re.compile(re.escape(secret)), "親友版的私人設定") for secret in secrets]
    warn = list(rules.WARN) + EXTRA_WARN
    suffixes = set(rules.FORBIDDEN_FILE_SUFFIXES) | EXTRA_FORBIDDEN_SUFFIXES
    problems: list[str] = []
    warnings: list[tuple[str, str]] = []
    for path in files_under(staging):
        relative = path.relative_to(staging).as_posix()
        data = path.read_bytes()
        if path.name in FORBIDDEN_FILE_NAMES or path.suffix.lower() in suffixes:
            problems.append(f"{relative}：不應公開的檔案")
        if len(data) >= rules.MIN_HASHED_BYTES:
            same = family.get(hashlib.sha256(data).hexdigest())
            if same:
                problems.append(f"{relative}：和親友版的 {same} 一模一樣")
        for pattern, reason in forbidden:
            match = pattern.search(relative)
            if match:
                problems.append(f"{relative}：檔名有「{match.group(0)}」（{reason}）")
        text = rules.without_allowed_notices(relative, data.decode("utf-8", errors="replace"))
        for number, line in enumerate(text.splitlines(), start=1):
            for pattern, reason in forbidden:
                match = pattern.search(line)
                if match:
                    problems.append(f"{relative}:{number}：「{match.group(0)}」（{reason}）")
            for pattern, reason in warn:
                match = pattern.search(line)
                if match:
                    warnings.append((f"{relative}:{number}：{match.group(0)}", reason))
    if problems:
        raise ExportError("禁用字掃描沒有通過：\n  " + "\n  ".join(problems))
    return warnings


def check_destination(dest: Path) -> None:
    resolved = dest.resolve()
    root = ROOT.resolve()
    if resolved == root or root in resolved.parents or resolved in root.parents:
        raise ExportError(f"目的資料夾不可以是開發 repo 或它的上下層：{resolved}")
    if not resolved.exists() or not any(resolved.iterdir()):
        return
    looks_exported = (resolved / "GFlyerIOS" / "Public" / "Edition.swift").is_file()
    if (not looks_exported or (resolved / "GFlyerIOS" / "Family").exists()
            or (resolved / "tools" / "export-public").exists()):
        raise ExportError(f"{resolved} 不是空的，也不像之前匯出的公開版；不會覆蓋它。")


def is_preserved(relative: str) -> bool:
    return any(relative == kept or relative.startswith(kept + "/") for kept in PRESERVE)


def clear(folder: Path, prefix: str = "") -> None:
    """清空目的資料夾，保留 PRESERVE 的路徑（和它們所在的資料夾）。"""
    for entry in folder.iterdir():
        relative = prefix + entry.name
        if is_preserved(relative):
            continue
        if entry.is_dir() and any(kept.startswith(relative + "/") for kept in PRESERVE):
            clear(entry, relative + "/")
            continue
        shutil.rmtree(entry) if entry.is_dir() else entry.unlink()


def sync(staging: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    clear(dest)
    shutil.copytree(staging, dest, dirs_exist_ok=True)

    # 匯出的檔案和目的資料夾（扣掉保留的本機檔案）要一模一樣
    def exported_files(base: Path) -> set[str]:
        names = set()
        for path in files_under(base):
            relative = path.relative_to(base).as_posix()
            if not is_preserved(relative):
                names.add(relative)
        return names

    if exported_files(staging) != exported_files(dest):
        extra = sorted(exported_files(dest) ^ exported_files(staging))
        raise ExportError("目的資料夾和匯出的檔案不同：" + "、".join(extra[:20]))


def build(dest: Path, idevice: Path | None) -> None:
    if idevice:
        if not (idevice / "lib" / "libidevice_ffi.a").is_file():
            raise ExportError(f"{idevice} 沒有 lib/libidevice_ffi.a")
        vendor = dest / "GFlyerIOS" / "Vendor" / "idevice"
        if vendor.exists():
            shutil.rmtree(vendor)
        shutil.copytree(idevice, vendor)
        print(f"  用 {idevice} 的 idevice 程式庫")
    for name in CI_STEPS:
        print(f"\n  -- scripts/ci.sh {name}", flush=True)
        if subprocess.run(["bash", "scripts/ci.sh", name], cwd=dest).returncode != 0:
            raise ExportError(f"公開 repo 的 CI 步驟 {name} 在匯出的資料夾失敗")


def summary(staging: Path, dest: Path, removed: list[str], applied: list[str],
            warnings: list[tuple[str, str]], file_list: Path | None) -> None:
    files = [p.relative_to(staging).as_posix() for p in files_under(staging)]
    groups = Counter()
    for name in files:
        parts = name.split("/")
        if parts[0] in SPLIT and len(parts) > 2:
            key = "/".join(parts[:2])
        elif parts[0] in SPLIT and len(parts) == 2:
            key = f"{parts[0]}/（直接放在資料夾裏的檔案）"
        else:
            key = parts[0] if len(parts) > 1 else name
        groups[key] += 1
    print(f"\n公開內容：{len(files)} 個檔案 → {dest}")
    for key, count in sorted(groups.items()):
        print(f"  {count:4d}  {key}")
    print("沒有匯出：")
    for line in removed:
        print("  " + line)
    print("產生的：" + "、".join(sorted(GENERATED)))
    print("公開版自己的檔案（overlay）：" + "、".join(applied))
    if warnings:
        print(f"提醒（不擋匯出，請看過）：{len(warnings)} 處")
        for reason, count in Counter(reason for _, reason in warnings).items():
            print(f"  {count:4d}  {reason}")
        targets = Counter(where.split("：", 1)[1] for where, reason in warnings if reason == EXTRA_WARN[0][1])
        for target, count in sorted(targets.items()):
            print(f"        {count:4d}  {target}")
    if file_list:
        lines = files + ["", "# 提醒"] + [f"{where}（{reason}）" for where, reason in warnings]
        file_list.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"完整檔案清單：{file_list}")


def self_test() -> list[str]:
    """每一道關卡都要擋得住一個例子，乾淨的例子不可以被擋。不用 git，Windows 上也能跑。"""
    failures: list[str] = []
    rules = load_rules()

    def stops(action) -> bool:
        try:
            action()
        except ExportError:
            return True
        return False

    # project.yml：用這個 repo 現在的版本
    project = (ROOT / "project.yml").read_text(encoding="utf-8").replace("\r\n", "\n")
    try:
        public = public_project_yml(project)
        names = set(re.findall(r"^  ([A-Za-z0-9_-]+):$", public, re.M))
        known = PUBLIC_TARGETS | PUBLIC_SCHEMES | FAMILY_TARGETS | FAMILY_SCHEMES
        if names & known != PUBLIC_TARGETS | PUBLIC_SCHEMES:
            failures.append(f"產生的 project.yml 的 target 和 scheme 是 {sorted(names & known)}")
        comments = [line for line in public.splitlines() if line.lstrip().startswith("#")]
        if comments != PROJECT_HEADER.splitlines():
            failures.append("產生的 project.yml 留下了開發 repo 的註解")
    except ExportError as error:
        failures.append(f"現在的 project.yml 產生不了公開版：{error}")
    broken = {
        "多了沒有分類的 target": project.replace("targets:\n", "targets:\n  NewTarget:\n    type: application\n", 1),
        "少了公開版的 scheme": project.replace("  GFlyerPublic-Idevice:\n", "  GFlyerIOS-Idevice:\n", 1),
        "公開版依賴親友版": project.replace("      - target: GFlyerPublicTunnel\n",
                                    "      - target: GFlyerPublicTunnel\n      - target: GFlyerIOS\n", 1),
        "公開版編譯 Family": project.replace("      - path: GFlyerIOS/Public\n",
                                      "      - path: GFlyerIOS/Public\n      - path: GFlyerIOS/Family\n", 1),
    }
    for case, text in broken.items():
        if text == project:
            failures.append(f"project.yml 的例子「{case}」沒有改到東西")
        elif not stops(lambda: public_project_yml(text)):
            failures.append(f"project.yml {case}沒有被擋下")

    with tempfile.TemporaryDirectory(prefix="gflyer-ios-export-test-") as temp:
        base = Path(temp)

        def tree(name: str, paths) -> Path:
            root = base / name
            for path in paths:
                (root / path).mkdir(parents=True, exist_ok=True)
            return root

        def write(root: Path, files: dict[str, bytes]) -> Path:
            for path, data in files.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_bytes(data)
            return root

        # 分類
        everything = INCLUDE | REPLACED | GENERATED | set(EXCLUDE)
        if stops(lambda: classify(write(tree("clean", everything), {"GFlyerIOS/New.swift": b"x"}))):
            failures.append("分類好的路徑和資料夾裏直接放的檔案被擋下")
        for path in ("NewFolder", "GFlyerIOS/NewFolder", "GFlyerIOSTests/NewFolder", "scripts/new_tool.py"):
            root = tree(f"unknown-{len(list(base.iterdir()))}", everything)
            write(root, {f"{path}/x" if "." not in path else path: b"x"})
            if not stops(lambda: classify(root)):
                failures.append(f"沒有分類的 {path} 沒有被擋下")

        # 掃描
        copied = b"x" * rules.MIN_HASHED_BYTES
        family = {hashlib.sha256(copied).hexdigest(): "GFlyerIOS/Family/Art.png"}
        secret = "https://example.invalid/private.json"
        clean = write(base / "scan-clean", {
            "GFlyerIOS/UI/Clean.swift": b"let title = \"GFlyer\"\n",
            "README.md": b"see docs/APP_STORE_PLAN.md and https://github.com/someone/repo\n"
                         b"https://github.com/JetPiggy/GFlyer\n",
        })
        try:
            reasons = Counter(reason for _, reason in scan(clean, rules, family, [secret]))
            if reasons[EXTRA_WARN[0][1]] != 1 or reasons[EXTRA_WARN[1][1]] != 1:
                failures.append(f"提醒的數目不對：{dict(reasons)}")
        except ExportError as error:
            failures.append(f"乾淨的檔案被擋下：{error}")
        dirty = {
            "禁用字": {"README.md": b"SideStore\n"},
            "親友版的 Bundle ID": {"project.yml": b"PRODUCT_BUNDLE_IDENTIFIER: com.geopilot.gflyer.ios\n"},
            "親友版的私人設定": {"GFlyerIOS/Services/Sample.swift": f"let url = \"{secret}\"\n".encode()},
            "和親友版一模一樣的檔案": {"GFlyerIOS/Resources/Renamed.png": copied},
            "App Store Connect 的 API 金鑰": {"AuthKey_ABC.p8": b"key"},
            "本機的指示檔": {"CLAUDE.local.md": b"notes"},
            "檔名的禁用字": {"GFlyerIOS/Resources/Flower.png": b"png"},
        }
        for case, files in dirty.items():
            root = write(base / f"scan-{len(list(base.iterdir()))}", files)
            if not stops(lambda: scan(root, rules, family, [secret])):
                failures.append(f"{case}沒有被擋下")

        # 親友版 Info.plist 裏的私人設定讀得出來
        root = base / "family-plist"
        (root / FAMILY_INFO_PLIST).parent.mkdir(parents=True)
        shutil.copy2(ROOT / FAMILY_INFO_PLIST, root / FAMILY_INFO_PLIST)
        if not family_settings(root):
            failures.append(f"{FAMILY_INFO_PLIST} 讀不到私人設定")

        # 目的資料夾和同步
        exported = write(base / "dest-exported", {"GFlyerIOS/Public/Edition.swift": b"enum Edition {}\n"})
        if stops(lambda: check_destination(exported)):
            failures.append("之前匯出的資料夾被拒絕")
        for case, files in {"不像匯出的資料夾": {"a.txt": b"x"},
                            "有親友版的資料夾": {"GFlyerIOS/Public/Edition.swift": b"x", "GFlyerIOS/Family/a": b"x"}}.items():
            root = write(base / f"dest-{len(list(base.iterdir()))}", files)
            if not stops(lambda: check_destination(root)):
                failures.append(f"{case}沒有被拒絕")
        if not stops(lambda: check_destination(ROOT)):
            failures.append("開發 repo 本身沒有被拒絕")
        dest = write(base / "dest-sync", {".git/HEAD": b"x", "GFlyerIOS/Vendor/idevice/lib/a": b"x",
                                          "stale.txt": b"x", "GFlyerIOS/Old/old.swift": b"x"})
        sync(write(base / "staging", {"GFlyerIOS/Vendor/README.md": b"x", "new.txt": b"x"}), dest)
        kept = {p.relative_to(dest).as_posix() for p in files_under(dest)}
        if kept != {".git/HEAD", "GFlyerIOS/Vendor/idevice/lib/a", "GFlyerIOS/Vendor/README.md", "new.txt"}:
            failures.append(f"同步之後的目的資料夾是 {sorted(kept)}")
    return failures


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="匯出公開版（GFlyerPublic）原始碼")
    parser.add_argument("--commit", default="HEAD", help="要匯出的 commit（預設 HEAD）")
    parser.add_argument("--dest", type=Path, default=DEFAULT_DEST, help="公開 repo 的資料夾（預設 ../GFlyer-iOS-public）")
    parser.add_argument("--build", action="store_true", help="在目的資料夾跑公開 repo 的 CI 步驟（只限 Mac）")
    parser.add_argument("--idevice", type=Path, help="和 --build 一起用：先把這個建好的 idevice 資料夾複製過去")
    parser.add_argument("--file-list", type=Path, help="把完整檔案清單和提醒寫到這個檔")
    parser.add_argument("--self-test", action="store_true", help="確認分類、project.yml 和掃描擋得住，不匯出")
    args = parser.parse_args()
    if args.idevice and not args.build:
        parser.error("--idevice 要和 --build 一起用")
    if args.build and sys.platform != "darwin":
        parser.error("--build 要在裝了 Xcode 的 Mac 上跑；Windows 只能匯出和掃描")
    if args.self_test:
        failures = self_test()
        for failure in failures:
            print(f"self-test：{failure}", file=sys.stderr)
        if failures:
            return 1
        print("self-test 通過：分類、project.yml、禁用字、親友版的檔案和設定、目的資料夾")
        return 0

    try:
        rules = load_rules()
        commit = git("rev-parse", "--verify", f"{args.commit}^{{commit}}")
        step(f"匯出 {commit[:10]}（未 commit 的改動不會匯出）")
        if git("status", "--porcelain"):
            print("  注意：工作區有未 commit 的改動，它們不在這次匯出裏（overlay 和這個工具用的是工作區的版本）。")
        check_destination(args.dest)
        with tempfile.TemporaryDirectory(prefix="gflyer-ios-export-") as temp:
            staging = Path(temp) / "GFlyer"
            staging.mkdir()
            archive(commit, staging)

            step("分類與排除")
            classify(staging)
            family = family_hashes(staging, rules.MIN_HASHED_BYTES)
            secrets = family_settings(staging)
            project = public_project_yml((staging / "project.yml").read_text(encoding="utf-8"))
            removed = remove_excluded(staging)
            (staging / "project.yml").write_text(project, encoding="utf-8", newline="\n")
            applied = apply_overlay(staging)

            step("掃描禁用字")
            warnings = scan(staging, rules, family, secrets)
            print("  通過")

            step(f"同步到 {args.dest}")
            sync(staging, args.dest)

            if args.build:
                step("在匯出的資料夾跑公開 repo 的 CI 步驟")
                build(args.dest, args.idevice)
            else:
                print("\n（沒有加 --build：沒有建置和測試）")

            summary(staging, args.dest, removed, applied, warnings, args.file_list)
    except ExportError as error:
        print(f"\n停下：{error}", file=sys.stderr)
        return 1
    print("\n完成。還沒有 commit 或 push：把公開內容列給使用者確認之後才做。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
