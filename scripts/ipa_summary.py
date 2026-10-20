#!/usr/bin/env python3
"""Print a summary of an unsigned GFlyer IPA that can be diffed between builds.

Used to check that a build change leaves an app's contents alone, for example
splitting project.yml into two editions (docs/APP_STORE_PLAN.md item 8): run it
on the IPA from before and after, then diff the two outputs.

Sections:
- files: every file in the app bundle with its size and SHA-256. The main
  executable's hash changes whenever any code changes; the other sections say
  whether the change matters.
- Info.plist: the compiled plist with sorted keys.
- Assets.car: one line per rendition from `assetutil --info` (macOS only),
  without the catalog's timestamp.
- strings: null-terminated UTF-8 strings in the executable that contain
  Chinese characters, which is where the app's wording ends up. Swift keeps
  strings of 15 bytes or less inside the instructions, so short labels are not
  listed.

Usage: python3 scripts/ipa_summary.py <app.ipa>
"""

import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def find_app(payload: Path) -> Path:
    apps = sorted(payload.glob("*.app"))
    if len(apps) != 1:
        raise SystemExit(f"Expected one .app in {payload}, found {len(apps)}")
    return apps[0]


def print_files(app: Path) -> None:
    print("## files")
    for path in sorted(p for p in app.rglob("*") if p.is_file()):
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        print(f"{path.relative_to(app).as_posix()}\t{len(data)}\t{digest}")


def print_info_plist(app: Path) -> dict:
    print("## Info.plist")
    with (app / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    print(json.dumps(info, ensure_ascii=False, indent=2, sort_keys=True, default=str))
    return info


def print_assets(app: Path) -> None:
    print("## Assets.car")
    car = app / "Assets.car"
    if not car.is_file():
        print("(missing)")
        return
    try:
        result = subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "assetutil", "--info", str(car)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"(assetutil unavailable: {error})")
        return
    fields = ("AssetType", "Name", "RenditionName", "Idiom", "Scale", "PixelWidth", "PixelHeight")
    rows = {
        "\t".join(str(entry.get(field, "")) for field in fields)
        for entry in json.loads(result.stdout)
        if "AssetType" in entry
    }
    for row in sorted(rows):
        print(row)


def print_strings(app: Path, executable: str) -> None:
    print("## strings")
    found = set()
    for chunk in (app / executable).read_bytes().split(b"\x00"):
        if len(chunk) < 4 or max(chunk) < 0x80:
            continue
        try:
            text = chunk.decode("utf-8")
        except UnicodeDecodeError:
            continue
        # Other bytes in the executable sometimes decode as UTF-8 by chance;
        # the app's own wording always has at least one Chinese character.
        has_chinese = any("一" <= c <= "鿿" for c in text)
        if has_chinese and all(c.isprintable() or c == "\n" for c in text):
            found.add(text)
    for text in sorted(found):
        print(text.replace("\n", "\\n"))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    sys.stdout.reconfigure(encoding="utf-8")
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(sys.argv[1]) as archive:
            archive.extractall(temp)
        app = find_app(Path(temp) / "Payload")
        print(f"# {app.name}")
        print_files(app)
        info = print_info_plist(app)
        print_assets(app)
        print_strings(app, info["CFBundleExecutable"])


if __name__ == "__main__":
    main()
