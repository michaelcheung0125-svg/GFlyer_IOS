#!/usr/bin/env python3
"""
產生 App 內「開放原始碼授權」頁的清單（docs/APP_STORE_PLAN.md 第 18 項，GFlyer-Suite DRIFT D34）。

    python3 -I scripts/open_source_licenses.py --source DIR           核對 GFlyerIOS/Resources/OpenSourceLicenses.json
    python3 -I scripts/open_source_licenses.py --source DIR --write   重新產生那個檔
    加 --out FILE 另外寫一份產生的結果（CI 把它上傳成 artifact）

DIR 是 idevice 在 scripts/build_idevice.sh 釘住的 revision 的原始碼；CI 的「Open source licences」job 會下載。
要有 cargo，cargo 會下載各套件的原始碼來讀授權檔。

App 打包的第三方程式只有 libidevice_ffi.a：idevice 和它連結的 Rust 套件，加上 Rust 標準程式庫。
清單照 build_idevice.sh 那一句 cargo build（同一個 package、target、features，從 build_idevice.sh 讀，
不會不同步）用 cargo tree 列出，只算一般的依賴：build script 和 proc macro 只在建置時執行，沒有編進 App。
每個套件的授權是 Cargo.toml 的 license；全文是套件裏附的 LICENSE、COPYING、NOTICE 等檔案，原樣放進去。
套件沒有附全文時，授權可以選 Apache-2.0 的就用 Apache-2.0 的全文（scripts/licenses/apache-2.0.txt）。

下面任何一種情況都會失敗，照訊息補上或改 OVERRIDES：
- 套件的 Cargo.toml 沒有寫 license
- 套件沒有附全文，授權又不能選 Apache-2.0
- OVERRIDES 給了全文，套件卻已經自己附了（上游補上了，OVERRIDES 要拿掉）
- OVERRIDES 裏的套件已經不在清單上（依賴拿走了，這裏沒跟着改）
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "build_idevice.sh"
OUTPUT = ROOT / "GFlyerIOS" / "Resources" / "OpenSourceLicenses.json"
LICENSE_DIR = ROOT / "scripts" / "licenses"
APACHE_TEXT = LICENSE_DIR / "apache-2.0.txt"
APACHE_TITLE = "Apache License 2.0"
# MIT 的標準全文，版權那一行是 {holder}（和 jkcoxson/jktcp 附的 LICENSE 同一份字）
MIT_TEMPLATE = LICENSE_DIR / "mit.txt"
MIT_TITLE = "MIT License"

# 自動做不到的部分，鍵是套件名稱。
#   license    Cargo.toml 沒寫或寫錯時的授權
#   text       套件沒有附全文時用的全文，scripts/licenses/ 裏的檔名（從上游 repo 抄來，寫明出處）
#   mitHolder  套件沒有附全文、上游 repo 也沒有時：Cargo.toml 寫 MIT，用 MIT 的標準全文配上 authors 寫的作者
OVERRIDES: dict[str, dict[str, str]] = {
    # idevice 的 FFI 套件沒有寫 license；整個 repo 是 MIT（根目錄的 LICENSE.txt，THIRD_PARTY_NOTICES.md）
    "idevice-ffi": {"license": "MIT"},
    # 這兩個套件和上游 repo（jkcoxson/plist_macro、jkcoxson/plist_ffi，2026-10-22 看過）都沒有授權檔，
    # 只有 Cargo.toml 寫 license = "MIT"、authors = ["Jackson Coxson"]
    "plist-macro": {"mitHolder": "Jackson Coxson"},
    "plist_ffi": {"mitHolder": "Jackson Coxson"},
}

# Rust 標準程式庫靜態連結在 libidevice_ffi.a 裏。它跟着 CI 當時的 Rust 編譯器，所以不寫版本；
# 授權是 Apache-2.0 或 MIT 任選（Rust 附的 COPYRIGHT-library），這裏附 Apache-2.0 的全文。
RUST_STD_NAME = "Rust 標準程式庫"
RUST_STD_LICENSE = "Apache-2.0 OR MIT"

# 套件根目錄裏算是授權全文的檔名
LICENSE_FILE = re.compile(r"^(licen[cs]e|copying|copyright|notice|unlicense)([-_. ].*)?$", re.I)
NOTICE_FILE = re.compile(r"^notice", re.I)


class LicenseError(Exception):
    pass


def build_settings() -> dict[str, object]:
    """build_idevice.sh 釘住的 revision 和 cargo build 的參數。"""
    script = BUILD_SCRIPT.read_text(encoding="utf-8")

    def find(pattern: str) -> str:
        match = re.search(pattern, script, re.M)
        if match is None:
            raise LicenseError(f"build_idevice.sh 裏找不到 {pattern}")
        return match.group(1)

    return {
        "revision": find(r'^IDEVICE_REVISION="([0-9a-f]{40})"$'),
        "package": find(r"--package (\S+)"),
        "target": find(r"--target (\S+)"),
        "noDefaultFeatures": "--no-default-features" in script,
        "features": find(r'--features "([^"]*)"').split(),
    }


def cargo(source: Path, args: list[str], offline: bool) -> str:
    command = ["cargo", *args, "--locked"] + (["--offline"] if offline else [])
    result = subprocess.run(command, cwd=source, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise LicenseError(f"{' '.join(command)} 失敗：\n{result.stderr}")
    return result.stdout


def linked_packages(source: Path, settings: dict[str, object], offline: bool) -> list[tuple[str, str]]:
    """cargo build 會編進 libidevice_ffi.a 的套件（名稱、版本）。"""
    args = ["tree", "--package", str(settings["package"]), "--target", str(settings["target"])]
    if settings["noDefaultFeatures"]:
        args.append("--no-default-features")
    args += ["--features", " ".join(settings["features"])]
    args += ["--edges", "normal,no-proc-macro", "--prefix", "none", "--format", "{p}"]
    packages = set()
    for line in cargo(source, args, offline).splitlines():
        match = re.match(r"^(\S+) v(\S+)", line)
        if match:
            packages.add((match.group(1), match.group(2)))
    if not packages:
        raise LicenseError("cargo tree 沒有列出任何套件")
    return sorted(packages)


def normalized(text: str) -> str:
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    return "\n".join(lines).strip("\n") + "\n"


def read_text(path: Path) -> str:
    try:
        return normalized(path.read_bytes().decode("utf-8"))
    except UnicodeDecodeError as error:
        raise LicenseError(f"{path} 不是 UTF-8：{error}") from error


def license_files(directory: Path, license_file: str | None) -> list[Path]:
    files = [path for path in directory.iterdir() if path.is_file() and LICENSE_FILE.match(path.name)]
    if license_file:
        declared = (directory / license_file).resolve()
        if declared.is_file() and declared not in [path.resolve() for path in files]:
            files.append(declared)
    # NOTICE 先，其餘照檔名
    return sorted(files, key=lambda path: (not NOTICE_FILE.match(path.name), path.name.lower()))


def can_choose_apache(expression: str) -> bool:
    choices = re.split(r"\s+OR\s+|/", expression)
    return any(choice.strip(" ()") == "Apache-2.0" for choice in choices)


def generate(source: Path, offline: bool) -> str:
    settings = build_settings()
    head = subprocess.run(["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True)
    if head.returncode != 0 or head.stdout.strip() != settings["revision"]:
        raise LicenseError(f"{source} 不是 build_idevice.sh 釘住的 idevice {settings['revision']}")

    metadata = json.loads(cargo(source, [
        "metadata", "--format-version", "1", "--filter-platform", str(settings["target"]),
    ], offline))
    workspace_root = Path(metadata["workspace_root"])
    by_key: dict[tuple[str, str], dict] = {}
    for package in metadata["packages"]:
        key = (package["name"], package["version"])
        if key in by_key:
            raise LicenseError(f"有兩個 {key[0]} {key[1]}，分不出是哪一個")
        by_key[key] = package

    texts: dict[str, str] = {}
    apache = read_text(APACHE_TEXT)

    def add_text(text: str) -> str:
        key = hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]
        texts[key] = text
        return key

    libraries = []
    problems = []
    linked = linked_packages(source, settings, offline)
    for name, version in linked:
        package = by_key.get((name, version))
        if package is None:
            raise LicenseError(f"cargo metadata 裏沒有 {name} {version}")
        override = OVERRIDES.get(name, {})
        expression = override.get("license") or package.get("license")
        directory = Path(package["manifest_path"]).parent
        files = license_files(directory, package.get("license_file"))
        if not files and package.get("source") is None:
            # 同一個 repo 的套件（idevice 自己）：授權檔在 repo 的根目錄
            files = license_files(workspace_root, None)
        if not expression:
            problems.append(f"{name} {version}：Cargo.toml 沒有寫 license，在 OVERRIDES 補上")
            continue
        entries = [{"title": path.name, "text": add_text(read_text(path))} for path in files]
        if entries and ("text" in override or "mitHolder" in override):
            problems.append(f"{name} {version}：套件已經附了授權全文，OVERRIDES 的全文要拿掉")
            continue
        if "text" in override:
            entries = [{"title": "LICENSE", "text": add_text(read_text(LICENSE_DIR / override["text"]))}]
        elif "mitHolder" in override:
            if expression != "MIT":
                problems.append(f"{name} {version}：授權是 {expression}，不是 MIT，mitHolder 不適用")
                continue
            text = read_text(MIT_TEMPLATE).replace("{holder}", override["mitHolder"])
            entries = [{"title": MIT_TITLE, "text": add_text(text)}]
        elif not entries:
            if not can_choose_apache(expression):
                problems.append(f"{name} {version}（{expression}）：套件沒有附授權全文，在 OVERRIDES 補上")
                continue
            entries = [{"title": APACHE_TITLE, "text": add_text(apache)}]
        libraries.append({"name": name, "version": version, "license": expression, "texts": entries})

    stale = sorted(set(OVERRIDES) - {name for name, _ in linked})
    problems += [f"OVERRIDES 裏的 {name} 已經不在清單上" for name in stale]
    if problems:
        raise LicenseError("\n".join(problems))

    libraries.append({
        "name": RUST_STD_NAME, "version": "", "license": RUST_STD_LICENSE,
        "texts": [{"title": APACHE_TITLE, "text": add_text(apache)}],
    })
    libraries.sort(key=lambda library: (library["name"].lower(), library["version"]))
    data = {
        "idevice": {key: settings[key] for key in ("revision", "package", "target", "features")},
        "libraries": libraries,
        "texts": dict(sorted(texts.items())),
    }
    return json.dumps(data, ensure_ascii=False, indent=1) + "\n"


def summary(text: str) -> set[str]:
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return set()
    return {f"{library['name']} {library['version']}（{library['license']}）" for library in data.get("libraries", [])}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="產生或核對「開放原始碼授權」頁的清單")
    parser.add_argument("--source", type=Path, required=True, help="idevice 的原始碼（build_idevice.sh 釘住的 revision）")
    parser.add_argument("--write", action="store_true", help=f"寫進 {OUTPUT.relative_to(ROOT).as_posix()}")
    parser.add_argument("--out", type=Path, help="另外寫一份產生的結果")
    parser.add_argument("--offline", action="store_true", help="只用 cargo 已經下載的套件")
    args = parser.parse_args()

    try:
        generated = generate(args.source.resolve(), args.offline)
    except LicenseError as error:
        print(f"產生不到授權清單：\n{error}", file=sys.stderr)
        return 1
    if args.out:
        args.out.write_text(generated, encoding="utf-8", newline="\n")
    count = len(json.loads(generated)["libraries"])
    if args.write:
        OUTPUT.write_text(generated, encoding="utf-8", newline="\n")
        print(f"已寫入 {OUTPUT.relative_to(ROOT).as_posix()}：{count} 個程式庫")
        return 0

    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
    if current == generated:
        print(f"授權清單和連結的程式庫相符：{count} 個程式庫")
        return 0
    old, new = summary(current), summary(generated)
    print(f"{OUTPUT.relative_to(ROOT).as_posix()} 和 idevice 實際連結的不同，用 --write 重新產生：", file=sys.stderr)
    for line in sorted(new - old):
        print(f"  + {line}", file=sys.stderr)
    for line in sorted(old - new):
        print(f"  - {line}", file=sys.stderr)
    if old == new:
        print("  （程式庫相同，授權全文不同）", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
