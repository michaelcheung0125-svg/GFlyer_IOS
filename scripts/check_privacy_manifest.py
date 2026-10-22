#!/usr/bin/env python3
"""
核對建好的公開版 .app 的私隱清單 PrivacyInfo.xcprivacy（docs/APP_STORE_PLAN.md 第 20 項）。

    python3 scripts/check_privacy_manifest.py --app APP      核對建好的 .app
    python3 scripts/check_privacy_manifest.py --binary FILE  列出一個執行檔用到的指定原因 API
    python3 scripts/check_privacy_manifest.py --self-test    確認偵測和核對擋得住

App Store Connect 收到上傳的建置時，會掃描執行檔有沒有用到「指定原因 API」（required reason API），
用到的類別沒有寫進私隱清單就退回（ITMS-91053）。這裏照 Apple 的清單做同一件事：讀 App 和每個
extension 的 Mach-O 執行檔，從未定義的符號（例如 `_stat`、`_mach_absolute_time`、
`_OBJC_CLASS_$_NSUserDefaults`、`_NSURLVolumeAvailableCapacityKey`）和 Objective-C 的 selector 字串
（例如 `systemUptime`）找出用到的類別，和那個 bundle 的 PrivacyInfo.xcprivacy 比對。
連結進來的 `libidevice_ffi.a`（Rust）也在執行檔裏，所以一樣算進去；系統的 framework 不算。

清單沒有寫到用到的類別、原因不是那個類別准用的、或私隱清單的格式不對，就失敗。寫了但掃不到的
只是提醒：Apple 的掃描可能比這裏看得多，不要因為這裏掃不到就拿走。

類別、API 和原因照 Apple 的文件（2026-10-22 讀）：
https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
Apple 改了清單，這裏的 CATEGORIES 要一起改。不需要 Mac，Windows 上也能跑。
"""
from __future__ import annotations

import argparse
import plistlib
import struct
import sys
from pathlib import Path

# 每個類別：Mach-O 裏的未定義符號、Objective-C selector，和准用的原因
CATEGORIES: dict[str, dict[str, set[str]]] = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {
        "symbols": {
            "_stat", "_fstat", "_fstatat", "_lstat", "_stat64", "_fstat64", "_fstatat64", "_lstat64",
            "_getattrlist", "_getattrlistbulk", "_fgetattrlist", "_getattrlistat",
            "_NSFileCreationDate", "_NSFileModificationDate",
            "_NSURLContentModificationDateKey", "_NSURLCreationDateKey",
        },
        "selectors": {"fileModificationDate", "fileCreationDate"},
        "reasons": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    },
    "NSPrivacyAccessedAPICategorySystemBootTime": {
        "symbols": {"_mach_absolute_time"},
        "selectors": {"systemUptime"},
        "reasons": {"35F9.1", "8FFB.1", "3D61.1"},
    },
    "NSPrivacyAccessedAPICategoryDiskSpace": {
        "symbols": {
            "_statfs", "_statvfs", "_fstatfs", "_fstatvfs", "_statfs64", "_fstatfs64",
            "_getattrlist", "_fgetattrlist", "_getattrlistat",
            "_NSURLVolumeAvailableCapacityKey", "_NSURLVolumeAvailableCapacityForImportantUsageKey",
            "_NSURLVolumeAvailableCapacityForOpportunisticUsageKey", "_NSURLVolumeTotalCapacityKey",
            "_NSFileSystemFreeSize", "_NSFileSystemSize",
        },
        "selectors": set(),
        "reasons": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    },
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {
        "symbols": set(),
        "selectors": {"activeInputModes"},
        "reasons": {"3EC4.1", "54BD.1"},
    },
    "NSPrivacyAccessedAPICategoryUserDefaults": {
        "symbols": {"_OBJC_CLASS_$_NSUserDefaults"},
        "selectors": set(),
        "reasons": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
    },
}
MANIFEST = "PrivacyInfo.xcprivacy"
TOP_LEVEL_KEYS = {"NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"}

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_SYMTAB = 0x2


class NotMachO(Exception):
    pass


def macho_slices(data: bytes) -> list[bytes]:
    """每個架構的 Mach-O；fat binary 拆開。只處理 64 位元。"""
    if len(data) < 8:
        raise NotMachO("太短")
    (magic_be,) = struct.unpack_from(">I", data, 0)
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        (count,) = struct.unpack_from(">I", data, 4)
        slices = []
        for index in range(count):
            if magic_be == FAT_MAGIC:
                _, _, offset, size, _ = struct.unpack_from(">5I", data, 8 + index * 20)
            else:
                _, _, offset, size, _, _ = struct.unpack_from(">2I2Q2I", data, 8 + index * 32)
            slices.append(data[offset:offset + size])
        return slices
    (magic_le,) = struct.unpack_from("<I", data, 0)
    if magic_le != MH_MAGIC_64:
        raise NotMachO(f"magic 0x{magic_le:08x}")
    return [data]


def undefined_symbols(macho: bytes) -> set[str]:
    """64 位元 Mach-O 的未定義外部符號（nm -u）。"""
    _, _, _, _, ncmds, _, _, _ = struct.unpack_from("<8I", macho, 0)
    offset = 32
    names: set[str] = set()
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<2I", macho, offset)
        if cmd == LC_SYMTAB:
            _, _, symoff, nsyms, stroff, strsize = struct.unpack_from("<6I", macho, offset)
            strings = macho[stroff:stroff + strsize]
            for index in range(nsyms):
                strx, n_type, _, _, _ = struct.unpack_from("<IBBHQ", macho, symoff + index * 16)
                # 不是 debug 符號、類型是 N_UNDF、而且是外部的
                if n_type & 0xE0 == 0 and n_type & 0x0E == 0 and n_type & 0x01:
                    end = strings.find(b"\0", strx)
                    names.add(strings[strx:end].decode("utf-8", "replace"))
        offset += size
    return names


def used_categories(data: bytes) -> dict[str, list[str]]:
    """執行檔用到的類別，和看到的符號或 selector。"""
    symbols: set[str] = set()
    for macho in macho_slices(data):
        symbols |= undefined_symbols(macho)
    found: dict[str, list[str]] = {}
    for category, spec in CATEGORIES.items():
        hits = sorted(symbols & spec["symbols"])
        # selector 是 __objc_methname 裏以 NUL 結尾的字串
        hits += [f"selector {name}" for name in sorted(spec["selectors"]) if b"\0" + name.encode() + b"\0" in data]
        if hits:
            found[category] = hits
    return found


def check_manifest(manifest: dict) -> tuple[list[str], dict[str, list[str]]]:
    """私隱清單的格式問題，和寫了的類別與原因。"""
    problems = []
    unknown = set(manifest) - TOP_LEVEL_KEYS
    if unknown:
        problems.append(f"不認識的鍵：{', '.join(sorted(unknown))}")
    for key in sorted(TOP_LEVEL_KEYS - set(manifest)):
        problems.append(f"少了 {key}")
    tracking = manifest.get("NSPrivacyTracking")
    if not isinstance(tracking, bool):
        problems.append("NSPrivacyTracking 要是 Boolean")
    domains = manifest.get("NSPrivacyTrackingDomains", [])
    if not isinstance(domains, list):
        problems.append("NSPrivacyTrackingDomains 要是陣列")
    elif domains and tracking is not True:
        problems.append("有 NSPrivacyTrackingDomains 時 NSPrivacyTracking 要是 true")
    if not isinstance(manifest.get("NSPrivacyCollectedDataTypes", []), list):
        problems.append("NSPrivacyCollectedDataTypes 要是陣列")
    declared: dict[str, list[str]] = {}
    entries = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(entries, list):
        problems.append("NSPrivacyAccessedAPITypes 要是陣列")
        entries = []
    for entry in entries:
        category = entry.get("NSPrivacyAccessedAPIType") if isinstance(entry, dict) else None
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons") if isinstance(entry, dict) else None
        if category not in CATEGORIES:
            problems.append(f"不認識的類別：{category}")
            continue
        if category in declared:
            problems.append(f"{category} 寫了兩次")
        if not isinstance(reasons, list) or not reasons:
            problems.append(f"{category} 沒有原因")
            reasons = []
        for reason in reasons:
            if reason not in CATEGORIES[category]["reasons"]:
                problems.append(f"{category} 不准用原因 {reason}")
        declared[category] = list(reasons)
    return problems, declared


def executables(app: Path) -> list[Path]:
    """App 和它裏面每個 extension、framework 的 bundle。"""
    bundles = [app]
    for folder, suffix in (("PlugIns", ".appex"), ("Extensions", ".appex"), ("Frameworks", ".framework")):
        bundles += sorted(p for p in (app / folder).glob(f"*{suffix}") if p.is_dir())
    return bundles


def bundle_executable(bundle: Path) -> Path | None:
    info = bundle / "Info.plist"
    if not info.is_file():
        return None
    name = plistlib.loads(info.read_bytes()).get("CFBundleExecutable")
    return bundle / name if name else None


def check_app(app: Path) -> tuple[list[str], list[str], list[str]]:
    """問題、提醒，和每個 bundle 的摘要。"""
    problems: list[str] = []
    warnings: list[str] = []
    lines: list[str] = []
    for bundle in executables(app):
        name = bundle.relative_to(app.parent).as_posix()
        executable = bundle_executable(bundle)
        if executable is None or not executable.is_file():
            problems.append(f"{name}：找不到執行檔")
            continue
        used = used_categories(executable.read_bytes())
        manifest_path = bundle / MANIFEST
        if manifest_path.is_file():
            try:
                manifest = plistlib.loads(manifest_path.read_bytes())
            except Exception as error:  # plistlib 對壞檔丟的例外種類不一
                problems.append(f"{name}/{MANIFEST} 讀不到：{error}")
                continue
            format_problems, declared = check_manifest(manifest)
            problems += [f"{name}/{MANIFEST}：{p}" for p in format_problems]
        elif bundle == app:
            problems.append(f"{name} 沒有 {MANIFEST}")
            declared = {}
        else:
            declared = {}
        for category, hits in used.items():
            if category not in declared:
                problems.append(f"{name} 用到 {category}（{', '.join(hits)}），{MANIFEST} 沒有寫")
        for category in declared:
            if category not in used:
                warnings.append(f"{name}/{MANIFEST} 寫了 {category}，執行檔裏掃不到")
        summary = ", ".join(f"{c.removeprefix('NSPrivacyAccessedAPICategory')}" for c in sorted(used)) or "沒有"
        lines.append(f"{name}：用到 {summary}")
    return problems, warnings, lines


# ── self-test ──────────────────────────────────────────────────

def fake_macho(undefined: list[str], defined: list[str] = (), extra: bytes = b"") -> bytes:
    """只有 LC_SYMTAB 的 64 位元 Mach-O。"""
    strings = b"\0"
    entries = []
    for name, n_type in [(n, 0x01) for n in undefined] + [(n, 0x0F) for n in defined]:
        entries.append((len(strings), n_type))
        strings += name.encode() + b"\0"
    header_size = 32 + 24
    symoff = header_size
    stroff = symoff + 16 * len(entries)
    data = struct.pack("<8I", MH_MAGIC_64, 0x0100000C, 0, 2, 1, 24, 0, 0)
    data += struct.pack("<6I", LC_SYMTAB, 24, symoff, len(entries), stroff, len(strings))
    for strx, n_type in entries:
        data += struct.pack("<IBBHQ", strx, n_type, 0, 0, 0)
    return data + strings + extra


def fake_fat(slices: list[bytes]) -> bytes:
    header = struct.pack(">2I", FAT_MAGIC, len(slices))
    offset = 8 + 20 * len(slices)
    body = b""
    for macho in slices:
        header += struct.pack(">5I", 0x0100000C, 0, offset + len(body), len(macho), 0)
        body += macho
    return header + body


def self_test() -> list[str]:
    failures = []

    def expect(label: str, actual, wanted):
        if actual != wanted:
            failures.append(f"{label}：得到 {actual!r}，應該是 {wanted!r}")

    binary = fake_macho(
        ["_stat", "_OBJC_CLASS_$_NSUserDefaults", "_printf"],
        defined=["_mach_absolute_time"],
        extra=b"\0systemUptime\0",
    )
    expect("未定義的符號和 selector", sorted(used_categories(binary)), sorted([
        "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPICategorySystemBootTime",
        "NSPrivacyAccessedAPICategoryUserDefaults",
    ]))
    expect("自己定義的符號不算", "_mach_absolute_time" in str(used_categories(binary)), False)
    expect("selector 要整個字串相同", used_categories(fake_macho([], extra=b"\0systemUptimeX\0")), {})
    expect("fat binary 每個架構都看", sorted(used_categories(fake_fat([fake_macho(["_statfs"]), fake_macho(["_mach_absolute_time"])]))), [
        "NSPrivacyAccessedAPICategoryDiskSpace",
        "NSPrivacyAccessedAPICategorySystemBootTime",
    ])
    expect("getattrlist 兩個類別都算", sorted(used_categories(fake_macho(["_getattrlist"]))), [
        "NSPrivacyAccessedAPICategoryDiskSpace",
        "NSPrivacyAccessedAPICategoryFileTimestamp",
    ])
    try:
        macho_slices(b"\x7fELF0000")
        failures.append("不是 Mach-O 也接受了")
    except NotMachO:
        pass

    good = {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]},
        ],
    }
    expect("正確的清單", check_manifest(good), ([], {"NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]}))
    bad_reason = dict(good, NSPrivacyAccessedAPITypes=[
        {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["35F9.1"]},
    ])
    expect("別的類別的原因", len(check_manifest(bad_reason)[0]), 1)
    expect("少了鍵", len(check_manifest({"NSPrivacyTracking": False})[0]), 3)
    expect("有追蹤網域卻不追蹤", len(check_manifest(dict(good, NSPrivacyTrackingDomains=["example.com"]))[0]), 1)
    expect("沒有原因", len(check_manifest(dict(good, NSPrivacyAccessedAPITypes=[
        {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPITypeReasons": []},
    ]))[0]), 1)
    return failures


def self_test_app() -> list[str]:
    """在暫存資料夾做一個假的 .app，走一次 check_app。"""
    import tempfile

    failures = []
    manifest = {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]},
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPITypeReasons": ["E174.1"]},
        ],
    }
    with tempfile.TemporaryDirectory() as temp:
        app = Path(temp) / "Fake.app"
        extension = app / "PlugIns" / "Fake.appex"
        extension.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Fake"}))
        (app / "Fake").write_bytes(fake_macho(["_OBJC_CLASS_$_NSUserDefaults", "_stat"]))
        (app / MANIFEST).write_bytes(plistlib.dumps(manifest))
        (extension / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Fake"}))
        (extension / "Fake").write_bytes(fake_macho(["_mach_absolute_time"]))
        problems, warnings, _ = check_app(app)
        wanted_problems = [
            "Fake.app 用到 NSPrivacyAccessedAPICategoryFileTimestamp（_stat），PrivacyInfo.xcprivacy 沒有寫",
            "Fake.app/PlugIns/Fake.appex 用到 NSPrivacyAccessedAPICategorySystemBootTime（_mach_absolute_time），PrivacyInfo.xcprivacy 沒有寫",
        ]
        if problems != wanted_problems:
            failures.append(f"假 App 的問題：{problems}")
        if warnings != ["Fake.app/PrivacyInfo.xcprivacy 寫了 NSPrivacyAccessedAPICategoryDiskSpace，執行檔裏掃不到"]:
            failures.append(f"假 App 的提醒：{warnings}")
        (app / MANIFEST).unlink()
        problems, _, _ = check_app(app)
        if "Fake.app 沒有 PrivacyInfo.xcprivacy" not in problems:
            failures.append("App 沒有私隱清單也接受了")
    return failures


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--app", type=Path, help="核對建好的 .app")
    group.add_argument("--binary", type=Path, help="列出一個執行檔用到的指定原因 API")
    group.add_argument("--self-test", action="store_true", help="確認偵測和核對擋得住")
    args = parser.parse_args()

    if args.self_test:
        failures = self_test() + self_test_app()
        for failure in failures:
            print(f"self-test：{failure}", file=sys.stderr)
        if failures:
            return 1
        print(f"self-test 通過：{len(CATEGORIES)} 個類別、fat binary、私隱清單的格式和假的 .app")
        return 0

    if args.binary:
        used = used_categories(args.binary.read_bytes())
        for category, hits in used.items():
            print(f"{category}：{', '.join(hits)}")
        if not used:
            print("沒有用到指定原因 API")
        return 0

    if not (args.app / "Info.plist").is_file():
        print(f"{args.app} 不是建好的 .app", file=sys.stderr)
        return 1
    problems, warnings, lines = check_app(args.app)
    for line in lines:
        print(line)
    for warning in warnings:
        print(f"提醒 {warning}")
    if problems:
        print(f"私隱清單核對沒有通過（{len(problems)} 項）：", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print("照 docs/APP_STORE_PLAN.md 第 20 項更新 GFlyerIOS/Public/PrivacyInfo.xcprivacy。", file=sys.stderr)
        return 1
    print(f"私隱清單核對通過：{len(lines)} 個執行檔，{len(warnings)} 個提醒")
    return 0


if __name__ == "__main__":
    sys.exit(main())
