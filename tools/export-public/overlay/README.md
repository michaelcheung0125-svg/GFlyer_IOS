# GFlyer - 飛豬人（iOS）

[English](#english)

GFlyer（飛豬人）是以地圖為主的 iOS 位置測試工具，用 SwiftUI 寫成。它經 iPhone 的開發者模式，用和 Xcode 模擬位置相同的開發者服務，把 iPhone 的位置換成你選的位置或路線：不用越獄，也不修改其他 App。

這個 repo 是 GFlyer iOS 公開版的原始碼，以 Apache License 2.0 授權；品牌名稱和飛豬圖像除外（見 [`NOTICE`](NOTICE)）。App 暫時沒有在 App Store 提供，需要自行建置。

## 功能

- Apple 地圖；地點和座標搜尋
- 定點傳送；單點、多點路線，多點路線可以循環；路線用「定點傳送」或「模擬移動」走
- 探索：南北來回的蛇形路線，固定的橫向間距，可調直向距離，地圖預覽路線
- 速度控制、自訂的快捷速度和搖桿
- 路線播放：到點後停留、繞圈或微動，手動前往下一點，開始前倒數，自動停止
- 收藏（可以分資料夾）、定位歷史、命名路線；GPX 匯入和匯出；備份和還原
- 收藏的國家與城市（先問過你才查）
- 跨日的時區提示（離線按經度推算）
- 「定位檢查」：看其他 App 現在收到的位置，確認模擬有沒有生效
- 飛航模式輔助（用行動網路時）
- 第一次設定：在這支 iPhone 上配對（iOS 27 以上）或匯入 Pairing File、App 內建的本機通道、下載 DDI

## 用之前要準備

- iPhone 要開啟開發者模式。
- Pairing File：iOS 27 以上可以在 App 裏按「在這支 iPhone 上配對」產生；較舊的 iOS 要用電腦產生，再在 App 裏匯入。
- 本機通道在 App 裏，第一次開啟時 iOS 會問可否加入 VPN 設定。這個通道只把送往目標 IP 的封包送回這部 iPhone 自己，不經手其他網絡流量。
- DDI：在 App 的「裝置設定」按下載，要連得上網絡。

App 的「裝置設定」有「操作順序」，列出每一步。

## 建置

需要 macOS、Xcode 26（CI 用 26.6）和 XcodeGen。最低支援 iOS 17.4。

```bash
brew install xcodegen
xcodegen generate
open GFlyerIOS.xcodeproj
```

- **模擬器**：scheme `GFlyerPublic`。它用預覽的定位後端，不會改任何裝置的位置。
- **iPhone**：要 Rust（[rustup](https://rustup.rs)）。先跑 `scripts/build_idevice.sh`，它從釘住版本的 idevice 原始碼建出 `libidevice_ffi.a`（見 [`GFlyerIOS/Vendor/README.md`](GFlyerIOS/Vendor/README.md)）；再跑一次 `xcodegen generate`，選 scheme `GFlyerPublic-Idevice`。

裝到 iPhone 要用付費的 Apple Developer 帳戶簽署：本機通道是 Network Extension，免費的 Apple ID 簽不了。自己簽署時，在 `project.yml` 把 `GFlyerPublic` 和 `GFlyerPublicTunnel` 的 `PRODUCT_BUNDLE_IDENTIFIER` 改成你自己的（通道的是 App 的加上 `.tunnel`），`DEVELOPMENT_TEAM` 填你的 Team ID，再跑 `xcodegen generate`。

CI 的每一步在 [`scripts/ci.sh`](scripts/ci.sh)，在 Mac 上可以照樣跑，例如 `bash scripts/ci.sh test`。

## 專案結構

| 路徑 | 內容 |
|---|---|
| `GFlyerIOS/UI/` | SwiftUI 畫面 |
| `GFlyerIOS/Services/` | 模擬定位（`SimulationController`）、配對、DDI、備份、搜尋和本機儲存 |
| `GFlyerIOS/Model/` | 純邏輯：座標、路線、GPX、搖桿和文字 |
| `GFlyerIOS/Public/` | 公開版自己的設定（`Info.plist`、entitlements、私隱清單）和程式，包括本機通道和 DDI 下載 |
| `GFlyerIOS/Edition/` | 版本專屬功能的介面（`Edition`、`EditionModel`） |
| `GFlyerPublicTunnel/` | 本機通道的 Packet Tunnel extension |
| `GFlyerIOSTests/` | 單元測試 |
| `scripts/` | 建置 idevice、開放原始碼授權的清單、私隱清單的檢查、CI |

單元測試沒有覆蓋和 iPhone 開發者服務的實際連線、系統的 VPN 設定和畫面；改動這些地方要在 iPhone 上試。

## 範圍和限制

GFlyer 不修改其他 App、不隱藏模擬定位狀態、不繞過其他 App 的偵測，也不讀取其他 App 的資料。其他 App 可以拒絕模擬位置，它們的使用條款仍然適用。

## 私隱

- 不需要帳號，沒有分析、廣告或追蹤的 SDK，JetPiggy 也沒有為 App 設伺服器。
- 收藏、歷史、路線、設定和 Pairing File 存在 iPhone 上，不會傳送給 JetPiggy。
- App 只在這些情況連線：Apple 的地圖和地點搜尋；你允許之後，用 Apple 的地點服務查收藏的國家與城市；你按下載時，從 GitHub 下載 DDI；掛載 DDI 時向 Apple 的簽署伺服器要票據，和 Xcode 的做法相同。
- 讀取 iPhone 的真實位置（地圖的目前位置、「定位檢查」）只在 iPhone 上使用，不會傳送出去。

## 授權

原始碼以 [Apache License 2.0](LICENSE) 授權。GFlyer、飛豬人和 JetPiggy 的名稱、App 圖示和飛豬圖像不在授權範圍內，見 [`NOTICE`](NOTICE)。idevice 的授權見 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

App 連結的 `libidevice_ffi.a` 包括 idevice、它用到的 Rust 套件和 Rust 標準程式庫，各自保留原本的授權。清單和授權全文在 `GFlyerIOS/Resources/OpenSourceLicenses.json`，App 內「裝置設定」的「關於」>「開放原始碼授權」可以看到。

## 聯絡

gflyer@jetpiggy.com

---

## English

GFlyer (飛豬人) is a map-first location testing tool for iOS, built with SwiftUI. Through the iPhone's Developer Mode it uses the same developer service that Xcode uses to simulate location, so the iPhone reports the place or route you choose. It needs no jailbreak and does not modify other apps.

This repository holds the source code of the public iOS edition. It is licensed under the Apache License 2.0, except for the brand names and the flying pig artwork (see [`NOTICE`](NOTICE)). The app is not on the App Store yet, so you need to build it yourself.

Features include static and route simulation, serpentine exploration, a joystick, route playback options, favorites, GPX import and export, backups, and a location check page. First-time setup pairs on the iPhone itself on iOS 27 and later (older versions import a pairing file made on a computer), uses a local tunnel built into the app, and downloads the Developer Disk Image. The app's interface is in Chinese.

To build, install Xcode 26 and XcodeGen, run `xcodegen generate` and open `GFlyerIOS.xcodeproj`. The `GFlyerPublic` scheme runs in the Simulator with a preview backend. For an iPhone, install Rust, run `scripts/build_idevice.sh`, regenerate the project and use the `GFlyerPublic-Idevice` scheme. Installing on an iPhone needs a paid Apple Developer account, because the local tunnel is a Network Extension; set your own bundle identifiers and team in `project.yml`.

The app has no account, no analytics, ads or tracking SDKs, and JetPiggy runs no server for it. Your data stays on the iPhone. It connects only to Apple for maps, search, place names (after you allow it) and the DDI signing server, and to GitHub when you download the DDI.

The libraries linked into the app keep their own licenses; their list and full license texts are in `GFlyerIOS/Resources/OpenSourceLicenses.json` and in the app.

Contact: gflyer@jetpiggy.com
