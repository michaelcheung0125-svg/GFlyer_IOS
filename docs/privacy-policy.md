# 公開版私隱政策（正本）

`docs/APP_STORE_PLAN.md` 第 19 項。這份是 iOS 公開版（`com.jetpiggy.gflyer`）私隱政策的內容正本：網站（`JetPiggy` repo 的 `sites/gflyer.jetpiggy.com/`）照這份做成兩頁，中文 `/ios/privacy.html`、英文 `/en/ios/privacy.html`；網站那邊只改外觀，不改內容。App（公開版設定頁「關於」的「私隱政策」，`Edition.privacyPolicyURL`）連到中文那一頁；App Store Connect 的私隱政策網址，中文的語言填中文頁，英文的填英文頁。

只寫公開版實際的做法。改了公開版處理資料的做法（連線、權限、存甚麼、備份檔的內容），要同時改這份，再交網站更新，「生效日期」也要改。親友版不適用這份。Android 公開版的私隱政策是另一份（GFlyer repo 的 `docs/privacy-policy.md`，網站的 `/privacy.html`）；兩份的結構和用字盡量相同，不同的地方是兩個平台的做法不同。

2026-10-22 使用者決定：
- 網址是 `/ios/privacy.html` 和 `/en/ios/privacy.html`。
- 正本現在寫，送審之前（第 25 項填商店資訊時）才放上網站：JetPiggy RULES 第 5 節只准寫已推出或已公開的功能，而且這一節不可以放寬。在那之前 App 裏的「私隱政策」打不開；公開版要付費開發者帳戶才裝得到，所以沒有人會按到。放上去的時候把兩種語言的「生效日期」改成那一天，交接時寫明。
- 地名反查先問（U7），下面「連線到的服務」照這樣寫。

照 Android 正本 2026-10-19 使用者確認的：開發者寫「JetPiggy」，聯絡電郵用 `gflyer@jetpiggy.com`，寫「不是專為兒童而設」。

RULES 第 5 節不准網站有個人帳戶名，也不准連去個人帳戶下的 repo，所以 DDI 的來源只寫「GitHub 上一個公開的 repo」；是哪個 repo、哪個版本，寫在 `GFlyerIOS/Services/DeveloperDiskImageStore.swift`。

每一句的根據（改程式時對照）：
- 存的資料：`LocalDataStore`（收藏最多 100 個、歷史 30 個、路線 50 條）、`ActiveSessionStore`、`DeviceLocationService` 的 `gflyer.last-real-coordinate`、`RegionLookup`、`PairingFileStore`（Application Support，`FileProtectionType.complete`，沒有排除在 iPhone 備份之外）、`DeveloperDiskImageStore`（`isExcludedFromBackup`）。
- 背景定位：`DeviceLocationService.startBackgroundRouteActivity`，只在「單點」「多點」「探索」移動期間。
- 配對公告：`PairingHost.swift`（dns_sd，最多 300 秒）、`IdevicePairingHostEngine`（名稱「GFlyer」）；TXT 的內容在 idevice 的 `PairableHostInfo::mdns_txt_records`。
- 通道：`GFlyerPublicTunnel`、`PacketReflector`（只導入目標 IP 一個位址）。
- 簽署伺服器：idevice `src/tss.rs`（`http://gs.apple.com/TSS/controller`，BoardID、ChipID、ECID、nonce 和映像的雜湊值），見 `docs/APP_STORE_PLAN.md`「第 15 項的進度」。
- 搜尋：`PlaceSearchService`（座標在手機上解析，不送出）；國家與城市：`AppleGeocoderRegionLabelSource` 和 `RegionLookupConsent`。
- 備份檔：`AppBackupCodec`；聯絡我們：`ContactEmail`；剪貼簿只有 `SetupView.showNoMailApp` 寫入。

下面兩節是要公開的全文。

---

## 中文

# GFlyer - 飛豬人 iOS 版私隱政策

生效日期：2026 年 10 月 22 日

本政策說明 iOS App「GFlyer - 飛豬人」（Bundle ID `com.jetpiggy.gflyer`，下稱「本 App」）怎樣處理你的資料。本 App 由 JetPiggy 開發。Android 版的私隱政策在 <https://gflyer.jetpiggy.com/privacy.html>。

### 重點

- 不需要帳號，也不用登入。
- 沒有分析、廣告或追蹤的 SDK。
- JetPiggy 沒有為本 App 設伺服器：你的位置、收藏、路線、設定和 Pairing File 不會傳送給 JetPiggy。
- 資料存在你的 iPhone 上。只有地圖、地點搜尋、查詢收藏的國家與城市，以及下載和掛載 DDI 要連線到 Apple 或 GitHub，見下面「連線到的服務」。
- 你用「聯絡我們」寄電郵給我們，我們才會收到你的電郵，見下面「聯絡我們的電郵」。

### 存在 iPhone 上的資料

本 App 把以下資料存在 iPhone 上、只有本 App 讀得到的儲存空間：

- 收藏位置、收藏路線和資料夾；
- 定位歷史（最近 30 個位置）；
- 快捷速度預設和各項設定，包括本機通道的目標 IP 和「飛航模式輔助」的捷徑名稱；
- 進行中的模擬，App 被系統關掉之後可以接着做；
- 最後一次讀到的 iPhone 真實位置（一個座標），見下面「iPhone 的真實位置」；
- 收藏所在的國家與城市（只在你允許之後才會查，見下面「連線到的服務」）；
- Pairing File 和下載的 DDI 檔案，見下面「Pairing File、本機通道和 DDI」。

iPhone 的 iCloud 備份和電腦備份會包括這些資料（DDI 檔案除外），按你的備份設定處理；用這些備份還原或設定另一部 iPhone 時，資料也會帶過去。

### 位置

**iPhone 的真實位置**。你授予「使用 App 期間」的位置權限之後，本 App 會讀取 iPhone 的位置，用來把地圖移到目前位置、在「定位檢查」頁顯示，以及在「完整清除模擬定位」時先把位置移回真實位置附近；為此本 App 會記下最後一次讀到的真實位置。讀到的位置只在 iPhone 上使用，本 App 不會把它傳送出去。用「單點」、「多點」或「探索」模擬移動期間，本 App 在背景繼續使用位置，讓 iOS 不會暫停本 App，這時 iOS 會顯示有 App 正在使用位置；停止之後就不再在背景使用。

**模擬位置**。本 App 的主要功能是模擬位置。要用這個功能，你要先開啟 iPhone 的開發者模式、準備好 Pairing File，並下載 DDI。你開始模擬時，本 App 經本機通道把你選的位置或路線交給這部 iPhone 的開發者服務，和開發者用 Xcode 模擬位置的方法相同；iPhone 上其他 App 收到的位置會變成模擬的位置，直到你停止模擬。

### Pairing File、本機通道和 DDI

**Pairing File**。本 App 要有 Pairing File 才可以連接這部 iPhone 的開發者服務。iOS 27 起可以按「在這支 iPhone 上配對」在這部 iPhone 上產生；較舊的 iOS 要用電腦產生，再按「匯入 Pairing File」匯入。Pairing File 存在本 App 的儲存空間，加上 iOS 的資料保護，iPhone 鎖定時讀不到。本 App 只用它連接這部 iPhone 自己，不會把它傳送出去，也不會放進本 App 匯出的備份檔。你可以按「匯出 Pairing File」存一份到你揀的位置，或按「移除 Pairing File」刪除。

**在這支 iPhone 上配對**。配對期間（最多 5 分鐘），本 App 在本機網絡上公告一個配對服務，讓 iPhone 的「設定」找到本 App。同一個網絡上的其他裝置也看得到這個公告；公告裏只有名稱「GFlyer」、為這次配對隨機產生的識別碼和配對協定需要的固定資料，沒有你或這部 iPhone 的資料。配對用的 6 位數字只在本 App 和通知裏顯示。配對完成、取消或逾時之後，公告就停止。

**本機通道**。本 App 在 iOS 的 VPN 設定加入「GFlyer 本機通道」，第一次開啟時 iOS 會問你可否加入。這個通道只接收送往你在「裝置設定」填的目標 IP 的封包，把它們送回這部 iPhone 自己，讓本 App 連接 iPhone 的開發者服務；這些封包不會離開這部 iPhone。你上網的其他流量不經過這個通道，本 App 也不會讀取或記錄。

**DDI**。iOS 要先掛載 Apple 的 Developer Disk Image（DDI）才可以模擬位置。你在「裝置設定」的「Developer Disk Image」按「下載 DDI（約 16.5 MB）」之後，本 App 才從 GitHub 上一個公開的 repo 下載 Apple 的 DDI 檔案（固定的版本），用 App 內建的 SHA-256 核對，存在 iPhone 上；這些檔案不會放進 iPhone 的 iCloud 備份或電腦備份。掛載 DDI 時，如果 iPhone 還沒有這個映像的個人化票據，本 App 會向 Apple 的簽署伺服器（gs.apple.com）要一張，和 Xcode 掛載 DDI 時一樣。這個請求包括這部 iPhone 的晶片識別碼（ECID，每部 iPhone 都不同）、晶片和主機板的型號代碼、一次性的隨機數和 DDI 檔案的雜湊值，經 HTTP 傳送，沒有加密。

### 剪貼簿

本 App 不會讀取剪貼簿。只有在找不到可以寄電郵的 App 時，「聯絡我們」會把我們的電郵地址複製到剪貼簿。

### 連線到的服務

本 App 只在下面的情況連線到第三方服務。這些服務會收到你的 IP 地址和連線需要的資料，並按它們自己的私隱政策處理。

- **Apple**（私隱政策：<https://www.apple.com/legal/privacy/>）：
  - 地圖：顯示地圖時，Apple 會收到地圖顯示的範圍；
  - 地點搜尋：你按下搜尋時，送出搜尋文字；搜尋的是座標的話，在 iPhone 上直接找出位置，不會送出；
  - 收藏的國家與城市：你允許「顯示收藏的國家與城市」之後，App 開啟或收藏變動時送出收藏位置與收藏路線第一點的座標；按 ☆ 收藏一個所在地區還沒查過的地點時，立刻送出那一點的座標，用來預先填入名稱，之後按取消也一樣。第一次要查之前會先問你；不允許也可以照常收藏，只是不顯示國家與城市。之後可以在「裝置設定」的「提示與地名」更改。查到的結果只存在 iPhone 上，不會放進本 App 匯出的備份檔；
  - 簽署伺服器：掛載 DDI 時，見上面「DDI」。
- **GitHub**（私隱政策：<https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement>）：你按「下載 DDI（約 16.5 MB）」時，下載 DDI 的檔案。

跨日時區提示用經度在 iPhone 上估算時差，不會把座標傳送到任何時區服務。

### 備份和 GPX

你可以把資料匯出成備份檔或 GPX 檔，也可以匯入。檔案放在你用系統的檔案選擇器揀的位置，由你自己保管；本 App 不會上傳這些檔案。備份檔包括收藏、路線、資料夾、定位歷史、快捷速度預設和部分設定，不包括 Pairing File、國家與城市的查詢結果和 iPhone 的真實位置。

### 聯絡我們的電郵

「裝置設定」的「聯絡我們」會打開你 iPhone 上的電郵 App，收件人是 <gflyer@jetpiggy.com>，內文預先填好本 App 的版本、iOS 版本和 iPhone 的型號代碼（例如 iPhone16,2），方便我們找出問題；寄出之前你可以修改或刪掉。電郵由你的電郵 App 寄出，本 App 不會自己傳送任何東西。我們會收到你的電郵地址和你寄來的內容，只用來回覆你和改善本 App，不會交給其他人。你可以要求我們刪除你寄來的電郵。

### 權限

- **位置（使用 App 期間）**：見上面「iPhone 的真實位置」。
- **本機網絡**：經本機通道連接這部 iPhone 的開發者服務；在這支 iPhone 上配對時，讓「設定」找到本 App。
- **VPN 設定**：加入「GFlyer 本機通道」，見上面「本機通道」。
- **通知**：在這支 iPhone 上配對時，顯示配對用的 6 位數字和配對結果；按「在這支 iPhone 上配對」時才會問你。
- **背景執行**：模擬移動期間在背景繼續使用位置；在這支 iPhone 上配對時，你切去「設定」的期間繼續等候配對，iOS 會顯示進度。

### 不做的事

- 不收集或出售你的個人資料，也不把資料交給廣告商。
- 不追蹤你在其他 App 或網站的活動。
- 不修改其他 App，也不隱藏模擬位置。

### 保存和刪除

- iPhone 上的資料會一直保存，直到你刪除。在本 App 內可以刪除收藏、路線和資料夾，清除定位歷史，移除 Pairing File；在「裝置設定」的「提示與地名」關掉「顯示收藏的國家與城市」，就不再查詢。
- 刪除本 App 會刪除它存在 iPhone 上的全部資料，包括 Pairing File 和 DDI 檔案。iCloud 備份和電腦備份裏的副本，按你的備份設定保存。
- 匯出的備份檔、GPX 檔和 Pairing File 由你自己刪除。
- 除了你寄給我們的電郵，JetPiggy 沒有你的資料。Apple 和 GitHub 收到的資料，按它們的政策保存。

### 資料安全

- iPhone 上的資料存在 iOS 給本 App 的私人儲存空間，其他 App 讀不到；Pairing File 另外加上 iOS 的資料保護，見上面「Pairing File」。
- 下載 DDI 經加密的 HTTPS。向 Apple 簽署伺服器的請求經 HTTP 傳送，沒有加密，見上面「DDI」。地圖和地點服務的連線由 iOS 處理。
- 本機通道的封包不會離開這部 iPhone。

### 兒童

本 App 是給一般人用的工具，不是專為兒童而設。不論使用者年紀多大，本 App 都不會把可以識別任何人的資料傳送給 JetPiggy。

### 你的權利

本 App 的資料只在你的 iPhone 和你自己的 iPhone 備份裏，你可以自己查看、匯出和刪除，見上面「保存和刪除」。我們手上只有你寄來的電郵；要查閱或刪除，或者對私隱有任何疑問，歡迎聯絡我們。

### 政策的更新

本政策有改動時，我們會更新這一頁和上面的生效日期。

### 聯絡我們

JetPiggy　<gflyer@jetpiggy.com>

---

## English

# GFlyer iOS Privacy Policy

Effective date: 22 October 2026

This policy explains how the iOS app "GFlyer - 飛豬人" (bundle ID `com.jetpiggy.gflyer`, "the app") handles your data. The app is developed by JetPiggy. The privacy policy for the Android app is at <https://gflyer.jetpiggy.com/en/privacy.html>.

### Summary

- No account or sign-in is needed.
- There are no analytics, advertising or tracking SDKs.
- JetPiggy runs no server for the app: your locations, favourites, routes, settings and pairing file are never sent to JetPiggy.
- Your data stays on your iPhone. Only maps, place search, looking up the country and city of favourites, and downloading and mounting the DDI connect to Apple or GitHub; see "Services the app connects to" below.
- We receive an email from you only if you send one with "聯絡我們" (Contact us); see "Emails you send us" below.

### Data stored on your iPhone

The app keeps the following in storage on your iPhone that only the app can read:

- favourite places, favourite routes and folders;
- location history (the 30 most recent locations);
- quick speed presets and settings, including the local tunnel's target IP and the shortcut names for "飛航模式輔助" (airplane mode assist);
- a simulation in progress, so it can continue if the system closes the app;
- the last real location read from your iPhone (one coordinate); see "Your iPhone's real location" below;
- the country and city of your favourites (looked up only after you allow it; see "Services the app connects to");
- the pairing file and the downloaded DDI files; see "Pairing file, local tunnel and DDI" below.

iCloud and computer backups of your iPhone include this data (except the DDI files), handled according to your backup settings; restoring or setting up another iPhone from those backups carries it over too.

### Location

**Your iPhone's real location.** After you grant location permission "使用 App 期間" (while using the app), the app reads your iPhone's location to move the map to your current position, to show it on the "定位檢查" (location check) page, and to move the location back near your real location before "完整清除模擬定位" (fully clear simulated location); for this the app remembers the last real location it read. The location is used only on your iPhone; the app never sends it anywhere. While a "單點" (single point), "多點" (multi-point) or "探索" (explore) simulation is moving, the app keeps using location in the background so that iOS does not suspend it, and iOS shows that an app is using your location; once you stop, it no longer uses location in the background.

**Simulated location.** Simulating location is the app's main feature. To use it, you first turn on Developer Mode on your iPhone, set up a pairing file and download the DDI. When you start a simulation, the app passes the location or route you chose through the local tunnel to your iPhone's developer services, the same way developers simulate location with Xcode, and other apps on your iPhone receive the simulated location until you stop.

### Pairing file, local tunnel and DDI

**Pairing file.** The app needs a pairing file to connect to your iPhone's developer services. From iOS 27 you can create one on the iPhone itself with "在這支 iPhone 上配對" (pair on this iPhone); on earlier iOS versions you create it on a computer and import it with "匯入 Pairing File" (import pairing file). The pairing file is kept in the app's storage with iOS data protection, so it cannot be read while your iPhone is locked. The app uses it only to connect to this iPhone itself, never sends it anywhere, and does not include it in backup files the app exports. You can save a copy where you choose with "匯出 Pairing File" (export pairing file), or delete it with "移除 Pairing File" (remove pairing file).

**Pairing on this iPhone.** While pairing (for up to 5 minutes), the app announces a pairing service on your local network so that the iPhone's Settings app can find it. Other devices on the same network can see this announcement too; it contains only the name "GFlyer", an identifier generated at random for this pairing, and fixed values the pairing protocol needs, and nothing about you or your iPhone. The 6-digit pairing code is shown only in the app and in a notification. The announcement stops when pairing finishes, is cancelled or times out.

**Local tunnel.** The app adds "GFlyer 本機通道" (GFlyer local tunnel) to the VPN settings of iOS; iOS asks for your permission the first time it is turned on. The tunnel receives only packets sent to the target IP you enter in "裝置設定" (device settings) and sends them back to this iPhone itself, so the app can connect to your iPhone's developer services; these packets never leave your iPhone. Your other internet traffic does not go through the tunnel, and the app does not read or record it.

**DDI.** iOS must mount Apple's Developer Disk Image (DDI) before it can simulate location. Only after you tap "下載 DDI（約 16.5 MB）" (download DDI, about 16.5 MB) under "Developer Disk Image" in "裝置設定" (device settings) does the app download Apple's DDI files (a fixed version) from a public repository on GitHub, check them against SHA-256 hashes built into the app, and keep them on your iPhone; these files are not included in iCloud or computer backups of your iPhone. When the DDI is mounted and your iPhone does not yet have a personalization ticket for this image, the app requests one from Apple's signing server (gs.apple.com), as Xcode does when it mounts the DDI. The request contains your iPhone's chip identifier (ECID, which is different for every iPhone), the model codes of its chip and board, a one-time random value (nonce) and the hashes of the DDI files, and is sent over HTTP without encryption.

### Clipboard

The app never reads the clipboard. Only when no email app is available does "聯絡我們" (Contact us) copy our email address to the clipboard.

### Services the app connects to

The app connects to third-party services only in the cases below. These services receive your IP address and the data needed for the request, and handle it under their own privacy policies.

- **Apple** (privacy policy: <https://www.apple.com/legal/privacy/>):
  - maps: when the map is shown, Apple receives the area shown on the map;
  - place search: when you tap search, the search text is sent; if you search for coordinates, the location is found on your iPhone and nothing is sent;
  - country and city of favourites: after you allow "顯示收藏的國家與城市" (show the country and city of favourites), the coordinates of your favourite places and of the first point of each favourite route are sent when the app opens or your favourites change; when you tap ☆ to save a place in an area not looked up yet, that point's coordinates are sent straight away to pre-fill its name, even if you then cancel. The app asks before the first lookup; if you decline you can still save favourites, they just won't show a country and city. You can change this later under "提示與地名" (hints and place names) in "裝置設定" (device settings). Results are stored only on your iPhone and are not included in backup files the app exports;
  - signing server: when the DDI is mounted; see "DDI" above.
- **GitHub** (privacy policy: <https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement>): when you tap "下載 DDI（約 16.5 MB）" (download DDI), the DDI files are downloaded.

The cross-date time zone hint estimates the time difference from longitude on your iPhone; coordinates are never sent to a time zone service.

### Backups and GPX

You can export your data to a backup file or a GPX file, and import them. Files are saved where you choose with the system file picker and stay in your control; the app never uploads them. Backup files contain your favourites, routes, folders, location history, quick speed presets and some settings, but not the pairing file, the country and city lookups or your iPhone's real location.

### Emails you send us

"聯絡我們" (Contact us) in "裝置設定" (device settings) opens the email app on your iPhone, addressed to <gflyer@jetpiggy.com>, with the app's version, the iOS version and your iPhone's model code (for example iPhone16,2) filled in to help us find problems; you can change or remove them before sending. The email is sent by your email app; the app itself sends nothing. We receive your email address and what you send, use it only to reply to you and improve the app, and do not pass it to anyone else. You can ask us to delete the emails you sent.

### Permissions

- **Location (while using the app)**: see "Your iPhone's real location" above.
- **Local network**: connects to your iPhone's developer services through the local tunnel; when pairing on this iPhone, lets the Settings app find the app.
- **VPN settings**: adds "GFlyer 本機通道" (GFlyer local tunnel); see "Local tunnel" above.
- **Notifications**: when pairing on this iPhone, show the 6-digit pairing code and the result; the app asks only when you tap "在這支 iPhone 上配對" (pair on this iPhone).
- **Background activity**: keeps using location in the background while a simulation is moving; when pairing on this iPhone, keeps waiting while you switch to the Settings app, and iOS shows the progress.

### What the app does not do

- It does not collect or sell your personal data, or give data to advertisers.
- It does not track your activity in other apps or on websites.
- It does not modify other apps or hide that a location is simulated.

### Retention and deletion

- Data on your iPhone is kept until you delete it. In the app you can delete favourites, routes and folders, clear the location history and remove the pairing file; turning off "顯示收藏的國家與城市" under "提示與地名" in "裝置設定" stops the lookups.
- Deleting the app deletes all of its data on your iPhone, including the pairing file and the DDI files. Copies in iCloud or computer backups are kept according to your backup settings.
- You delete exported backup files, GPX files and pairing files yourself.
- Apart from emails you send us, JetPiggy holds none of your data. Data received by Apple and GitHub is kept under their policies.

### Security

- Data on your iPhone is kept in the private storage iOS gives the app; other apps cannot read it. The pairing file also has iOS data protection; see "Pairing file" above.
- The DDI is downloaded over encrypted HTTPS. The request to Apple's signing server is sent over HTTP without encryption; see "DDI" above. Connections for maps and place services are handled by iOS.
- Packets in the local tunnel never leave your iPhone.

### Children

The app is a tool for general use, not designed specifically for children. Whatever the user's age, the app sends no data that identifies anyone to JetPiggy.

### Your rights

The app's data is only on your iPhone and in your own iPhone backups, where you can view, export and delete it yourself; see "Retention and deletion" above. The only data we hold is emails you send us. To see or delete them, or with any privacy question, please contact us.

### Changes to this policy

When this policy changes, we will update this page and the effective date above.

### Contact

JetPiggy · <gflyer@jetpiggy.com>
