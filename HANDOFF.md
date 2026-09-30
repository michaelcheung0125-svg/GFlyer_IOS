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
- 傳送、單點、多點及探索四種模式（0.6.9 起探索是和 Android 相同的蛇形，取代螺旋）
- 非線性 1.8-900 km/h 速度控制、內建/自訂速度預設及 20 km/h 提示。0.6.9 起：
  速度預設上限從 12 改成 6，和 Android 一致；已經存了超過 6 個的使用者原本的全部保留，
  只是不能再新增，刪掉一個只會少一個。匯入備份時最多取 6 個。新增速度預設時
  去掉名稱前後空白、最多 20 個 Unicode code point，和 Android 相同（原本不限長度）
- App 前景搖桿控制
- 收藏、歷史、收藏資料夾、命名路線及路線草稿重啟恢復（0.6.9 起清單顯示和 Android 相同的「國家 · 城市」與時間）
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
    路線、速度預設；UUID 與 Android long id 雙向映射）。0.6.9 起：
    iOS 不認識的 settings 鍵原樣保留、匯出時寫回，Android → iOS → Android
    往返不再把 Android 專屬設定重設成預設值（`AppBackupCodec`、
    `LocalDataSnapshot.foreignSettings`，`TransferTests` 有 3 個測試）。同一批：備份陣列裡混進
    非物件元素時只略過那一個，不再讓整個集合被丟掉。再同一批（GFlyer-Suite DRIFT D12〜D17，
    commit `bb542f8`）：備份解析嚴格區分布林與數字（`"loop": 1` 不再是 true）、名稱以 Unicode
    code point 截斷、備份缺少 `crossDateWarningEnabled` / `autoStopMinutes` 時還原成預設值
    （原本保留裝置目前的值）、`autoStopMinutes` 不是選項值時距離相同取較大的（15 分鐘變 30，
    原本變成 0 等於關掉自動停止）；座標圖鑑陣列裡的非物件元素也改成逐一略過。
    備份檔在第一個 JSON 物件之後還有其他內容時忽略那些內容、照常還原（DRIFT D16）：舊版
    Android 在 Android 10 以後覆寫比較長的同名備份時不截斷檔案，這種檔案原本 iOS 還原不了。
    建立資料夾時先截斷到 40 個字再比對同名，不會再建出兩個同名資料夾；資料夾最多 30 個，
    和 Android 相同（原本沒有上限，但兩個平台還原備份都只取前 30 個），已經超過的保留。
    路線名稱儲存時一律「去掉前後空白 → 截斷到 80 → 再去掉結尾空白」
    （`SavedRoute.normalizedName`），另存留言板路線不會再無聲覆蓋同名路線。
    GPX 匯入的路線名稱補讀 CDATA（原本 `<name><![CDATA[...]]></name>` 會變成「匯入路線」），
    儲存時比對同名改用 `lowercased()`，和產生名稱時同一條規則（DRIFT D18；Android 已改成和 iOS
    相同的匯入命名）
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
- `0.6.9 (22)`：2026-09-30 發佈到 `GFlyer-updates`（release `ios-v0.6.9`，來源檔 commit `e8ff807`）；
  IPA 是 CI run `36774670035`（`b61e3d0`）的產物，SHA-256 `012afc51…cbe6708e33`，10,158,261 bytes。
  第一次用 GFlyer-Suite `tools/release/release_manifest.py` 發佈，同時建立了 `releases.json`（目前只有
  `ios`），App 介紹的「螺旋探索」改成「蛇形探索」。**使用者決定跳過實機驗證先發佈**；2026-10-01 使用者從
  SideStore 更新到 0.6.9，回報實機測試沒有問題（沒有逐項回報下面各批的「尚待驗證」）。Android 0.8.7 還沒發佈。原本和 Android 0.8.7
  一起準備，規格在 GFlyer-Suite `docs/features/*.md`，Android 是參考實作。這一段是
  「小修正、留言板字數、資料過時回報、D8 文件」那一批；其他功能各自補在下面。
  - **速度比較**（`contracts/fixtures/speed/preset-speed-values.json`）：一律用 km/h 的
    Double、容差 0.01 km/h（`SpeedScale.isSameSpeed` / `isBelow` / `isAtMost`）。內建
    預設改用 `QuickSpeedPreset.isBuiltIn`（名稱完全相同 + isSameSpeed），還原 Android
    備份後「正常走路」「腳踏車」「汽車」不再出現刪除鈕；種花警告改成
    `!isAtMost(v, 20)`，文字改成 Android 的「注意: 超過 20 km/h 將無法種花」。
  - **舊版走路預設**（`backup/legacy-walk-preset.json`）：還原備份時名稱完全等於
    「正常走路」且 |m/s − 1.4| < 0.001 的換成 5.0 km/h；`LocalDataSnapshot` 解碼時對
    已經存著的 5.04 km/h 做同一件事（冪等，不加資料版本，下一次存檔寫回）。
  - **收藏**（`docs/features/name-limits.md`）：新增與改名都是 N2（去空白 → 80 個
    code point → 去結尾空白），改名成空白不動、對話框的「儲存」停用。讀取時不改名。
    收藏按鈕照 Android：座標已經收藏過時顯示「此座標已經收藏過」、不再取代那一筆；
    沒有名稱時是「收藏 <座標>」（原本「位置 <座標>」）；成功是「收藏成功」。留言板
    存成收藏時，只有空白的座標名稱與留言也會跳過。
  - **座標圖鑑型別**（`coordinate-library/type-strictness.*`）：布林不是數字、數字不是
    布林（`isBoolean`，和備份相同）；分類圖示、頂層 `updatedAt` / `source` 原樣保留、
    不去空白（照 Android）。
  - **GPX 匯入**（`docs/features/gpx-import.md`）：讀不到的檔案略過、整批只有一則訊息
    （全部都讀不到時是「找不到可用路線」），沒有路線的檔案不再另外跳錯誤。載入第一條
    匯入路線時不動循環設定；模擬中也可以按「匯入 GPX 路線」，路線照存、不載入。
    載入條件抽成 `SimulationController.shouldLoadImportedRoute`。
  - **留言板字數**（`docs/features/message-board-limits.md`，I1–I15、I17）：全部以
    code point 計算，常數在 `BoardTextLimits`（以 fixture id 為鍵）。搜尋框補上 80、
    公告標籤輸入框補上 120；分享收藏座標與路線時送出前正規化名稱（本機不改）。
    標籤去重改成區分大小寫。本機訊息照 Android：必填是「請輸入使用者名稱及共用邀請碼」
    ／「…及管理員啟用碼」，邀請碼、啟用碼、「請先加入留言板」、「留言板伺服器尚未設定」
    等去掉句號；管理員設定邀請碼時長度（「共用邀請碼需為 4 至 32 個字元」）與字元分開
    檢查。I16（N/300 計數器，選做）沒有做。**Worker 必須在 App 之前部署。**
  - **資料過時回報**（`docs/features/coordinate-stale-report.md`，C-I1–C-I8）：只有明信片
    有「回報資料已過時」；原因、預設值、「送出回報」、300 code point 上限照 Android；
    送出內容 `coordinateId` / `coordinateName` 原樣、`message` 不去空白且一律帶鍵；任何
    2xx 都算成功；失敗一律「回報送出失敗，請稍後再試」。「這筆座標資料無效」去掉句號。
  - **D8 文件**：`docs/RELEASE_PROCESS.md` 第 5–7 步改用 GFlyer-Suite 的
    `tools/release/release_manifest.py`（`build ios` → `project --dry-run` → `project`，
    投影前先 rebase，`git add altstore.json releases.json`，發佈後跑 `check`）；
    `ALTSTORE_DISTRIBUTION.md`、`README.md`、`TROUBLESHOOTING_CASES.md` 同步。
    文件原本說 `GFlyer_IOS` 是私有 repo，實際是**公開**的（標準 runner 不計費），一併
    改正。`scripts/update_altstore_source.py` 留到升版 commit 再刪。
  - **尚待驗證**（實機）：還原 Android 備份後速度預設沒有刪除鈕；收藏重複時的提示；
    複選 3 個 GPX（含一個壞檔）；留言板 30 個 emoji 的使用者名稱、300 個 emoji 的回覆；
    明信片回報成功與關網路時的失敗訊息。
  - **多點路線到點動作**（另一批，`docs/features/route-arrival-actions.md` 的 I1–I12，
    照 Android；決定：Q1 舊的「定點傳送 + 無動作」保留、Q2 一次性提示、Q3 半徑照 Android
    去重、Q5 「瞬間跳轉」循環不回第 1 點、Q6 手動前進說明不寫「懸浮」）：
    - 到點動作、手動前進、停留只在多點「定點傳送」使用；「模擬移動」到點不停。手動前進時
      停留一律 0。倒數只在多點模式按「開始」時有；單點路線與留言板路線直接開始是純走路、
      不倒數（只預覽、自己按「開始」照多點處理）。決定都在 `Model/RouteArrival.swift`
      （`RoutePlaybackOptions.effective`、`RouteArrivalSteps`、`RouteArrivalPlan.lap`），
      `SimulationController.startRoute` 照它播放：每一圈是 `RouteArrivalPlan.playbackLap`（同一份
      `lap` 配上座標），訊息的點編號、到點步驟與「最後一段」都直接用 `lap` 的結果，不再有自己的一份
      編號規則；中斷恢復的第一圈用 `RouteArrivalPlan.resumedLap` 對齊到整圈的尾段。
    - `RouteTravelMode` / `RoutePointAction` / `LoopTransitionMode` 的 rawValue 是存檔
      與中斷快照裡的值，**不能改**；畫面用 `label`（定點傳送、繞圈、向東走 20 米、瞬間跳轉）。
    - `PlaybackSettings`：停留 1〜300（原本 0〜300、步進 5 → 1）；到點動作在定點傳送的預設是
      繞圈（Android），但存檔裡新安裝是「無」＋`preselectsOrbitForTeleport`，第一次切到定點傳送時
      `selectTravelMode` 才預先選好繞圈（只做一次）；繞圈半徑照 Android 整理（範圍外丟掉、去重、
      前 4 個、空的用 [20, 30]），新增一圈 40 米、可刪任一圈；新增 `arrivalRulesVersion`（新安裝 2，
      0.6.8 的資料沒有這個鍵 = 1）、`pendingArrivalRulesNotice` 與 `preselectsOrbitForTeleport`
      （0.6.8 不認得這幾個鍵）。
    - **遷移**（§5.3）：`LocalDataStore.init` 解碼成功後呼叫
      `migratedToArrivalRulesV2()`，有變就立刻寫回。**存的到點動作一律不改**：模擬移動 + 無動作
      保留「無」、設 `preselectsOrbitForTeleport`（切到定點傳送時預先選好繞圈）；定點傳送 + 無動作
      保留、不預先選（Q1，兩個選項都不選取）；模擬移動 + 繞圈／微動或手動前進 → 值保留、設提示
      旗標。原本把模擬移動 + 無動作寫成繞圈，降級回 0.6.8（兩種移動方式都執行到點動作）後模擬移動
      會在每個點繞圈，所以改掉。提示「多點路線設定已調整」在主畫面等其他 alert 都關掉才出現，按
      「知道了」清掉並存檔。遷移**不在** `init(from:)` / `sanitized()` 裡（那兩個每次存檔都跑）。
      降級到 0.6.8 再升級會重跑一次，規格說可以接受。
    - 播放：繞圈半徑每次開始繞圈才讀目前設定、速度每圈讀一次；狀態文字照 Android（「正在前往第
      2 點」、「已到達第 N 點」、「第 N 點 · X 秒後開始動作…」、每圈一次的「正在繞圈 · 第 i/n 圈 ·
      半徑 r 米」、「開始下一輪循環」），逐步的傳送（走路、繞圈、微動）不再蓋掉事件訊息；拿掉
      每圈結束時「瞬間跳轉」先送第 1 點的那一步。走路每步是「速度 × 0.25 秒」，拿掉 0.5 公尺
      下限（最低速 1.8 km/h 原本快 4 倍）。暫停／繼續照 Android 顯示「移動已暫停」／「已繼續移動」
      （I14，路線與探索共用，取代 0.6.8 的「已暫停」／「模擬中」），繼續後那句留到下一個事件，
      不恢復暫停前的訊息。
    - 畫面：循環選項只在多點模式出現（單點路線一律不循環，存路線時也不存看不到的循環）；
      「進階播放選項」路線播放中整組停用（`SimulationStatus.isPlayingRoute`），「循環路線」與
      「循環方式」也一樣（照 Android；原本可以切，但對播放中的路線沒有作用）。中斷快照寫正在播的
      那條路線開始時的路線點、循環與循環方式（`playingRoute`，和 Android 相同），不寫畫面上的值：
      播放中在地圖上加點或改循環，恢復的仍是剩下的點所屬的那一條路線。設定頁改成
      「多點路線倒數」（不用／3／5／10 秒＋說明）、「傳送到點停留」、「繞圈設定」。
    - 測試：`SharedContractTests` 照抄 `route/arrival-actions.json` 全部段落（offset、orbit、
      microMove、orbitRadii、orbitRadiiEdits、dwellSeconds、arrivalPlan；arrivalPlan 也對
      `playbackLap` 驗每一段與座標）；`PlaybackFeatureTests` 有 §5.3 每一列的遷移測試、版本 2
      存檔不被改寫、提示只出現一次、恢復第一圈的對齊。控制器層級的播放測試做不到：開始路線要先
      通過 `DeviceLocationService.startBackgroundRouteActivity()`，模擬器上的定位權限是未決定，
      一定回傳 false。
    - **尚待驗證**（實機）：§6 的上機清單 —— 模擬移動多點路線到點不停；定點傳送 + 繞圈 +
      停留 3 秒；定點傳送 + 向東走 20 米 + 手動前進（最後一點不等）；跳過繞圈與跳過倒數；單點
      與留言板路線直接開始不倒數；從 0.6.8 升上來，§5.3 每種舊設定各一次。
  - **蛇形探索**（另一批，`docs/features/serpentine-exploration.md`，照 Android 取代 0.6.8 的
    螺旋；決定：中斷恢復從中斷位置接著走（Android 0.8.7 也修成這樣）、0.6.8 的螺旋快照恢復成
    一輪新的蛇形、文字照 Android、數字固定照繁中格式）：
    - 模型（`Model/SimulationModels.swift`）：`SpiralPath` 換成 `SerpentinePath`，逐行照 Android
      的運算順序（段號才會和 fixture 完全相等，不要「整理」）；`ExplorationDirection` 的 rawValue
      是 `"EAST"` / `"WEST"`（設定與快照裡存的值）；`ExplorationRun` 是一輪探索的起點、目前位置、
      進度、Y 與方向；畫面文字在 `ExplorationTexts`。拿掉 `SimulationError.exploreAlreadyActive`
      （「探索已經在執行中。」）。
    - 設定：`PlaybackSettings.explorationVerticalLengthMetres`（預設 1000，夾在 200〜5000，步進
      100）與 `explorationDirection`（預設 EAST），都在明確的 `CodingKeys` 裡、寬鬆解碼（0.6.8 的
      存檔沒有這兩個鍵 → 預設值）。**不在備份裡**，`AppBackupCodec` 沒動。
    - 播放（`SimulationController.startExplore`）：每 0.25 秒從上一次的位置與進度走「速度 × 0.25
      秒」，拿掉 0.5 公尺下限；暫停時不前進。起點是模擬中的模擬座標，否則是選取點。探索中再按
      「開始探索」從目前位置、進度 (0, 0) 重新開始，不再報錯（0.6.8 會先取消播放再被擋下，模擬停在
      原地、狀態卻還是進行中）。Y 與方向探索中（含暫停）停用，`adjustExplorationVerticalLength` /
      `setExplorationDirection` 也直接忽略。點地圖只改選取點。預覽線 `explorationPreview` 輸入沒變
      就用快取（Y = 5000 約 1,300 點）。狀態文字「正在蛇形探索」只在開始時寫一次，每個 tick 的
      傳送不改寫它，所以暫停／繼續的「移動已暫停」／「已繼續移動」留到停止或下一次暫停。
    - 中斷快照（`ActiveSessionStore.swift`）：移除 `spiralCenter` / `spiralAngleRadians`，新增選填
      `explorationCenter` / `explorationState` / `explorationVerticalLengthMetres` /
      `explorationDirection`。`init(from:)` 寫在 **extension** 裡（保留 memberwise init）：0.6.8 原有
      欄位照舊要求存在，四個探索欄位各自寬鬆，壞掉只讓那一欄變 nil。`encode(to:)` 維持自動合成，
      降版到 0.6.8 仍讀得到。鍵維持 `gflyer.active-session.v1`（換鍵會連路線快照一起丟）。
      `resumedExploration` 負責清理（負數、非有限值）與補預設（進度 (0, 0)、Y 1000 再夾限、EAST、
      起點用中斷座標）；恢復時從快照的 `coordinate` 出發，不跳回起點。進度在 `send()` 之前換好，
      快照的座標與進度是同一個 tick。
    - 畫面（`MainView.exploreControls`）：標題「探索中心」／「虛擬定位已啟用」＋選取點座標；
      「預設路線寬度為鳥瞰地圖縮至最遠的寬度」「X 固定 530 米」；「Y」的 −／＋（無障礙標籤「減少
      Y 值 100 米」／「增加 Y 值 100 米」，200／5000 時停用）、「1,000 米」、「預覽 12.12 公里」；
      「左（西）」「右（東）」（全形括號）；開始鈕「開始探索」。刪掉「以選取位置為中心持續螺旋探索」。
    - 鏡頭（規格 §3.5，照 Android）：沒有在探索時，預覽的起點一改變就縮放到整條預覽 —— 切進探索、
      在探索模式點地圖或選搜尋結果改選取點、模擬座標改變、探索停止後起點換回選取點都算；只改 Y 或
      方向不縮放，探索中也不縮放。離開探索模式時忘掉上一次的起點（Android 的
      `lastExplorationPreviewCenter`），所以每次切進來都縮放一次。範圍由 `UI/ExplorationCamera`
      算：預覽落在搜尋列與控制面板之間沒被蓋住的那一塊、四周留 24 pt（Android 72 px），那一塊太矮
      時改用整張地圖；三者的位置用 `reportFrame` 在 `mapArea` 座標空間量。一般點地圖仍然不移動鏡頭。
      什麼時候縮放是純邏輯的 `ExplorationFitTrigger`：切進探索時控制面板在同一次更新裡換成探索的設定，
      新的高度比縮放晚才量到，所以縮放後 1 秒內面板的框一變、起點沒變，就用新的面板高度再縮放一次
      （探索中與停止後不補）。停止、自動停止與完整清除時 `exploration` 馬上清掉，`status` 要等
      `clearLocation` 回來才重設；中間這段 `isStoppingExploration` 讓 `explorationStart`
      （`ExplorationRun.origin`）已經是選取點，和 Android 一次清掉狀態相同，所以預覽線不會先跳到停下的
      位置、鏡頭不會先縮放過去再回來；起點沒變就完全不動，探索中點過地圖或恢復的一輪則直接縮放一次到
      選取點。清除失敗時回到停下的位置（仍在模擬，再按「開始探索」也從那裡開始）。
    - 沒有照 Android 做的（規格 §3.3 接受）：切到探索模式時 Android 把選取點換成 `mapCenter`（App
      最後自己設定的鏡頭中心，不是拖動後的畫面中心），iOS 保留目前的選取點；切進來之後鏡頭縮放到
      整條預覽，起點在哪裡都看得到。預覽線樣式沿用 iOS 的虛線。
    - 測試：`SharedContractTests` 照抄 `explore/serpentine-path.json` 全部段落（constants、
      previewDistance、segments 四組、advance 22 例、walks 5 條全部取樣點、previews 5 例）；
      `PlaybackFeatureTests` 有 §4.3 的 0.6.8 螺旋快照（`load(now:)` 貼近 savedAt）、方向
      `"UPWARDS"` 只讓方向變 nil、壞欄位不丟快照、路線快照不受影響、0.6.8 必要的鍵仍寫出、恢復時的
      清理、設定預設與夾限與存檔、Y 步進、閒置時的預覽與按鈕、文字；`ExplorationCameraTests` 有縮放
      範圍，以及 `ExplorationFitTrigger` / `ExplorationRun.origin` 的時機（停止不動鏡頭、每個新起點縮放
      一次、離開探索後重來、縮放後面板換高度補縮放一次）。
    - **尚待驗證**（實機，規格 §6）：Y 1000、EAST、汽車速度：先往北，到上緣往東 530 米，再往南
      2,000 米；預覽線與實際路線重合、開始後改從目前位置畫；切進探索、在探索模式點地圖改起點時
      鏡頭縮放到整條預覽（Y 5,000、控制面板展開時也看得到整條，不被搜尋列或面板蓋住；特別是面板展開
      時從「傳送」或路線模式切進探索，預覽下緣要在探索面板上方），只改 Y 或方向時鏡頭不動；探索幾分鐘
      後按停止、等自動停止、用完整清除，鏡頭都不動，預覽線直接回到探索前的起點，不先跳到停下的位置；
      移動中 Y 與方向停用、速度可改、暫停／
      繼續／停止；探索中再按「開始探索」不跳走、不報錯；探索幾分鐘後結束 App，恢復後從中斷位置接著
      走；用 0.6.8 在探索中結束 App，10 分鐘內升級到 0.6.9 再開，提示可以恢復且不當機。
  - **座標圖鑑前往紀錄與「隱藏已前往」**（另一批，`docs/features/library-teleport-history.md`，照
    Android App 內圖鑑；決定：只在「傳送」、座標有效而且模擬接受時記錄，「預覽」不記錄；iOS 清除後不
    彈提示；完整時間與「清除紀錄」放在列的「⋯」選單）：
    - 純邏輯（`Model/LibraryTeleportHistory.swift`）：`record`（次數 + 1、時間直接覆寫、不比較新舊）、
      `filter`、`listing`（隱藏之後的清單，加上隱藏之前算的計數、開關旁文字、空清單訊息）、
      `encode` / `decode`（和 Android `teleported_map` 同一個形狀 `{id: {"at": 毫秒, "n": 次數}}`；寬鬆
      解析：整份讀不出來是空的、逐筆略過、n 至少 1、布林不算數字）、`formatShort` / `formatFull`
      （明確設定 `en_US_POSIX`、西元曆與時區，「同一年」用同一個時區的西元曆比，佛曆／日本曆的 iPhone
      也和 Android 顯示相同）、`summary`、`countLabel`。格式器依格式與時區快取在 `NSCache`。
    - 儲存（`CoordinateMarkStore`）：**新鍵** `gflyer.coordinate-teleports.v1`（Data）與
      `gflyer.coordinate-hide-teleported.v1`（Bool，沒存過是 false），每次記錄／清除／切換都立刻寫回。
      **`Snapshot` 與 `gflyer.coordinate-marks.v1` 沒動**：在 `Snapshot` 加欄位會讓 0.6.8 的資料整份解
      不開、清掉最愛與造訪標記。不在備份裡。時間存毫秒整數（造訪標記存秒，那是既有格式）。
    - 清單（`CoordinateLibraryController`）：原本的 `visibleCoordinates` 改名 `matchingCoordinates`
      （分頁、子分類、搜尋、排序），`listing` 再套隱藏；「⏲ 提醒中」不套用（`hideApplies`），開關的值
      不變。「預覽」／「傳送」的判斷搬到 `CoordinateLibraryController.use`，在關閉圖鑑之前記錄；之後
      跨日警告被取消或連線失敗都不回滾，和 Android 相同。
    - 畫面（`CoordinateLibraryView`）：搜尋框下方「隱藏已前往」／「✓ 隱藏已前往」＋「已前往 N / 總數」
      （圖鑑還沒載入或在「⏲ 提醒中」時整列不顯示，清單空的時候照樣顯示）；全部前往過而被隱藏時，空清單
      是「這裡的點都前往過了；關閉「隱藏已前往」就會再列出來。」、不附說明；列在提醒狀態下面多一行
      「➤ 已前往 09/19 14:32 · 3 次」（強調色、單行，只去過一次不寫次數）；「⋯」選單最後一段用完整時間
      當 Section 標題，底下是「清除紀錄」。「還沒從圖鑑前往過」與「已清除前往紀錄」iOS 不顯示。
    - 測試：`SharedContractTests` 照抄 `coordinate-library/teleport-history.json` 全部案例（record
      同時走純函式與 `CoordinateMarkStore`、decode、encode 往返、format 用 fixture 的時區、summary、
      filter、messages）；`CoordinateLibraryTests` 有 0.6.8 資料升級、壞掉的前往紀錄、換一個 store 讀回、
      `Snapshot` 仍只有兩個欄位、布林、「預覽」與無效座標不記錄、控制器在分類／最愛／提醒中分頁的清單。
      被接受的「傳送」與模擬中被拒絕兩條要真的開始模擬，單元測試沒有涵蓋。
    - **尚待驗證**（實機，規格 §6）：按「傳送」後回到圖鑑，該列出現「➤ 已前往…」，再傳送一次變
      「 · 2 次」；「預覽」不記錄；模擬進行中按「傳送」被拒絕時不記錄；打開「隱藏已前往」該列消失、
      計數不變；全部前往過的分類顯示提示；切到「⏲ 提醒中」開關列消失、有紀錄的提醒座標仍列出；關掉
      App 再開開關仍是開的；「⋯」選單的完整時間與「清除紀錄」（iOS 17 的選單若不顯示 Section 標題，
      照規格改成 disabled 的項目）；從 0.6.8 覆蓋安裝後原本的最愛與造訪標記都還在。
  - **收藏的「國家 · 城市」標籤**（另一批，`docs/features/region-labels.md`，照 Android；決定：照 Android
    App 一啟動就查、隱私說明照這樣寫；路線列改成「N 個點」；「收藏前先問名稱並預填標籤」不移植，記成 DRIFT）：
    - 純邏輯（`Services/RegionLookup.swift` 的 `RegionLabel`）：快取鍵 `String(format: "%.2f,%.2f")`；請求
      `GET https://nominatim.openstreetmap.org/reverse`，參數就 `format=jsonv2`、`zoom=10`、
      `accept-language=zh-TW`、`lat`、`lon`（原始座標、`String(Double)`），`Accept: application/json`、
      `User-Agent: GFlyer/<版本> (iOS)`（和 `AppUpdateChecker` 同一個寫法）、`timeoutInterval = 8`；回應 → 標籤：
      非 2xx 不讀 body、JSON 物件的 `address` 物件、國家 + city／town／municipality／village／county／
      state_district／state 第一個不是空白的（不看 `province`），城市等於國家就丟掉、不再往下找，用「 · 」接，
      只認字串值，原樣使用不修剪。
    - 佇列與快取（`RegionLookup`，`@MainActor`，由 `SimulationController` 持有）：同一時間一個請求、依排入順序，
      每次真的送出之後（成功或失敗）等 1.1 秒，已有快取的跳過不等、第一筆不等；這次執行排過隊（只增不減）與
      失敗過的鍵不再送，失敗不寫快取、下次啟動再試。快取是**新鍵** `gflyer.region-labels.v1`（JSON 的
      `[String: String]`），每查到一筆就寫回，解不開當作空的；不過期、刪收藏／清歷史／還原備份都不清，
      **不在** `SavedPlace` / `SavedRoute` / `LocalDataSnapshot` / 備份裡，舊資料完全不受影響。transport 與時鐘
      可以注入。
    - 觸發（`SimulationController`）：`@Published regionLabels`；`init` 最後與每次 `refreshStoredData()` 送出
      「收藏位置（清單順序）+ 收藏路線第一點」，定位歷史不送。`init` 多了選填的 `regionLookup` 參數。
    - 畫面（`LibraryViews`，文字在 `LibraryRowText`）：名稱單行；第二行單行、超出以 … 截斷：收藏與歷史是
      「座標  ·  標籤」（兩個空白），路線是「N 個點 · 循環｜單程 · 標籤」（原本「N 點」）；第三行小字、不限行數：
      「收藏於／定位於／儲存於 」＋系統語言與時區的 `.medium` 日期、`.short` 時間（清單原本不顯示時間）。
    - 隱私：規格 §3.9 的共用句子一字不差加進 `README.md`（新的 Privacy 段）與 `docs/PROJECT_OVERVIEW.md`
      （「隱私」小節）。iOS App 內沒有隱私或關於說明文字（設定頁「關於」只有版本等欄位），所以 App 內沒有加。
    - 測試：`RegionLabelTests` 照抄 `region/nominatim-labels.json` 全部案例（cacheKeys 9、labels 23、
      responses 12、request），佇列用假的 transport 與時鐘測（一次一個、每次請求後 1.1 秒、同格／已快取／
      已失敗不再送、失敗不寫快取、下次啟動重試、快取壞掉是空的），`SimulationController` 的送出順序、歷史不送、
      刪掉再加回不再送、備份裡沒有標籤，以及清單文字。其他會新增收藏或路線的控制器測試改傳
      `RegionLookup.offline(defaults:)`，單元測試不會真的連 Nominatim。
    - **尚待驗證**（實機，規格 §6）：既有收藏在開 App 後陸續出現標籤；清單開著時即時更新；飛航模式下不顯示、
      不報錯，恢復網路後重開 App 會補上；刪除收藏再加回同一點不會再送請求；備份匯出檔裡沒有標籤；
      中文系統上時間是「2026年9月24日 下午1:40」這種格式。

- `0.6.8 (21)`：0.6.7 實機回報的四件事。
  - 已發佈 `ios-v0.6.8`；CI 兩個 job 通過（97 個測試），IPA 拆檢通過
    （`Assets.car`、AppIcon、版本號 0.6.8 (21)），線上 `altstore.json` 為
    0.6.8，下載網址 HTTP 200 且大小 9,949,118 bytes 與來源檔一致。
  - **按鈕沒有按壓回饋**：`mapButton` 用的 `.buttonStyle(.plain)` 會連系統
    預設的按壓高亮一起拿掉，所以按下去畫面完全不變。新增
    `PressFeedbackButtonStyle`，同時給視覺（變暗、縮到 0.93）與觸覺
    （`.sensoryFeedback(.impact(flexibility: .soft))`）。震動只在按下的邊緣
    觸發，放開再震一次會讓單次點擊感覺像兩次。視覺回饋單獨不夠用，因為手指
    通常正好蓋住剛按下的那顆。
  - **定位按鈕看起來像沒反應**：等 CoreLocation 要數秒，期間沒有任何指示。
    改為顯示轉圈並忽略重複點擊。收掉轉圈需要在 `requestCurrentLocation` 加
    `onFinish`——原本的 `onSuccess` 失敗時不會被呼叫，只靠它轉圈會卡住。
    另加 20 秒保險絲：權限尚未決定時完成回呼會被收起來等系統對話框，使用者
    不回答就永遠不會回來。
  - **控制面板收合箭頭難按**：可點範圍只有約 20pt 的字形，`.borderless`
    不把周圍空白算進去。改成整條 header 列都是按鈕（標題、座標、狀態點、
    箭頭與其間空隙），箭頭本身補到 44pt。整列寬的按鈕傳
    `scalesOnPress: false`——一整條狀態列縮起來看起來像跑版而不像回饋。
    不覆寫 accessibilityLabel，狀態訊息仍是 VoiceOver 讀出的內容，動作放在
    hint。
  - **深淺色外觀設定**：新增 `Model/AppAppearance.swift`（system／light／dark，
    存在 `gflyer.appearance`），設定頁「關於」下方新增「外觀」一節。
    `preferredColorScheme` 套在 `GFlyerIOSApp` 的 WindowGroup 根層而不是
    MainView——sheet 是另一個呈現層，套在 MainView 上設定頁自己不會變色。
    `.system` 對應 `nil`（不覆寫），值缺失或損壞都退回 `.system`，兩點都有
    測試。模擬器深色截圖仍跟隨系統，等於驗證了這條預設路徑。
  - **一次 CI 紅燈**：`Section("外觀") { } footer: { }` 這個多載不存在，帶字串
    標題的 `Section` 沒有 footer 參數，要用 content／header／footer 那一組
    （`StepRecorderView` 已經是這樣寫）。本機的括號平衡檢查擋不掉這種型別
    錯誤，只有 CI 會。
  - **尚待驗證**：實機上震動強度是否合適；關閉定位權限後轉圈是否會自己收掉；
    整條 header 可按之後會不會誤觸；設定頁開著時切換外觀是否跟著變色；
    重開 App 後外觀設定是否保留。

- `0.6.7 (20)`：地圖工具列的可點目標放大到 44pt；底下換上一組設計 token。
  - 已發佈 `ios-v0.6.7`；CI 兩個 job 通過（92 個測試），IPA 拆檢通過
    （`Assets.car`、AppIcon、版本號 0.6.7 (20)），線上 `altstore.json` 為
    0.6.7，下載網址 HTTP 200 且大小 9,924,607 bytes 與來源檔一致。
  - **設計 token**：新增 `GFlyerIOS/UI/DesignTokens.swift`，把 `UI/` 底下 157 處
    散落的樣式數值收進具名常數——間距四階 `2/6/10/14`、版面座標、狀態色與
    地圖色分成兩組、重複字體組合、圓角與動畫。盤點前光是間距就用掉 2 到 12
    之間的每一個整數。顏色一律包 SwiftUI 的語意色不寫死 hex，深色模式的自動
    切換因此保留。`routeStroke` 與 `statusAttention` 目前同值但獨立宣告：路線
    畫的是地圖資料不是警示，合併之後換警示色會連路線一起變，有測試擋住。
  - **可點目標**：`mapButton` 的 12 顆按鈕從 40×40 換成 `Metrics.tapTarget`
    (44)，收起後的箭咀從 28pt 寬換成 44。整列因此高約 24pt。這是整批改動裡
    唯一真的移動像素的一項。
  - **順手修掉一個自己造成的回歸**：間距 token 化時把外層內距從 12 換成
    `Spacing.md` (10)，但箭咀抵銷用的 `-12` 沒跟著改，於是多突出 2pt。改成
    `-Spacing.md`，兩邊指向同一個 token 就不會再漂移。
  - **CI 產出模擬器截圖**：`Preview scheme tests` job 多一步，用剛建好的 app
    截淺色與深色兩張 PNG 當 artifact。這個專案在 Windows 上開發，本機沒有
    模擬器，版面改動以前只能等實機。刻意輸出 PNG 而非 `.xcresult`（後者要
    Xcode 才打得開）。App 多一個 `-GFlyerScreenshotMode` 啟動旗標，只用來跳過
    更新檢查與留言板刷新這兩個網路動作，否則截圖會隨線上狀態而變。
    量過截圖：工具列寬 102.0pt，正好等於 `6×2 + 44×2 + 2`，44pt 確實生效。
  - **尚待驗證**：實機上工具列變高之後是否擋掉太多地圖、12 顆按鈕是否好按、
    箭咀是否貼齊右緣且好按，以及深色模式在實機上是否正確（顏色寫法全換過，
    只有模擬器截圖驗過）。

- `0.6.6 (19)`：0.6.5 的兩個回報。
  - 已發佈 `ios-v0.6.6`；CI 兩個 job 通過（86 個測試），IPA 拆檢通過
    （`Assets.car`、AppIcon、版本號 0.6.6 (19)），線上 `altstore.json` 為
    0.6.6，下載網址 HTTP 200 且大小 9,915,757 bytes 與來源檔一致。教學內容
    不變（兩項都是把已寫明的行為修回來），只更新版本標示。
  - **單指縮放又出現**：0.6.4 只在畫面出現時掃一次就關掉，實測 0.6.5 又會
    縮放，代表地圖會在自己更新版面時把手勢**重新啟用**。改為記住找到的手勢
    物件，`updateUIView` 每次（地圖一有更新）就把它們關回去，另加一個每 2 秒
    的迴圈複查、每第 4 次重新掃描整個視窗（手勢物件可能被換掉），在背景時
    不做事。
  - **搜尋列仍被鍵盤頂起，而且只在工具列展開時發生**：這個線索指向高度。
    搜尋列那一層本來用 `Spacer()` 撐滿畫面再留 112 的底部內距；工具列展開時
    整塊比鍵盤讓出的空間還高，SwiftUI 放不下就把它往上推，收起時高度足夠小
    所以看不出來。改成只佔自己高度，並用 `.overlay(alignment: .top)` 釘在
    最上面，不再參與 ZStack 的底部對齊。
  - **尚待驗證**：CI；實機上兩個問題是否都消失，特別是長時間使用、切換過
    背景之後單指縮放是否仍然關著。

- `0.6.5 (18)`：搜尋列不再被鍵盤頂起、地圖工具列可以收起。
  - 已發佈 `ios-v0.6.5`；CI 兩個 job 通過，IPA 拆檢通過（`Assets.car`、
    AppIcon、版本號 0.6.5 (18)），線上 `altstore.json` 為 0.6.5，下載網址
    HTTP 200 且大小 9,912,265 bytes 與來源檔一致。線上使用教學已同步
    （工具列表格新增收起／展開兩個箭咀）。
  - 鍵盤彈出時搜尋列與右側工具列會向上跳一下。原本的
    `.ignoresSafeArea(.keyboard, edges: .bottom)` 只加在 NavigationStack
    **裡面**的 ZStack，擋不住 SwiftUI 把整個畫面推上去；改為同時加在
    NavigationStack 外面。
  - 工具列最下一行新增「收起地圖工具列」（`chevron.right`）。收起後只剩一個
    貼住畫面右邊的 `chevron.left` 小標籤，按一下展開。狀態用
    `@AppStorage("gflyer.map-toolbar-expanded")` 記住。
  - **尚待驗證**：CI；實機上鍵盤彈出時搜尋列是否完全不動，以及收起／展開的
    外觀與動畫。

- `0.6.4 (17)`：使用者實測 0.6.3 後回報的三個問題。
  - 已發佈 `ios-v0.6.4`；CI 兩個 job 通過（85 個測試），IPA 拆檢通過
    （`Assets.car`、AppIcon、版本號 0.6.4 (17)），線上 `altstore.json` 為
    0.6.4，下載網址 HTTP 200 且大小 9,900,258 bytes 與來源檔一致。線上使用
    教學已同步（完整清除步驟、多點模式說明、版本標示）。
  - 0.6.3 的 LocalDevVPN 自動跳轉已由使用者實機確認正常。
  - 完整清除後取不到目前位置、其他 App 停在模擬位置：清除前先用同一條連線
    把位置設到最後一次已知的真實位置，等 2 秒再清除。理由與來源見
    `docs/TROUBLESHOOTING_CASES.md` 案例 4 的「後續」。真實位置由
    `DeviceLocationService.lastRealCoordinate` 記錄（只收
    `isSimulatedBySoftware == false` 且精確度有效的定位，存 UserDefaults）。
  - 多點模式會自動把「選取位置」連成第一點，刪光後再點也一樣：多點模式改成
    只放使用者點的點，可以刪到空；地圖上不再畫「選取位置」標記。單點模式
    不變（起點是目前位置）。因為兩點的多點路線不能再靠點數判斷模式，
    `RouteDraft` 新增選填的 `isMultiPoint`，舊草稿仍按點數判斷。
  - 點地圖後立即上下拖會變成縮放：這是 MapKit 的單指縮放
    （`_MKOneHandedZoomGestureRecognizer`）。沒有公開 API 能單獨關掉，
    `UI/OneHandedZoomDisabler.swift` 照類別名稱找出並停用；找不到時什麼都
    不做。雙指縮放、雙擊放大不受影響。
  - **尚待驗證**：CI；實機上三個問題是否都消失，特別是清除後 Google 地圖
    多快回到真實位置。

- `0.6.3 (16)`：GFlyer 代使用者開關 LocalDevVPN。
  - 已發佈 `ios-v0.6.3`；CI 兩個 job 通過（79 個測試，含新的 11 個
    `LocalDevVPNBridgeTests`），IPA 拆檢通過（`Assets.car` 3.9 MB、AppIcon、
    版本號 0.6.3 (16)、`LSApplicationQueriesSchemes` 含 `localdevvpn`），
    線上 `altstore.json` 為 0.6.3，下載網址 HTTP 200 且大小 9,881,280 bytes
    與來源檔一致。
  - 為何不內建 VPN：Apple 的權限表中 Network Extensions／Personal VPN 只開放
    給付費帳號，免費 Apple ID 經 SideStore 重簽拿不到；而且 SideStore 每 7 天
    重簽本身就要 LocalDevVPN，內建了用戶仍然要裝它，兩個 VPN 還會互相踢。
  - 做法：LocalDevVPN 原始碼（jkcoxson/LocalDevVPN，`LocalDevVPNApp.swift`）
    支援 `localdevvpn://enable?scheme=gflyer` 與 `disable`，開關後約 1 秒打開
    `gflyer://` 回來。新檔 `Services/LocalDevVPNBridge.swift`。
  - 結果**不看回呼**，回到前景後用 UDP `connect()` + `getsockname()` 查送往
    目標 IP 的路由是否走 `utun`／`ipsec` 介面，最多等約 10 秒。LocalDevVPN
    只導這一條路由進 VPN，所以這等於「LocalDevVPN 已連線」。這個檢查不送
    封包，不會觸發 LocalDevVPN 的隨選連線規則。
  - 按開始（及中斷恢復）時 VPN 沒開就自動跳去開，確認後才繼續；路線點數
    檢查提前到跳轉之前。設定頁可關掉自動開啟。
  - 完整清除可選「清除後同時關閉 LocalDevVPN」（預設關）：**清除成功才關**，
    而且在定位驗證之後才關（跳走後 App 不在前景，未必取得到定位）。
  - 設定頁新增 VPN 狀態、手動開／關按鈕；模擬中不准關。
  - `Info.plist` 的 `LSApplicationQueriesSchemes` 加了 `localdevvpn`。
  - 已確認：使用者在 iPhone 的 Safari 輸入 `localdevvpn://enable`，會跳到
    App Store 版 LocalDevVPN，所以它有登記這個網址。Safari 先問「是否打開」
    是 Safari 自己的確認；GFlyer 用 `UIApplication.open` 跳轉時不應出現。
  - **尚待驗證**：macOS CI 編譯與 `LocalDevVPNBridgeTests`；從 GFlyer 跳轉時
    VPN 是否真的連上、是否自動跳回 GFlyer；路由檢查在 Wi-Fi、行動網絡、飛行
    模式三種情況下是否都正確；第一次使用 LocalDevVPN（系統要求允許 VPN
    設定）時的流程。

- `0.6.2 (15)`：修好「匯入 Pairing File」按了沒反應。
  - 使用者實測回報：按下去沒有任何反應，也不報錯，等於**裝置模式的首次
    設定完全做不了**。而且沒有繞道：App 沒有宣告 `CFBundleDocumentTypes`，
    所以「檔案 App → 分享 → 開啟於 GFlyer」也看不到 GFlyer。
  - 原因是 **SwiftUI 同一個 view 上只會有一個 `.fileImporter` 生效**，串接多個
    時其餘會靜默失效。這沒有寫進 Apple 文件，見
    https://developer.apple.com/forums/thread/781186 。`SetupView` 串了三個
    匯入、兩個匯出，配對檔那個在最內層，正是被吃掉的那一個。
  - 三個匯入改成共用一個 `.fileImporter`、兩個匯出共用一個 `.fileExporter`，
    由 `ImportTarget` / `ExportTarget` 兩個 enum 決定接受哪些型別與交給誰處理。
    **不要為了「看起來清楚」再拆回多個 modifier**，那會讓 bug 重現。
  - 目標在 completion 裡先讀出再清掉，否則下一次呼叫會沿用上一次的目標。
  - 順帶：按「取消」時 `fileImporter` 也會回 failure，舊程式會誤跳「匯入失敗」，
    現在用 `describe(_:)` 把 `NSUserCancelledError` 濾掉。
  - 已發佈 `ios-v0.6.2`；IPA 拆檢通過（`Assets.car` 3.9 MB、AppIcon、
    版本號 0.6.2 (15) 皆正確）。**尚待實機驗證**五條路徑：配對檔匯入、
    GPX 匯入、GPX 匯出、備份匯出、備份還原。

- `0.6.1 (14)`：飛航切換捷徑由一個拆成兩個。
  - 0.6.0 用單一捷徑加「如果」判斷輸入是 on 還是 off。**使用者實測卡住**：
    「如果」動作有 Input 與 Condition 兩個參數，前面沒有動作時 Input 欄位
    不會直接顯示，說明與畫面對不上。
  - 飛行模式只有兩種狀態，本來就不需要分支。改成 `GFlyer 飛航開`、
    `GFlyer 飛航關` 兩個捷徑，各只有一個「設定飛航模式」動作，沒有條件也
    沒有變數要綁。**不要為了少一個捷徑改回「如果」版本**。
  - 仍然會把 `on` / `off` 當文字輸入傳過去，所以舊的「如果」版捷徑照樣可用：
    同一個名稱填進兩個欄位即可。舊的單一名稱偏好設定會自動沿用為兩個方向的
    預設值（`gflyer.airplane-shortcut-name` → on/off 兩個新鍵），有測試守著。
  - `isAutomationReady` 要求兩個名稱都非空，避免只填一半時另一個方向必然失敗。

- `0.6.0 (13)`：地圖工具列的一鍵補錄步數，以及飛航模式輔助。
  - 一鍵補錄只在**捷徑成功回報過一次之後**才直接送出，之前按下去是開啟設定
    頁。成功回呼是唯一能證明「名稱正確＋捷徑內容可用＋回呼接得到」的訊號；
    旗標 `gflyer.step-shortcut-verified` 與七天紀錄分開存，紀錄過期不會讓
    按鈕退回未設定。
  - 飛航模式輔助處理「開飛行 → 開始模擬 → 關飛行」這串操作。**iOS 沒有任何
    公開 API 讓 App 切換飛行模式**，不要再去找——輔助能做的是用
    `NWPathMonitor` 偵測網絡狀態，以及透過使用者自建捷徑的「設定飛航模式」
    動作代切。
  - 目前是第幾步**完全由連線狀態與模擬狀態推導**（`AirplaneAssistController.step`），
    不另存狀態機。所以使用者從控制中心手動切換，畫面也會跟著同步。三個步驟
    永遠都可以按，偵測錯了（VPN 會讓路徑看起來仍連線）不會卡住任何人。
  - **只有「關閉飛行模式」會自動執行**，而且只在使用者從輔助畫面按「開始模擬」
    的那一次。自動開啟刻意不做：中途失敗會把人留在斷網狀態；關閉方向失敗只是
    維持現狀。不要為了「更自動」把開啟方向也自動化。
  - `ShortcutBridge` 是兩個捷徑功能共用的網址組裝層，逐字元編碼的規則集中在
    那裡，有測試守著。
  - **`@Published` 屬性不能在自己的 `didSet` 裡無條件自我指派**：一般儲存屬性
    會抑制重入，`@Published` 經過 property wrapper 的 setter 會無限遞迴，CI
    的徵狀是測試「崩潰重啟」而不是斷言失敗。`quickStepCount` 的夾值用相等
    判斷擋住。
  - 兩個捷徑的建立步驟與排查寫在 `docs/SHORTCUTS.md`。
  - 已發佈 `ios-v0.6.0`；IPA 拆檢通過（`Assets.car`、AppIcon、版本號皆正確），
    線上來源檔與下載網址已驗證。**實機測試尚未進行。**
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
亦然）；再從 iOS 匯出、回到 Android 還原，確認懸浮狀態列、地圖供應商等
Android 專屬設定沒有被重設；確認 `GFlyer-updates` Pages 上的 `coordinates/coordinates.json`
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
