# GFlyer iOS Handoff

## 新對話快速開始

在新的 AI 對話中，可以直接要求：

> 請以 `C:\Project\GFlyer_IOS` 作為唯一工作目錄，完整讀取 `AGENTS.md`、`HANDOFF.md`、`README.md` 與 `docs/IMPLEMENTATION_PLAN.md`。這是一個沒有本機 Mac、供個人側載的 iOS 專案。先建立 GitHub Actions macOS 編譯驗證流程，再處理真機簽署與硬性可行性測試；不要修改 `C:\Project\GFlyer` 的 Android 專案，也不要宣稱 Windows 靜態檢查等同 Xcode 或 iPhone 實機驗證。

## 專案位置

這是從 Android repository 分離出來的獨立專案：

```text
C:\Project\GFlyer_IOS
```

Android 專案仍在：

```text
C:\Project\GFlyer
```

兩者不應再共用工作樹或互相搬移檔案。

## 使用者目標

使用者想要一個與 GFlyer Android 主要功能相近的 iOS App，供自己側載使用，不上架 App Store。第一次可以連接電腦完成安裝、配對與準備；之後正常傳送位置及執行路線時，不需要一直連接電腦。

## 目前已完成

- SwiftUI + MapKit 地圖介面
- 飛豬品牌地圖標記、地圖點擊選點、地點/座標搜尋及右側地圖工具列
- 地圖目前位置按鈕、真實 Core Location 權限流程及使用者位置標示
- 傳送、單點、多點及螺旋探索四種模式
- 非線性 1.8-900 km/h 速度控制、內建/自訂速度預設及 20 km/h 提示
- App 前景搖桿控制
- 收藏、歷史、收藏資料夾、命名路線及路線草稿重啟恢復
- 可收合底部控制面板及原生 sheet/menu 操作
- 暫停、繼續、停止
- 循環路線，以及走回起點/直接返回
- iOS 17 `CLBackgroundActivitySession`、`location` background mode 及可見背景定位指示；路線/探索停止、完成或失敗時會釋放
- Pairing File 匯入、檔案保護與本機儲存
- Preview backend，讓沒有 `idevice` 靜態函式庫時仍可開發 UI
- `idevice` backend 的 CoreDevice/RPPairing、RemoteXPC、`location_simulation_set()` 與 `location_simulation_clear()` 接點
- `BrokenPipe`、`Channel closed`、connection reset/not connected 後清理舊資源並自動重建一次 CoreDevice session
- 通道測試後保留健康的 CoreDevice session；但 Stop/Clear 會拆掉模擬 session，讓 iOS 回退真實 GPS（見下方 0.4.3 說明），下一次 Start 重建
- 目標 IP 改變、Pairing File 被替換或 transport 真正斷線時會清理與重建 session；斷線訊息分別說明行動網絡與 Wi-Fi/熱點的恢復方式
- Personalized Developer Disk Image 下載、固定 revision、SHA-256 驗證及需要時掛載
- 修正固定 DDI commit 的 BuildManifest SHA-256 與 iPhoneOS Rust sysroot 建置參數
- App 重啟/強制關閉後的「強制清除模擬定位」恢復路徑
- 與 Android 共用 Cloudflare Worker/D1 的私人留言板：座標、路線、公告、
  回覆、標籤、期限、置頂及搜尋
- 邀請碼／管理員登入、Keychain session token、未讀徽章、前景靜默刷新、
  邀請碼與成員管理
- Android 分享內容可在 iOS 預覽、直接傳送／開始路線，或另存到本機收藏；
  執行中的定位不會被留言板內容意外覆蓋
- 留言板與 CoreDevice 完全分離，不讀取或上傳 Pairing File、DDI、Apple
  簽署資料或裝置通道內容
- `GFlyerIOS-Idevice` XcodeGen scheme
- GitHub Actions macOS simulator test 與 unsigned device archive workflow
- 實機硬性可行性測試記錄表
- `idevice` MIT 授權 notice 與個人側載限制文件
- `0.3.0 (5)` 從 Android 版移植的功能（macOS CI 已通過，實機驗證未跑）：
  - 跨日期傳送提醒（經度離線估算時區，可在設定關閉）
  - 多點路線播放選項：逐點傳送移動方式、到點停留秒數、繞圈（含跳過鍵）／
    微動到點動作、手動「下一點」前進、開始前倒數、自動停止計時器
  - 搖桿位移動力學（三次曲線、不對稱加減速、推到邊持續加速）與獨立搖桿限速
  - GPX 1.1 匯入（trk/rte/wpt）與全部路線匯出
  - 與 Android 互通的 `GFlyer Backup` v1 備份／還原（收藏、歷史、資料夾、
    路線、速度預設；UUID 與 Android long id 雙向映射）
  - 座標圖鑑：從 GFlyer-updates Pages 下載 `coordinates.json`、分類／子分類
    瀏覽、搜尋、星號最愛、到訪提醒、匿名過期回報；iOS 不內建種子資料，
    第一次載入需要網路
  - 中斷恢復：模擬中每 15 秒與到點時寫入快照（10 分鐘有效），重啟時提示
    從中斷位置恢復
  - `LocalDataSnapshot` 改為容錯解碼，新增欄位不會清空既有收藏／路線
- `0.4.0 (6)`：
  - App 內更新檢查：讀取與 SideStore 相同的 `altstore.json`，比對版本後
    提示，並用 `sidestore://install?url=` 把安裝交給 SideStore／AltStore。
    App 本身不會也不能安裝 IPA。前景最多每 6 小時檢查一次，可「今日不再
    顯示」，設定頁有手動檢查與一鍵加入來源
  - 修正播放迴圈誤用共用 `lastError`：其他畫面（例如留言板守衛）的錯誤
    訊息會讓進行中的路線停住，且暫停／繼續無效
  - 修正地圖工具列點擊穿透到後方地圖、底部控制列被鍵盤推到畫面中間、
    搜尋鍵盤無法關閉
  - 發佈路徑改為 AltStore／SideStore 來源，見 `docs/ALTSTORE_DISTRIBUTION.md`
  - `0.4.0 (6)` 已發佈到公開的 `GFlyer-updates`（release `ios-v0.4.0`）並
    確認可以從 SideStore 來源安裝到實機。來源檔必須維持舊版 AltStore 扁平
    格式，細節見 `docs/ALTSTORE_DISTRIBUTION.md`
- `0.5.0 (12)`：補錄步數（對應 Android 的 Health Connect 補錄）。
  - **不使用 HealthKit**：免費 Apple ID 拿不到 HealthKit entitlement，
    SideStore 重簽時會被剝離（已查證）。改為呼叫使用者自建的「捷徑」，由
    捷徑用它自己的權限寫入健康 App，因此免費與付費帳號都能用。
    **不要改成 App 直接寫 HealthKit**，那會讓免費使用者完全不能用。
  - `shortcuts://x-callback-url/run-shortcut`，巢狀回呼網址必須逐字元編碼
    （`?`、`&`、`=` 未編碼會被外層網址吃掉，有測試守著）。
  - 回呼 `gflyer://steps/done|failed?id=` 由 `GFlyerIOSApp.onOpenURL` 接住，
    需要 Info.plist 的 `CFBundleURLTypes` 宣告 `gflyer` scheme。
  - 只保留最近七天紀錄；合計只計入捷徑回報成功者。GFlyer 讀不到健康資料，
    所以介面明講這是「送出的補錄」而不是健康 App 的實際步數。
  - 不做 Android 那套時間區間分配（使用者指定只需單次寫入）。
- `0.4.5 (11)`：完整清除改為「驗證＋指引」設計。**實機確認**：清除並拆掉
  session 後，需要開關一次飛行模式，其他 App 才會回到真實位置——指引內容
  與實測相符。發佈流程自此統一寫在 `docs/RELEASE_PROCESS.md`。**實機發現**：即使拆掉模擬
  session，iOS 仍沿用快取的模擬定位，直到取得新的真實 fix（0.4.4 拆 session
  的做法在實機上也無法立刻回報真實位置）。因此：
  - 一般停止回到輕量行為：清座標點、保留 session（蜂窩網路友善），訊息不
    宣稱已恢復真實定位
  - 設定的「完整清除模擬定位」：清除＋拆 session＋抓一筆新定位驗證，如實顯
    示「真實位置／仍是模擬座標（附關 VPN、開關飛行模式指引）／取不到定位」
  - `clearLocation` 增加 `tearDownSession` 參數區分兩種路徑
  - **任何清除路徑都不可以宣稱「已恢復真實定位」而不驗證**
- `0.4.4 (10)`：修正強制清除沒有回饋；嘗試以拆 session 恢復真實 GPS（實機
  證實不足夠，見 0.4.5）。
  - （0.4.3 起）停止與清除的競態：被取消的播放任務可能有一筆 `setLocation` 在
    路上，會在 clear 之後才落地。停止現在先 `await` 這些任務結束才清除，`send()`
    開頭也加了取消守衛。
  - （0.4.3 起）定位按鈕改用連續更新且只接受按鈕按下之後的新定位，避免回傳
    快取的殘留模擬座標；結果帶 `isSimulatedBySoftware` 旗標如實標示。session
    未拆除前這會逾時，拆除後才真正取得真實定位。
  - 設定頁「強制清除模擬定位」改為 await 並顯示成功／失敗訊息（原本把清除丟到
    背景，設定頁看不到任何回饋）。
- `0.4.2 (8)`：修正 App 內更新檢查永遠回報「已是最新版本」。**已在實機
  確認**：SideStore 以免費 Apple ID 安裝後，執行時的 bundle identifier 確實
  帶有 team id 後綴，與來源檔的 `com.geopilot.gflyer.ios` 不相等，原本的完全
  相等比對因此永遠落空。`AltStoreSourceParser.matchingApp` 的三層比對
  （相等 → 點號邊界前綴 → 單一 App 來源）不可以改回完全相等。設定頁
  「關於」會顯示執行時的 Bundle ID，方便再次診斷這類問題。
- `0.4.1 (7)`：加入 App 圖示。先前沒有 `AppIcon.appiconset`，主畫面只顯示
  空白預設圖示。圖示由 Android 版共用的 `gflyer_icon_art.png` 產生：取中央
  75%（對應 Android adaptive icon 遮罩後實際可見的範圍），放大到
  1024×1024 並存成無 alpha 的 24-bit PNG。`project.yml` 需要
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`，否則 asset catalog 裡的
  圖示不會被套用

GitHub Actions 的兩個 job 已在 Xcode 16.4 完整通過。Simulator unit test 曾因
App target 的 `PRODUCT_NAME` 是 `GFlyer`，
而 XcodeGen 預設 test host 仍指向 `GFlyerIOS.app/GFlyerIOS` 而失敗；目前已在
`project.yml` 明確設定 `TEST_HOST` 與 `BUNDLE_LOADER` 指向
`GFlyer.app/GFlyer`。該問題排除後，測試編譯進一步發現 `PRODUCT_NAME`
同時把 Swift module 改名為 `GFlyer`，與測試的 `@testable import GFlyerIOS`
不一致；固定 `PRODUCT_MODULE_NAME: GFlyerIOS` 後，Simulator tests 與
`Idevice unsigned archive` 均已通過。最初通過的程式 commit 是 `b777985`；新增目前位置、
正式背景定位活動及 CoreDevice transport 自動重連後，Xcode 16.4 workflow 亦於
commit `b0c9618` 再次全部通過。Stop/Clear 後保留 CoreDevice session 的
`0.1.2 (3)` 修正在 commit `9728992` 通過 workflow
[`31932297918`](https://github.com/michaelcheung0125-svg/GFlyer_IOS/actions/runs/31932297918)。
產出的 unsigned IPA 位於：

```text
C:\Project\GFlyer_IOS\artifacts\9728992\GFlyerIOS-Idevice-unsigned.ipa
SHA-256 352CAB80A729C2ACFFA199B18C47D6219B2AFB483C459E5DC5CBF1DC740B8EA3
```

Android/iOS 留言板版本 `0.2.0 (4)` 在 commit `1eabf69` 通過 Xcode 16.4
workflow [`32275792347`](https://github.com/michaelcheung0125-svg/GFlyer_IOS/actions/runs/32275792347)：
15 個 Simulator tests 全部通過，`Idevice unsigned archive` 亦成功。新 artifact：

```text
C:\Project\GFlyer_IOS\artifacts\1eabf69\GFlyerIOS-Idevice-unsigned.ipa
SHA-256 1771316CC5026DBF3B837352DEB73DE79EF528F224C630E90D0BA07EAAB08D32
```

這只證明 Swift/XCTest、arm64 device archive 與 `idevice` link 成功；尚未證明
個人簽署、iPhone UI、真實 Android/iOS 雙向留言板或目標 iPhone 定位回歸。

`0.3.0 (5)` 在 commit `ada19c5` 通過 Xcode workflow
[`33500571429`](https://github.com/michaelcheung0125-svg/GFlyer_IOS/actions/runs/33500571429)：
38 個 Simulator tests 全部通過（含新增的 `PlaybackFeatureTests`、
`TransferTests`、`CoordinateLibraryTests`），`Idevice unsigned archive` 亦
成功並產出 unsigned IPA artifact。實機回歸、個人簽署與 Android 備份／
座標圖鑑互通仍待驗證。

## 重要檔案

```text
project.yml
README.md
THIRD_PARTY_NOTICES.md
docs/IMPLEMENTATION_PLAN.md
scripts/build_idevice.sh
GFlyerIOS/Model/GeoCoordinate.swift
GFlyerIOS/Model/SimulationModels.swift
GFlyerIOS/Model/MessageBoardModels.swift
GFlyerIOS/Services/SimulationController.swift
GFlyerIOS/Services/DeviceLocationService.swift
GFlyerIOS/Services/IdeviceLocationSimulationBackend.swift
GFlyerIOS/Services/DeveloperDiskImageStore.swift
GFlyerIOS/Services/PairingFileStore.swift
GFlyerIOS/Services/MessageBoardAPIClient.swift
GFlyerIOS/Services/MessageBoardController.swift
GFlyerIOS/Services/MessageBoardSessionStore.swift
GFlyerIOS/UI/MainView.swift
GFlyerIOS/UI/MessageBoardViews.swift
GFlyerIOS/UI/SetupView.swift
GFlyerIOSTests/GeoMathTests.swift
GFlyerIOSTests/FeatureModelTests.swift
GFlyerIOSTests/MessageBoardTests.swift
GFlyerIOS/Services/LocalDataStore.swift
GFlyerIOS/Services/PlaceSearchService.swift
GFlyerIOS/UI/LibraryViews.swift
```

## 下一個對話應先做什麼

新對話開始時，先讀取本檔案、`AGENTS.md`、`README.md` 及 `docs/IMPLEMENTATION_PLAN.md`，然後依序處理：

### -1. 驗證 `0.3.0 (5)` 的新功能互通

macOS CI 已在 commit `ada19c5`（run `33500571429`）通過。接下來：
用一部 Android 裝置匯出 `gflyer-backup.json`，在 iOS 還原驗證互通（反向
亦然）；確認 `GFlyer-updates` Pages 上的 `coordinates/coordinates.json`
可公開存取並在 iOS 圖鑑載入；在實機驗證播放選項（逐點傳送／停留／繞圈／
手動前進／倒數／自動停止）、跨日期提醒、搖桿動力學、GPX 匯入匯出與
中斷恢復提示。

### 0. 驗證留言板 `0.2.0 (4)`

macOS CI 已完成。下一步用一部 Android 及一部 iPhone 交叉測試：各自發布
座標、路線與回覆；iOS 預覽／傳送／收藏 Android 內容；
管理員發布公告、置頂、設定邀請碼及撤銷測試裝置。不得把沒有 token 的 HTTP
`401` 健康檢查誤當成完整互通驗證。

### 1. 驗證目前第 1 至第 3 階段

目前第 1 至第 3 階段，以及目前位置／背景活動的程式已在 commit `b0c9618`
通過以下兩個 Xcode 16.4 job；下一步是以新 IPA 做目標 iPhone 回歸：

- `Preview scheme tests`：產生 Xcode 專案並在 iOS Simulator 執行測試。
- `Idevice unsigned archive`：建置固定 revision 的 `idevice`，無簽署 archive
  `GFlyerIOS-Idevice`，並上傳 unsigned IPA 與 `.xcarchive` artifact。

unsigned IPA 不能直接安裝到 iPhone；它只驗證 device target 可以編譯與連結。
個人簽署仍需在受信任的 Mac 或安全的簽署流程完成。不要把 Apple 憑證、私密
金鑰或 provisioning profile 寫入 repository；如日後加入簽署 job，只能使用
GitHub Actions encrypted secrets。

使用其他可用的 Mac 時可手動執行：

```bash
cd GFlyer_IOS
brew install xcodegen
chmod +x scripts/build_idevice.sh
xcodegen generate
open GFlyerIOS.xcodeproj
```

### 2. 先完成硬性可行性測試

不要先擴充完整 UI。先在目標 iPhone 與 iOS 版本驗證：

1. `GFlyerIOS-Idevice` 可以個人簽署並安裝。
2. Pairing File 能被匯入。
3. LocalDevVPN 能提供 `10.7.0.1:49152` raw RPPairing 連線；設定頁的通道測試顯示「連線成功」。
4. Personalized DDI 能下載、驗證與掛載。
5. Apple Maps 會顯示第一個模擬位置。
6. 第二次座標更新可重用連線。
7. Stop/強制清除後恢復真實 GPS。
8. 拔掉/不連接電腦後仍能重複執行上述操作。
9. 未啟用模擬定位時，目前位置按鈕會要求定位權限並把地圖移到 iPhone 的位置。
10. 多點路線開始後切到其他 App 1 至 30 分鐘，確認背景定位指示仍存在、路線仍前進，回到 GFlyer 不再出現 `BrokenPipe`/`Channel closed`。
11. 在飛行模式建立第一條通道後開啟行動網絡，驗證 Clear → Start 與路線 Stop → Start 都能重用同一 session，無需再開飛行模式。
12. 強制關閉 App 或斷開 LocalDevVPN 後，驗證行動網絡的提示要求以飛行模式重建，而 Wi-Fi/個人熱點提示明確說明無需飛行模式。

使用 `docs/DEVICE_FEASIBILITY_CHECKLIST.md` 記錄環境、每一步結果與失敗階段。

### 3. 收集實機證據

每次測試記錄：

- iPhone 型號
- iOS 版本
- Xcode 版本
- `idevice` revision
- LocalDevVPN 版本與目標 IP
- 設定頁通道測試顯示的完整 `idevice` 錯誤碼與訊息（不可附上 Pairing File 內容）
- pairing file 產生方式
- 失敗階段：pairing、tunnel、DDI、RemoteXPC、location set 或 clear
- Apple Maps 顯示結果

## macOS 建置與依賴

`GFlyerIOS` 一般 scheme 使用預覽後端；真正裝置模式需要先執行：

```bash
./scripts/build_idevice.sh
xcodegen generate
```

這會從固定 commit 建立 `idevice-ffi` iOS static library，並放入未追蹤的：

```text
GFlyerIOS/Vendor/idevice/include/idevice.h
GFlyerIOS/Vendor/idevice/include/module.modulemap
GFlyerIOS/Vendor/idevice/lib/libidevice_ffi.a
```

DDI 會在 App 第一次需要時下載到 iOS Application Support，並以 pinned SHA-256 驗證。不要把 DDI binary 放進 Git。

## 目前已知限制

- Windows 目前只能做檔案、語法、YAML、plist 與文件檢查；不能取代 Xcode 實機編譯。
- App Store 不支援這種全機 GPS 模擬方式；本專案只做個人側載。
- 背景路線使用正式 Core Location background activity，不使用靜音音訊等保活方式；仍不能保證強制關閉、系統資源終止、VPN 中斷或未來 iOS 版本下無限執行。
- 背景定位會顯示 iOS 系統指示並增加耗電，停止路線後應確認指示消失。
- 已建立的 CoreDevice socket 在實測中可從飛行模式延續到行動網絡；新版會在 Stop/Clear 後保留它，但此行為仍需新 IPA 實機驗證。App 被系統終止、VPN 斷線或 socket 失效後，行動網絡使用者仍需飛行模式重建；Wi-Fi/熱點使用者無需。
- iOS 更新可能讓 pairing file、DDI 或 Apple 私有協定失效。
- 個人簽署 profile 會過期，過期時可能需要重新簽署或使用電腦刷新。
- 地圖及搜尋需要網路；定位控制本身透過 LocalDevVPN/裝置開發服務。
- 留言板需要 Internet 及有效邀請／session；離線時留言板不可用，但不應影響
  已建立的 LocalDevVPN/CoreDevice 定位通道。
- 留言板後端、Android/iOS 實際雙向發布及管理流程仍需在 `0.2.0 (4)` IPA
  做跨裝置驗證；Windows 靜態檢查不能證明 Swift 編譯或互通成功。
- 第三方 App 可以拒絕模擬位置，且其服務條款仍然適用。

## 不要做的事

- 不要把本專案搬回 `C:\Project\GFlyer`。
- 不要修改 Android 專案來解決 iOS 問題。
- 不要複製 StikDebug AGPL UI 或應用程式碼。
- 不要提交 Apple signing secrets、Pairing File、DDI 或 `libidevice_ffi.a`。
- 不要加入反偵測、修改遊戲客戶端或規避第三方檢查。

## 完成標準

目前的第 1 至第 3 階段只有在新 workflow 的 Preview tests 與 Idevice archive
通過，並在目標 iPhone 回歸傳送、第二次更新、Stop 清除、單點、多點、探索與
搖桿後，才算驗證完成。這次新增的目前位置及背景播放需另外通過上述實機測試；
留言板還需通過 Android/iOS 雙向發布、回覆、管理與撤銷 session 測試。
`0.3.0 (5)` 的播放選項、跨日期提醒、搖桿動力學、GPX、備份、座標圖鑑與
中斷恢復已通過 macOS CI（commit `ada19c5`、run `33500571429`），仍需實機
與 Android 互通驗證。冷卻計時 UI 與路線重排仍屬後續工作。
