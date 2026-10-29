#!/usr/bin/env bash
# 核對建好的公開版 archive。macos-xcode.yml 用它查每次 push 建的未簽署 archive，app-store.yml 用它查
# 要上傳的、簽好的 archive（docs/app-store-signing.md）。公開 repo 的 scripts/ci.sh archive 做同樣的
# 檢查（tools/export-public/overlay/），改其中一邊時兩邊一起改。
#
#   bash tools/app-store/check_public_app.sh ARCHIVE
set -euo pipefail

archive="${1:?usage: bash tools/app-store/check_public_app.sh ARCHIVE}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
app="$archive/Products/Applications/GFlyerPublic.app"
plist="$app/Info.plist"
tunnel="$app/PlugIns/GFlyerPublicTunnel.appex"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

expect() {
  local actual
  actual="$(plist_value "$1" "$2")"
  if [ "$actual" != "$3" ]; then
    echo "$1: $2 is \"$actual\", expected \"$3\"." >&2
    exit 1
  fi
}

project_value() {
  sed -n "s/^ *$1: \"\(.*\)\"$/\1/p" "$root/project.yml"
}

# 綠燈不等於產物正確：圖示、Bundle ID 和版本號要在建好的 App 裏核對
test -d "$app"
test -f "$app/Assets.car"
test -f "$app/AppIcon60x60@2x.png"
expect "$plist" CFBundleIdentifier com.jetpiggy.gflyer
# 版本號只在 project.yml 改（docs/RELEASE_PROCESS.md 第 1 步）
expect "$plist" CFBundleShortVersionString "$(project_value MARKETING_VERSION)"
expect "$plist" CFBundleVersion "$(project_value CURRENT_PROJECT_VERSION)"
# 加密的出口申報（docs/APP_STORE_PLAN.md 第 21 項）：只用標準加密、不在法國上架，所以是 NO。
# 少了這個鍵，每次上傳都要在 App Store Connect 回答；要改先看 docs/app-store-encryption.md
expect "$plist" ITSAppUsesNonExemptEncryption false
# App 內建的本機通道（docs/APP_STORE_PLAN.md 第 12 項）
test -f "$tunnel/GFlyerPublicTunnel"
expect "$tunnel/Info.plist" CFBundleIdentifier com.jetpiggy.gflyer.tunnel
expect "$tunnel/Info.plist" NSExtension:NSExtensionPointIdentifier com.apple.networkextension.packet-tunnel
expect "$tunnel/Info.plist" CFBundleShortVersionString "$(plist_value "$plist" CFBundleShortVersionString)"
expect "$tunnel/Info.plist" CFBundleVersion "$(plist_value "$plist" CFBundleVersion)"
# 親友版的私人網址只放在親友版的 Info.plist（docs/APP_STORE_PLAN.md 第二階段的做法）
for key in GFlyerMessageBoardAPIURL GFlyerCoordinateLibraryURL GFlyerUpdateSourceURL; do
  if plist_value "$plist" "$key" >/dev/null 2>&1; then
    echo "The public app's Info.plist has $key." >&2
    exit 1
  fi
done

# 原始碼掃描之外再掃一次建好的 App，管建置時才加進來的字：建置設定、資源、連結進來的
# 程式庫（docs/APP_STORE_PLAN.md 第 10 項）
python3 -I "$root/scripts/check_public_sources.py" --app "$app"

# App Store Connect 收到上傳時會掃執行檔用到的「指定原因 API」，私隱清單沒有寫就退回
# （docs/APP_STORE_PLAN.md 第 20 項）。這裏先照同一份清單掃 App 和通道 extension。
plutil -lint "$app/PrivacyInfo.xcprivacy"
python3 -I "$root/scripts/check_privacy_manifest.py" --app "$app"

# 上傳用的是 release 類的建置（docs/APP_STORE_PLAN.md 第 23 項）：有 dSYM，執行檔經過 strip，
# 不帶這個 repo 在建置機器上的路徑（debug 類的建置帶着 debug map，路徑裏有私人 repo 的名稱）
test -d "$archive/dSYMs/GFlyerPublic.app.dSYM"
test -d "$archive/dSYMs/GFlyerPublicTunnel.appex.dSYM"
for binary in "$app/GFlyerPublic" "$tunnel/GFlyerPublicTunnel"; do
  if grep -a -q -F "$root/" "$binary"; then
    echo "$binary has paths under $root:" >&2
    strings -a "$binary" | grep -F "$root/" | sort -u | head -20 >&2
    exit 1
  fi
done

echo "GFlyerPublic $(plist_value "$plist" CFBundleShortVersionString) ($(plist_value "$plist" CFBundleVersion)) checked."
