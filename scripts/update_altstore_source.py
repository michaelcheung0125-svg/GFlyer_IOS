#!/usr/bin/env python3
"""Add or update a GFlyer iOS version entry in the public AltStore source.

The AltStore/SideStore source lives in the separate public GFlyer-updates
repository, next to the Android `latest.json`. This script reads the real
version, build, bundle identifier and minimum iOS version out of a built IPA,
measures its size and SHA-256, and writes the matching `versions[]` entry.

Usage:

    python3 scripts/update_altstore_source.py \
        --ipa artifacts/<commit>/GFlyerIOS-Idevice-unsigned.ipa \
        --source ../GFlyer-updates/altstore.json \
        --tag ios-v0.3.0 \
        --notes "本次更新內容"

The download URL defaults to the GFlyer-updates release asset for `--tag`,
matching how the Android APK is published.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import plistlib
import sys
import zipfile
from pathlib import Path

DEFAULT_RELEASE_URL = (
    "https://github.com/michaelcheung0125-svg/GFlyer-updates"
    "/releases/download/{tag}/{filename}"
)


def read_ipa_metadata(ipa_path: Path) -> dict:
    """Pull the app Info.plist out of an IPA without unpacking the whole file."""
    with zipfile.ZipFile(ipa_path) as archive:
        candidates = [
            name
            for name in archive.namelist()
            if name.startswith("Payload/")
            and name.endswith(".app/Info.plist")
            and name.count("/") == 2
        ]
        if not candidates:
            raise SystemExit(f"在 {ipa_path} 找不到 Payload/*.app/Info.plist")
        with archive.open(candidates[0]) as handle:
            info = plistlib.load(handle)

    missing = [
        key
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion")
        if not info.get(key)
    ]
    if missing:
        raise SystemExit(f"IPA 的 Info.plist 缺少欄位：{', '.join(missing)}")

    return {
        "bundleIdentifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "buildVersion": str(info["CFBundleVersion"]),
        "minOSVersion": info.get("MinimumOSVersion"),
    }


def version_key(version: str, build: str) -> tuple:
    """行銷版本優先、build 次之，逐段以數字比較。"""

    def parts(value: str) -> tuple:
        result = []
        for segment in str(value).split("."):
            digits = ""
            for char in segment:
                if not char.isdigit():
                    break
                digits += char
            result.append(int(digits) if digits else 0)
        return tuple(result)

    return (parts(version), parts(build))


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path, help="已建置的 IPA 路徑")
    parser.add_argument("--source", required=True, type=Path, help="altstore.json 路徑")
    parser.add_argument("--tag", help="GFlyer-updates 的 release tag，例如 ios-v0.3.0")
    parser.add_argument("--url", help="自訂下載網址，預設用 --tag 組出 release 資產網址")
    parser.add_argument("--notes", default="", help="這個版本的更新說明")
    parser.add_argument("--date", help="發佈日期 YYYY-MM-DD，預設今天（UTC）")
    args = parser.parse_args()

    if not args.ipa.is_file():
        raise SystemExit(f"找不到 IPA：{args.ipa}")
    if not args.source.is_file():
        raise SystemExit(f"找不到來源檔：{args.source}")
    if not args.url and not args.tag:
        raise SystemExit("必須提供 --tag 或 --url")

    metadata = read_ipa_metadata(args.ipa)
    download_url = args.url or DEFAULT_RELEASE_URL.format(
        tag=args.tag, filename=args.ipa.name
    )
    # SideStore 期望 ISO-8601 帶時間的日期；只給日期會解析失敗
    if args.date:
        release_date = args.date if "T" in args.date else f"{args.date}T00:00:00Z"
    else:
        release_date = datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )

    source = json.loads(args.source.read_text(encoding="utf-8"))
    apps = [
        app
        for app in source.get("apps", [])
        if app.get("bundleIdentifier") == metadata["bundleIdentifier"]
    ]
    if not apps:
        raise SystemExit(
            f"來源檔沒有 bundle identifier 為 {metadata['bundleIdentifier']} 的 App"
        )
    app = apps[0]

    entry = {
        "version": metadata["version"],
        "buildVersion": metadata["buildVersion"],
        "date": release_date,
        "localizedDescription": args.notes,
        "downloadURL": download_url,
        "size": args.ipa.stat().st_size,
        "sha256": sha256_of(args.ipa),
    }
    if metadata["minOSVersion"]:
        entry["minOSVersion"] = metadata["minOSVersion"]

    # 同一個 version+build 視為重新發佈，就地取代；否則插到最前面（最新版在前）
    versions = app.get("versions", [])
    existing = next(
        (
            index
            for index, item in enumerate(versions)
            if item.get("version") == entry["version"]
            and item.get("buildVersion") == entry["buildVersion"]
        ),
        None,
    )
    if existing is None:
        versions.insert(0, entry)
        action = "新增"
    else:
        if not args.notes:
            entry["localizedDescription"] = versions[existing].get(
                "localizedDescription", ""
            )
        versions[existing] = entry
        action = "更新"
    app["versions"] = versions

    # SideStore 讀的是 App 物件上的扁平欄位，不是只有 versions 陣列。
    # 少了這些欄位，加入來源時會出現 StoreApp is not valid。
    newest = max(
        versions,
        key=lambda item: version_key(item.get("version", "0"), item.get("buildVersion", "0")),
    )
    app["version"] = newest["version"]
    app["buildVersion"] = newest.get("buildVersion", newest["version"])
    app["versionDate"] = newest["date"]
    app["versionDescription"] = newest.get("localizedDescription", "")
    app["downloadURL"] = newest["downloadURL"]
    app["size"] = newest["size"]

    args.source.write_text(
        json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"已{action} {app.get('name', 'App')} {entry['version']} ({entry['buildVersion']})\n"
        f"  下載網址 {entry['downloadURL']}\n"
        f"  大小 {entry['size']} bytes\n"
        f"  SHA-256 {entry['sha256']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
