#!/usr/bin/env bash
# 這個 repo 的 CI 步驟。.github/workflows/ci.yml 逐步呼叫；在裝了 Xcode 的 Mac 上也可以自己跑：
#
#   bash scripts/ci.sh xcode      印出 Xcode 和 Swift 的版本；DEVELOPER_DIR 指定的 Xcode 不在就失敗
#   bash scripts/ci.sh licences   核對 App 內「開放原始碼授權」的清單和 libidevice_ffi.a 實際連結的相符
#                                 （要 git、cargo 和 python3，Linux 也能跑）
#   bash scripts/ci.sh idevice    沒有 GFlyerIOS/Vendor/idevice 就用 scripts/build_idevice.sh 建置（要 Rust），
#                                 再檢查程式庫齊全、有 App 用到的函式
#   bash scripts/ci.sh test       產生 Xcode 專案，在 iPhone 模擬器跑 GFlyerPublic 的單元測試
#   bash scripts/ci.sh archive    建未簽署的 GFlyerPublic-Idevice archive（AppStore 設定，和上傳 App Store Connect
#                                 的是同一種建置），檢查建好的 App
#
# 建置產物放在 $RUNNER_TEMP（CI）或 build/（本機，git 不追蹤）。
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${RUNNER_TEMP:-$PWD/build}"
VENDOR=GFlyerIOS/Vendor/idevice
mkdir -p "$OUT"

xcode() {
  if [ -n "${DEVELOPER_DIR:-}" ] && [ ! -d "$DEVELOPER_DIR" ]; then
    echo "$DEVELOPER_DIR is not installed. Repin DEVELOPER_DIR in .github/workflows/ci.yml." >&2
    exit 1
  fi
  xcodebuild -version
  swift --version
}

licences() {
  # 和 scripts/build_idevice.sh 同一個來源和 revision；只下載原始碼，不建置
  local revision source
  revision="$(sed -n 's/^IDEVICE_REVISION="\([0-9a-f]*\)"$/\1/p' scripts/build_idevice.sh)"
  test -n "$revision"
  source="$OUT/idevice-source"
  if [ ! -d "$source/.git" ]; then
    git init -q "$source"
    git -C "$source" remote add origin https://github.com/jkcoxson/idevice.git
  fi
  git -C "$source" fetch -q --depth 1 origin "$revision"
  git -C "$source" checkout -q --detach FETCH_HEAD
  python3 -I scripts/open_source_licenses.py --source "$source" --out "$OUT/OpenSourceLicenses.json"
  python3 -I scripts/check_privacy_manifest.py --self-test
}

idevice() {
  if [ ! -f "$VENDOR/lib/libidevice_ffi.a" ]; then
    bash scripts/build_idevice.sh
  fi
  local required
  for required in "$VENDOR/lib/libidevice_ffi.a" "$VENDOR/include/idevice.h" "$VENDOR/include/module.modulemap"; do
    if [ ! -f "$required" ]; then
      echo "Missing $required. Delete $VENDOR and run this step again to rebuild it." >&2
      exit 1
    fi
  done
  # 在這支 iPhone 上配對要用 pairable_host_* 三個函式，它們由 build_idevice.sh 的 tunnel_tcp_stack
  # 帶進來的 remote_pairing feature 編入，換 revision 或改 features 時可能無聲地消失。idevice.h 是掃原始碼
  # 產生的，不看 features，所以要看 .a 的符號索引（__.SYMDEF）：連結器也是靠它找函式。不要用 nm 逐個 .o
  # 列符號：Rust 的 LLVM 比 Xcode 的新，.o 裏的 bitcode 會令 Xcode 的 nm 報錯。
  local armap="$OUT/idevice-armap.txt" missing=0 symbol
  nm --print-armap "$VENDOR/lib/libidevice_ffi.a" > "$armap" 2>/dev/null || true
  for symbol in tunnel_create_rppairing pairable_host_prepare pairable_host_accept_fd pairable_host_free; do
    if ! grep -q "$symbol(" "$VENDOR/include/idevice.h"; then
      echo "idevice.h does not declare $symbol." >&2
      missing=1
    fi
    if ! grep -q "^_${symbol} in " "$armap"; then
      echo "The symbol index of libidevice_ffi.a does not list $symbol." >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    echo "The index lists $(grep -c ' in ' "$armap") symbols." >&2
    exit 1
  fi
  echo "idevice library is complete."
}

generate() {
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen is required: brew install xcodegen" >&2
    exit 1
  fi
  xcodegen generate
}

test_app() {
  generate
  local simulator
  simulator="$(xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
iphones = [
    device
    for runtime_devices in devices.values()
    for device in runtime_devices
    if device.get("isAvailable") and device["name"].startswith("iPhone")
]
if not iphones:
    raise SystemExit("No available iPhone simulator was found")
print(iphones[0]["udid"])
')"
  xcodebuild test \
    -project GFlyerIOS.xcodeproj \
    -scheme GFlyerPublic \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$OUT/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO
}

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

archive() {
  generate
  local archive="$OUT/GFlyerPublic-Idevice.xcarchive"
  rm -rf "$archive"
  xcodebuild archive \
    -project GFlyerIOS.xcodeproj \
    -scheme GFlyerPublic-Idevice \
    -destination "generic/platform=iOS" \
    -archivePath "$archive" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO

  # 綠燈不等於產物正確：圖示、Bundle ID 和版本號要在建好的 App 裏核對
  local app="$archive/Products/Applications/GFlyerPublic.app"
  local plist="$app/Info.plist"
  local tunnel="$app/PlugIns/GFlyerPublicTunnel.appex"
  test -d "$app"
  test -f "$app/Assets.car"
  test -f "$app/AppIcon60x60@2x.png"
  expect "$plist" CFBundleIdentifier com.jetpiggy.gflyer
  # 版本號只在 project.yml 改
  expect "$plist" CFBundleShortVersionString "$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)"
  expect "$plist" CFBundleVersion "$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml)"
  # 加密的出口申報：App 只用國際標準的加密，又不在法國的 App Store 提供，所以是 NO，
  # 上傳 App Store Connect 時不用再回答。改了加密，或者要在法國提供，要重新判斷。
  expect "$plist" ITSAppUsesNonExemptEncryption false
  # App 內建的本機通道
  test -f "$tunnel/GFlyerPublicTunnel"
  expect "$tunnel/Info.plist" CFBundleIdentifier com.jetpiggy.gflyer.tunnel
  expect "$tunnel/Info.plist" NSExtension:NSExtensionPointIdentifier com.apple.networkextension.packet-tunnel
  expect "$tunnel/Info.plist" CFBundleShortVersionString "$(plist_value "$plist" CFBundleShortVersionString)"
  expect "$tunnel/Info.plist" CFBundleVersion "$(plist_value "$plist" CFBundleVersion)"
  # App Store Connect 收到上傳時會掃執行檔用到的「指定原因 API」，私隱清單沒有寫就退回
  plutil -lint "$app/PrivacyInfo.xcprivacy"
  python3 -I scripts/check_privacy_manifest.py --app "$app"
  # 上傳用的是 release 類的建置：有 dSYM，執行檔經過 strip，不帶這個 repo 在建置機器上的路徑
  test -d "$archive/dSYMs/GFlyerPublic.app.dSYM"
  test -d "$archive/dSYMs/GFlyerPublicTunnel.appex.dSYM"
  local binary
  for binary in "$app/GFlyerPublic" "$tunnel/GFlyerPublicTunnel"; do
    if grep -a -q -F "$PWD/" "$binary"; then
      echo "$binary has paths under $PWD:" >&2
      strings -a "$binary" | grep -F "$PWD/" | sort -u | head -20 >&2
      exit 1
    fi
  done
  echo "GFlyerPublic $(plist_value "$plist" CFBundleShortVersionString) ($(plist_value "$plist" CFBundleVersion)) checked."
}

case "${1:-}" in
  xcode) xcode ;;
  licences) licences ;;
  idevice) idevice ;;
  test) test_app ;;
  archive) archive ;;
  *)
    echo "usage: bash scripts/ci.sh xcode|licences|idevice|test|archive" >&2
    exit 2
    ;;
esac
