# App Store 的私隱申報（公開版）

`docs/APP_STORE_PLAN.md` 第 20 項，分兩部分：

- App 裏的私隱清單 `GFlyerIOS/Public/PrivacyInfo.xcprivacy`：已經做好，CI 會核對。
- App Store Connect 的「App 私隱」問卷：已經起草，等使用者確認；要有第 22 項的帳戶才填得到。

對應 Android 的是 GFlyer repo `docs/play-app-content.md` 的第 6 節「資料安全性」。改了公開版處理資料的做法，這份、私隱清單和私隱政策（`docs/privacy-policy.md`）一起改。親友版不上 App Store，沒有這些。

## 1. 私隱清單（PrivacyInfo.xcprivacy）

放在公開版 App 的最上層（XcodeGen 把 `GFlyerIOS/Public/` 裏的 `.xcprivacy` 當成資源）。

| 鍵 | 值 | 理由 |
|---|---|---|
| `NSPrivacyTracking` | `false` | 沒有追蹤，也不用 App Tracking Transparency |
| `NSPrivacyTrackingDomains` | 空 | 沒有追蹤用的網域 |
| `NSPrivacyCollectedDataTypes` | 空 | 不收集資料，見第 2 節 |
| `NSPrivacyAccessedAPITypes` | 下表三類 | App 用到的「指定原因 API」 |

| 類別 | 誰用、做甚麼 | 原因 |
|---|---|---|
| `UserDefaults` | 收藏、路線、設定、進行中的模擬、國家與城市的查詢結果等，存在 App 自己的 `UserDefaults.standard`（`LocalDataStore`、`ActiveSessionStore`、`RegionLookup`、`DeviceLocationService`、`@AppStorage`）。不讀其他 App 或系統寫的鍵 | `CA92.1`：只讀寫 App 自己的資料 |
| `FileTimestamp` | 連結進來的 idevice（Rust 標準程式庫）讀檔時用 `stat`、`fstat`、`lstat`、`fstatat` 取檔案的大小和類型，例如讀 App 自己資料夾裏的 Pairing File。Swift 的程式沒有直接用 | `C617.1`：App 自己的資料夾裏的檔案 |
| `SystemBootTime` | 主畫面「探索」的地圖縮放，用 `ProcessInfo.systemUptime` 量兩次調整相隔多久（`MainView`、`ExplorationCamera`）；不送出去 | `35F9.1`：量 App 裏兩件事相隔的時間 |

沒有用到的類別：剩餘空間（下載 DDI 之前沒有查空間）和使用中的鍵盤。

`scripts/check_privacy_manifest.py` 做 App Store Connect 收到上傳時的同一種檢查：讀 App 和通道 extension 的執行檔，從未定義的符號和 Objective-C selector 找出用到的類別，和私隱清單比對；沒有寫到的就失敗。CI 的 archive job 對建好的公開版 App 跑它（另外 `plutil -lint`），Linux 上的「Public edition source scan」跑它的 `--self-test`。類別和 API 的清單照 Apple 2026-10-22 的文件，Apple 改了要跟着改。

通道 extension 只有 `PacketTunnelProvider` 和 `PacketReflector`，沒有用到指定原因 API，所以沒有自己的私隱清單；CI 一樣會掃它，用到了就會失敗。

## 2. App Store Connect 的「App 私隱」

### 原則

照 Apple 的「App privacy details on the App Store」（<https://developer.apple.com/app-store/app-privacy-details/>，2026-10-22 讀）：

- **收集**：資料離開裝置，而開發者或「第三方夥伴」保存它，保存得比即時完成那次請求更久。「第三方夥伴」指加進 App 的分析工具、廣告網絡、第三方 SDK 或其他外部供應商的程式碼。只在裝置上處理的不算收集。
- **Apple 的 framework 和服務**（文件舉例 MapKit）：Apple 收集的資料不用開發者申報。
- **完成請求就不保存的**，例如請求帶着的 IP 地址，不用申報。
- **可選申報**：符合全部條件的可以不申報，例如和主要功能無關、偶爾才有、使用者每次自己選擇送出的意見回報。

### 答案

| 問題 | 答案 |
|---|---|
| 你或你的第三方夥伴會不會從這個 App 收集資料 | 不會（No, we do not collect data from this app） |
| 私隱政策網址（必填） | 中文 <https://gflyer.jetpiggy.com/ios/privacy.html>，英文 <https://gflyer.jetpiggy.com/en/ios/privacy.html>（第 19 項；網頁送審之前才放上去） |
| 私隱選擇網址（可選） | 不填。資料只在使用者的 iPhone 上，私隱政策的「保存和刪除」寫了怎樣刪除 |

填完之後，商店上的標籤是「Data Not Collected」。

### 不申報的，和理由

| 資料 | 為甚麼不用申報 |
|---|---|
| 地圖顯示的範圍、地點搜尋的文字、收藏的座標（查國家與城市） | 經 MapKit 和 `CLGeocoder` 送去 Apple。Apple 收集的資料不用開發者申報，JetPiggy 收不到 |
| 掛載 DDI 時這部 iPhone 的 ECID、晶片和主機板的型號代碼、nonce | idevice 送去 Apple 的簽署伺服器 `gs.apple.com`，取得掛載用的票據，和 Xcode 一樣。收到的是 Apple，JetPiggy 和 idevice 的作者都收不到，所以照「Apple 收集的不用申報」處理。這一項要使用者確認，見第 4 節 |
| 下載 DDI | 從 GitHub 下載固定版本的檔案，請求只帶 IP 地址和要下載的檔案，沒有使用者資料；GitHub 不是加進 App 的程式碼 |
| 「聯絡我們」的電郵 | 和 Android 相同：App 只打開使用者的電郵 App，預填版本、iOS 版本和型號代碼，使用者看得到，也改得到；寄出電郵的是電郵 App，App 本身不傳送任何東西。就算當成 App 收集，它也和主要功能無關、偶爾才有，而且使用者每次自己選擇寄出 |
| iPhone 的真實位置、模擬位置 | 只在 iPhone 上用；模擬位置交給這部 iPhone 自己的開發者服務 |
| 收藏、路線、設定、Pairing File、最後一次的真實位置 | 只存在 iPhone 上。iCloud 備份由 Apple 按使用者的設定處理，不是 App 送出去的 |
| 在這支 iPhone 上配對時的公告 | 本機網絡上的 Bonjour 公告，只有名稱「GFlyer」和隨機產生的識別碼，不送到任何伺服器 |
| 本機通道 | 封包不離開這部 iPhone |

### 和 Android 的標籤不同

Android 的資料安全性申報了這些項目：位置、應用程式內搜尋記錄，以及 Maps SDK 送給 Google 的四項（`docs/play-app-content.md`）。兩邊的做法相同，標籤不同是因為兩個商店的定義和 App 裏的程式不同：

- Google Play 的定義是，資料經 App 或 App 裏的 SDK 離開手機就算收集，經系統的地點服務送出也算。
- Android 版加進了 Google 的 Maps SDK，它是第三方 SDK。
- iOS 的地圖、搜尋和地名都用 Apple 自己的 framework，Apple 寫明它收集的不用開發者申報。App 裏也沒有第三方的地圖 SDK。

## 3. 怎樣確認

- CI：上面的私隱清單核對。
- 第 23 項第一次上傳之後，App Store Connect 沒有寄來 ITMS-91053（缺少指定原因 API 的申報）之類的電郵。
- 問卷填好之後，在 App Store Connect 預覽產品頁的私隱標籤，確認和私隱政策沒有矛盾。

## 4. 送出前要確認

1. **整份答「不收集」**，特別是掛載 DDI 時送去 Apple 的 ECID：草稿照「Apple 收集的不用申報」處理。想保守的話，可以申報「Identifiers → Device ID」（用途「App Functionality」、沒有連結身分、沒有追蹤）。但那樣商店會顯示 App 收集裝置 ID，和 JetPiggy 實際收不到任何資料不符，所以建議不申報。
2. **「聯絡我們」的電郵不申報**，和 Android 相同。
3. 填問卷要有第 22 項的帳戶。
