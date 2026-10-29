# iOS 公開版（App Store）上架計劃

2026-10-19 使用者決定：iOS 照 Android 分成**親友版**和**公開版**兩個版本。親友版就是現在的 App，照舊經 SideStore 安裝、保留全部功能。公開版以上架 App Store 為目標，在 iOS 27 以上做到從安裝到第一次傳送都不用電腦。參考對象是 LocationLab 和它的配對 App LL Pair（見最後的「參考」）。

這份列出上架之前要做的事，次序就是建議的處理次序。做完一項就把那一行搬到「已做」，寫上日期和 commit；編號固定，不重新編號。跨平台的紀錄在 GFlyer-Suite：`docs/DRIFT.md` 的 D35 和 `docs/PARITY.md` 的「iOS 的兩個版本」，每做完一項同時更新。Android 公開版的對應文件是 GFlyer 的 `docs/公開版上線待辦.md`，兩邊的做法盡量一致。

發佈、上傳 App Store Connect 和送審，一律等使用者明確要求（`AGENTS.md`）。

## 上 App Store 之後能不能全程不用電腦

可以，限 iOS 27 以上。條件是下面第 3–6 項和第 12–14 項都做完，並且通過審查。

| 步驟 | 親友版（現在） | 公開版，iOS 27 以上 | 公開版，iOS 26 以下 |
|---|---|---|---|
| 安裝 App | 電腦上的 iloader 裝 SideStore，再從 SideStore 裝 | App Store | App Store |
| 開發者模式的開關出現 | 安裝開發者簽署的 App 後出現 | App 叫出開關（第 13 項） | 要接電腦 |
| 配對檔 | 電腦（iloader 或 idevice_pair） | 在手機上配對（第 3–6 項） | 電腦（idevice_pair），在 App 匯入 |
| 本機通道 | LocalDevVPN | App 內建（第 12 項） | App 內建 |
| DDI | App 下載 | App 下載 | App 下載 |
| 每 7 天重簽 | 要（SideStore 自動） | 不用 | 不用 |
| 要不要電腦 | 第一次要 | **不用** | 第一次要 |

使用者仍然要自己做兩件事：在「設定」開啟開發者模式並重新開機，以及輸入配對的 PIN。iOS 不讓 App 代替使用者做。第一次設定要連得上網路，用來下載 DDI；配對時要給 App「本機網路」權限。

現在的親友版做不到，是因為它要靠 SideStore 安裝，而 SideStore 第一次安裝要用電腦上的 iloader。網上號稱 iOS 27 免電腦裝 SideStore 的 SideInstaller，本身要從網頁用來路不明的簽署憑證安裝，不採用。

## 定位（照 Android 公開版）

公開版是通用的「位置測試工具」，App、商店資訊和截圖都不提任何遊戲，類別是「開發者工具」。LocationLab 用同一套技術（開發者模式、配對檔、App 內建的本機通道、DDI、CoreDevice 定位模擬），也是以開發者工具上架，是目前最接近的先例。

- 用途照實寫：位置相關 App 的功能測試、路線重播、邊界和速度測試。商店說明只寫公開版真正有的功能。
- 拿走的功能不可以用別的方法帶回公開版：不改個名就留下、不對審查帳號停用、不用密碼或遠端開關在過審後開啟、不藏起入口，也不在公開版引導安裝親友版。審查指南 2.5.19 明文禁止隱藏或沒有說明的功能。拿走的程式要根本不在公開版的 target 裏，不是編進去再藏起來。
- 不加反偵測，不改其他 App，不繞過其他 App 的檢查，也不寫「不會被封號」之類的承諾（`AGENTS.md`）。

## 要使用者決定的事

| # | 決定 | 建議 | 理由 |
|---|---|---|---|
| U1 | 開發者帳戶：個人還是機構 | 有登記的公司就用機構帳戶（JetPiggy） | 審查指南 5.4 寫明「提供 VPN 服務」的 App 只限機構帳戶。公開版的通道只連回手機自己、不轉送一般網路流量，不算 VPN 服務；LocationLab 用個人帳戶也過了審查。機構帳戶少一個被拒的理由，商店上的賣家名稱也是公司名，個人帳戶顯示本名。兩種年費相同（US$99）；機構帳戶要 D-U-N-S 編號 |
| U2 | 公開版的 bundle id、名稱和圖示 | 照 Android 公開版：`com.jetpiggy.gflyer`、JetPiggy 的飛豬圖；App Store 名稱先查有沒有被用 | 兩個平台的公開版一致。親友版的 `com.geopilot.gflyer.ios`、名稱和圖示不變，兩個版本可以並存安裝 |
| U3 | 公開版的最低 iOS | 維持 17.4 | iOS 27 以上在手機上配對；iOS 26 以下匯入電腦產生的配對檔，現有的匯入功能就能用。只支援 iOS 27 的話，說明和審查比較單純，但會擋掉還沒升級的人 |
| U4 | 配對放在 GFlyer 裏，還是像 LL Pair 另外上架一個 App | 放在 GFlyer 裏 | 使用者少裝一個 App，第一次設定一次走完。LocationLab 分開的原因沒有公開，推測和它還要支援 iOS 26 有關。審查要求分開時再拆 |
| U5 | 收費和廣告 | 免費、沒有廣告 | 私隱標籤和私隱政策最單純。LocationLab 用訂閱加廣告 |
| U6 | 公開版拿走哪些功能 | 和 Android 公開版相同，再加 iOS 專屬的兩項（第 9 項） | 兩個平台的公開版一致，DRIFT 只需要記 iOS 專屬的差別 |
| U7 | 地名反查改用系統服務時，要不要先取得同意 | 照 Android 公開版先問（GFlyer-Suite `docs/features/region-labels.md` 3.10），文字一字不差 | 兩個平台的公開版一致 |
| U8 | 公開版的原始碼放在哪裏 | 照 Android：GFlyer_IOS 照舊是開發 repo，兩個版本都在這裏開發；送審之前用匯出工具把公開版匯出到 JetPiggy 名下的新 repo（例如 `JetPiggy/GFlyer-iOS`），歷史全新（第 28 項） | 品牌規則第 8 節要求品牌產品的 repo 在 JetPiggy organization 名下、內容清理過，第 5 節不准連去個人帳戶。GFlyer_IOS 是個人帳戶下的公開 repo，有親友版的功能、遊戲用語和私人網址，不能直接當公開版的來源。把 GFlyer_IOS 改成私人的話，macOS 的 CI 要收費（私人 repo 的 macOS 分鐘按 10 倍計），所以不改。不阻擋第二、三階段 |
| U9 | 公開版要不要在法國的 App Store 上架 | 首版不上架 | 公開版經 idevice 自己用標準加密。在法國上架要先向法國的 ANSSI 申報加密，再把文件交給 Apple；不在法國上架就不用交任何文件，`Info.plist` 寫「不用申報」，每次上傳不用再回答（第 21 項，`docs/app-store-encryption.md`）。App 只有中文介面。之後想在法國上架，申報之後再加 |

**已決定（2026-10-21）**：U2、U3、U6、U8 照建議。U2：公開版的 bundle id 是 `com.jetpiggy.gflyer`，名稱「GFlyer - 飛豬人」（和 Android 公開版的 App 名稱相同），圖示是 JetPiggy 的飛豬；App Store 上的名稱在第 22 項建 App 時查過才定。U3：最低 iOS 17.4。U6：和 Android 公開版拿走的相同，再加檢查新版和 SideStore 的連結、LocalDevVPN 的交接（第 9 項）。U8：在 GFlyer_IOS 開發，送審之前匯出到 JetPiggy 名下的新 repo（第 28 項）。

**已決定（2026-10-22）**：U7 照建議：公開版把收藏的座標送去反查之前先問，文字照 Android 公開版（第 17 項已經這樣做）。U9 也照建議：首版不在法國的 App Store 上架，加密申報照舊寫 `NO`（第 21 項）。

## 第一階段：Xcode 26 與在手機上配對

兩個版本都用得到。先在親友版做完，用 SideStore 裝到 iOS 27 的 iPhone 驗證；現在的使用者升級之後也不用再開 idevice_pair。

第一階段 2026-10-21 全部做完，見「已做」的第 1–7 項。

### iOS 27 實機畫面（2026-10-20，香港繁體中文）

使用者用 0.6.16 在 iOS 27 的 iPhone 上配對成功時的截圖，一步一步：

1. 「設定」>「私隱與保安」，「保安」一組裏的「開發者模式」（右邊寫「開啟」）。台灣繁體中文叫「隱私權與安全性」，還沒有那邊的截圖。
2. 「開發者模式」頁：開關下面有「配對的裝置」（這支 iPhone 列出 iloader）和「其他裝置」（旁邊一直轉圈）。GFlyer 在「其他裝置」顯示成藍色的「Pair with GFlyer」，是英文，沒有翻譯；名稱來自 TXT 的 `name`。
3. 按下去跳出「要與「GFlyer」配對嗎？」，說明是「配對後，你將可以從此電腦透過乙太網絡或Wi-Fi連接取用你的設定及資料。」，按鈕「取消」和「配對」。
4. 按「配對」後是「輸入密碼」頁，6 個圓圈，下面寫「請輸入「GFlyer」上顯示的六位數字代碼來配對。」。GFlyer 的 PIN 通知（「GFlyer 配對」／「在「設定」輸入 PIN：……」）會蓋在這一頁上面，看得到數字。
5. 輸入後，系統的背景工作進度（標題「在這支 iPhone 上配對」、副標「PIN：……」、打勾）和「GFlyer 配對完成」通知一起出現；回到 GFlyer，設定頁顯示「配對完成，Pairing File 已更新。」。「配對的裝置」只有 iloader：剛配對完和之後再進這一頁都沒有 GFlyer，所以「設定」裏沒有取消 GFlyer 配對的地方。

## 第二階段：分成兩個版本

照 Android 的做法（GFlyer `AGENTS.md` 的「兩個版本」）。U2、U3、U6 和 U8 2026-10-21 照建議決定。第 8 項、第 10 項和第 11 項已做，見「已做」；第 9 項 2026-10-21 做完（6 步，記錄在「第二階段的做法」）。第二階段 2026-10-21 全部做完。做法的細節在表下面。

| # | 待辦 | 為甚麼和怎樣做 | 做完的標準 |
|---|---|---|---|
| 9 | 把親友版專屬的功能搬進 `Family/` | 和 Android 公開版拿走的相同：留言板（連同地圖工具列的分享）、座標圖鑑（連同前往紀錄、到訪標記、NEW 和資料過時回報）、步數補錄（審查指南 5.1.3 不准寫入不實的健康資料，經使用者的捷徑寫也一樣）、超過 20 km/h 的種花提示。iOS 專屬的兩項：檢查新版和 SideStore 的連結（公開版經 App Store 更新），以及 LocalDevVPN 的交接（公開版改用第 12 項）。飛航模式輔助和它用的捷徑橋接留在共用。一次搬一樣、一個 commit，次序見下面 | 公開版的 App 裏沒有這些畫面和程式；親友版照舊；備份格式不變，公開版把沒有的功能的設定鍵當外來鍵保留、匯出時寫回（DRIFT D1 的做法） |

### 第二階段的做法

**target 和資料夾（第 8 項）**

- `project.yml` 有兩個 App target：`GFlyerIOS`（親友版，target、scheme 和 IPA 的名稱照舊，所以 SideStore 來源和發佈用的 artifact 都不用改）和 `GFlyerPublic`（公開版，bundle id `com.jetpiggy.gflyer`，App 名稱「GFlyer - 飛豬人」）。兩個的 `PRODUCT_MODULE_NAME` 都是 `GFlyerIOS`，共用測試的 `@testable import GFlyerIOS` 兩邊都能用；所以兩個 App 不可以在同一次建置裏一起編，每個 scheme 只建一個。兩個都有 `Idevice` 設定。
- 版本號寫在 `project.yml` 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，兩個版本共用（和 Android 相同），兩個 `Info.plist` 都寫 `$(MARKETING_VERSION)`、`$(CURRENT_PROJECT_VERSION)`。`docs/RELEASE_PROCESS.md` 第 1 步跟着改了。
- 原始碼：共用的是 `GFlyerIOS/`，排除 `Vendor`、`Family`、`Public`；親友版另加 `GFlyerIOS/Family/`，公開版另加 `GFlyerIOS/Public/`。
- 每個版本自己的 `Info.plist` 和 entitlements 放在版本的資料夾。圖放在兩個版本共用的 `GFlyerIOS/Resources/Assets.xcassets`：App 圖示、導覽列的 `GFlyerIcon` 和地圖上選取位置的 `GFlyerMarker` 兩個版本都用 JetPiggy 飛豬（第 11 項）。只有一個版本用的圖才放版本的資料夾，而且不可以和共用的 catalog 同名；兩個版本各放一份一模一樣的圖也不可以（和 Android「同名資源只放在版本資料夾」相同，Android 的匯出工具遇到會停下）。
- 版本介面：共用的 `protocol EditionFeatures`，每個版本的資料夾提供 `enum Edition: EditionFeatures`（照 Android 每個版本的 `object Edition`）。共用程式只經 `Edition` 碰版本專屬的東西：啟動時建立哪些 controller、地圖工具列多的按鈕、設定頁多的 section、回到前景時做的事、`onOpenURL`、備份要保留的外來鍵。公開版的實作是空的。現在這些都直接寫在 `GFlyerIOSApp`、`MainView`、`SetupView` 和 `SimulationController` 四個檔裏，第 9 項每搬一樣就加一個成員。第 8 項加的第一個成員是捷徑和 LocalDevVPN 的回呼 scheme `callbackScheme`：親友版 `gflyer`，公開版 `jetpiggy-gflyer`。兩個 App 都裝了的話，同一個 scheme 會令 iOS 不知道要打開哪一個。第 9 項第 1 步加了 `EditionModelFeatures`：每個版本一個 `EditionModel`（`GFlyerIOSApp` 用 `@StateObject` 建立），提供地圖和設定頁的提示、設定頁多的 section 和回到前景時做的事；公開版的全是空的（照 Android 的 `NoScreenFeatures`）。第 2 步加了地圖工具列的按鈕（`mapToolItems`，接在「座標圖鑑」後面）和 `handleOpenURL`；兩個提示的成員改名為 `mainScreenPresentations`、`settingsPresentations`，因為也放 sheet。地圖工具列改成一串按鈕、兩個一列，所以公開版少了按鈕也不會留空位。第 3 步在 `Edition` 加了 `speedHint`（照 Android 的 `speedHint`），速度控制下面的提示由它給，公開版是 nil。第 5 步加了導覽列「設定」前面的按鈕（`navigationBarButtons`），地圖工具列版本專屬的按鈕改成接在「已儲存路線」後面；`SimulationController` 的留言板方法改成共用的「別處來的座標、路線」（`previewExternalRoute`、`saveExternalCoordinate`、`saveExternalRoute`），留言板的名稱和文字留在親友版的 `SimulationController+MessageBoard.swift`。第 6 步加了 `LocalTunnelFeatures`：每個版本一個 `LocalTunnel`（親友版就是 `LocalDevVPNBridge`，公開版到第 12 項之前什麼都不做），`SimulationController` 開始前開通道、完整清除後關通道，以及設定頁通道 section、「恢復」和「操作順序」裏說到通道的列和文字都經它；查路由改成共用的 `TunnelRoute`，第 12 項的通道也用得到。之後每搬一樣，用得到的就加在這裏。
- 測試：`GFlyerIOSTests/` 兩個版本共用，兩個 test target 都跑；只測親友版功能的測試搬到 `GFlyerIOSTests/Family/`，只在親友版的 test target（第 9 項搬第一個時才在 `project.yml` 加這個資料夾）。測試裏的回呼網址用 `Edition.callbackScheme`，不寫死 `gflyer://`。
- CI：Preview 的測試 job 用 matrix 同時跑兩個 scheme，截圖只截親友版；打包 job 照舊產生親友版的 IPA，之後另外建公開版的 Idevice 未簽署 archive，檢查 bundle id、圖示和沒有私人網址，只上傳內容摘要（artifact `GFlyerPublic-Idevice-summary`），不發佈。
- 「親友版的 IPA 和拆開之前相同」：比對拆開後的檔案清單、`Info.plist`、`Assets.car` 裏的圖名，以及執行檔裏的使用者看得到的字串。`scripts/ipa_summary.py` 產生這份摘要，CI 每次都放進親友版的 artifact（`GFlyerIOS-Idevice-summary.txt`），拿拆開前後兩份 diff。

**搬功能的次序（第 9 項）**：從最獨立的開始，每搬一樣都確認親友版照舊、兩個版本的測試都過，並更新 PARITY 的「iOS 的兩個版本」：

1. 檢查新版和 SideStore 的連結（`AppUpdate`、`AppUpdateChecker`、地圖上的更新提示、設定頁的「軟體更新」）。最獨立，先用它驗證版本介面。**已做**（2026-10-21，`27072b8`；CI run `39514298680` 三個 job 綠燈，親友版 316 個測試、公開版 304 個，各有 1 個依條件略過，編譯警告和之前相同）：`AppUpdate`、`AppUpdateChecker` 和 `AppUpdateTests` 搬到 `Family/`；地圖上的「有新版本」、設定頁的「更新」錯誤提示和「軟體更新」section 搬到 `Family/UI/AppUpdateViews.swift`。設定頁「關於」的版本、Bundle ID 和「聯絡我們」電郵裏的版本改由共用的 `AppVersionInfo` 讀。拆開比對：親友版和 `e713a01` 比只有執行檔不同，`Info.plist`、`Assets.car` 和字串相同；公開版的字串比親友版少 24 條，全是檢查新版和 SideStore 的字（例如「有新版本」「用 SideStore 更新」「軟體更新」），沒有多出的
2. 步數補錄（`StepRecord*`、捷徑回呼 `gflyer://steps/…`）。**已做**（2026-10-21，`7dc579f`；CI run `39518722050` 三個 job 綠燈，親友版 319 個測試、公開版 295 個，各有 1 個依條件略過）：`StepRecordEntry`、`StepRecorderController`、`StepRecorderView` 和 `StepRecorderTests` 搬到 `Family/`；地圖工具列的步行圖示、從地圖和設定頁打開的補錄畫面、一鍵補錄在主畫面的結果和設定頁的「補錄步數」放在 `Family/UI/StepRecorderEntryPoints.swift`，`EditionModelTests` 多了 3 個測試。編譯警告沒有新的，公開版少了補錄那一個。拆開比對：親友版和第 1 步之後比只有執行檔不同；公開版少了補錄的字串（例如「補錄步數」「設定補錄步數」「如何建立捷徑」），沒有多出的。CI 截圖上地圖工具列的排列和之前相同
3. 種花提示（`MainView` 和 `SimulationModels` 裏超過 20 km/h 的提示）。**已做**（2026-10-21，`8309529`；CI run `39519993188` 三個 job 綠燈，親友版 322 個測試、公開版 295 個，各有 1 個依條件略過，編譯警告和之前相同）：照 Android，20 km/h 的上限改成 `Family/Model/FlowerSpeedLimit.swift`，`SpeedScale` 不再有它；共用的 speed fixture 裏種花的那一欄從 `SharedContractTests` 和 `FeatureModelTests` 搬到 `FlowerSpeedLimitTests`。拆開比對：親友版只有執行檔不同；公開版只少了「注意: 超過 20 km/h 將無法種花」一條字串
4. 座標圖鑑（`CoordinateLibrary*`、`CoordinateMarkStore`、`LibraryTeleportHistory`、NEW、資料過時回報）。原本排在留言板後面，2026-10-21 改成先搬：`CoordinateLibraryController` 的資料過時回報用到留言板的 `MessageBoardAPIClient`，留言板卻沒有用到圖鑑。先搬圖鑑，它在 `Family/` 照樣用得到還在共用的 API client，之後 API client 跟留言板一起搬；先搬留言板的話，API client 要先留在共用，等圖鑑搬走再搬一次。地圖工具列上圖鑑排在「分享到留言板」後面，先搬圖鑑也不用改親友版按鈕的次序。**已做**（2026-10-21，`4c062e5`；CI run `39521311660` 三個 job 綠燈，親友版 323 個測試（多了 1 個圖鑑按鈕的測試）、公開版 265 個（圖鑑的 30 個測試搬到親友版，依條件略過的那 1 個也在裏面，所以公開版不再有略過的測試），編譯警告和之前相同）：共用的 `SharedContractTests` 裏前往紀錄、檢查線上版和「NEW」的部分搬到 `Family/CoordinateLibraryContractTests`。拆開比對：親友版只有執行檔不同；公開版只少了圖鑑的字串（包括座標庫的網址），沒有多出字串。地圖工具列和導覽列按鈕的截圖和第 2 步逐像素相同。檔案的搬移（`git mv`）誤進了前一個只改文件的 commit `f801765`，所以單獨 checkout `f801765` 時公開版編譯不過，`f801765` 和 `4c062e5` 合起來才是這一步；兩個都已推上去，沒有改寫歷史
5. 留言板（`MessageBoard*`、`MessageBoardAPIClient`、地圖工具列的分享、未讀數）。**已做**（2026-10-21，`7eafee1`；CI run `39522776195` 三個 job 綠燈，親友版 324 個測試（多了 1 個「分享到留言板」按鈕的測試）、公開版 249 個（留言板的 16 個測試搬到親友版），編譯警告和之前相同）：`MessageBoardModels`、`MessageBoardAPIClient`、`MessageBoardController`、`MessageBoardSessionStore`、`MessageBoardViews`、`MessageBoardTests` 和 `BoardCounterTests` 搬到 `Family/`；導覽列的留言板按鈕連同未讀數、兩個留言板畫面和「分享到留言板」放在 `Family/UI/MessageBoardEntryPoints.swift`；`SharedContractTests` 裏留言板字數的部分搬到 `Family/MessageBoardContractTests`。拆開比對：親友版除了執行檔，只有一條字串不同：「請先停止目前的定位模擬，再使用留言板路線。」改由共用的「請先停止目前的定位模擬，再使用」、「留言板」和「路線。」接起來，畫面上的字相同；公開版少了留言板的字串，多出的只有「路線。」，是公開版不會顯示的那句的一段。導覽列和地圖工具列的截圖和第 2 步逐像素相同。還沒處理：設定頁備份的兩句說明（「…留言板登入與 Pairing File 不受影響。」、「…留言板登入與 Pairing File 不會包含在備份內。」）公開版也顯示，公開版沒有留言板，第 10 項之前要改由版本給（第 10 項改了，`ae9aefc`）
6. LocalDevVPN 的交接（`LocalDevVPNBridge`、設定頁的 LocalDevVPN section、`SimulationController` 的通道檢查）。之後到第 12 項做好之前，公開版能編譯、不能傳送。**已做**（2026-10-21，`89d8f98`；CI run `39524306005` 三個 job 綠燈，親友版 327 個測試（多了 3 個 `LocalTunnelFeatures` 的測試）、公開版 240 個（`LocalDevVPNBridgeTests` 的 9 個搬到親友版，查路由的 2 個改成共用的 `TunnelRouteTests`），編譯警告和之前相同）：`LocalDevVPNBridge` 和它的測試搬到 `Family/`；設定頁的開關、狀態和「按開始時自動開啟」、「恢復」的「清除後同時關閉 LocalDevVPN」放在 `Family/UI/LocalDevVPNSettings.swift`，設定頁的手動開關放在 `Family/Services/SimulationController+LocalDevVPN.swift`。公開版的通道 section 叫「本機通道」，只有目標 IP 和測試通道；「操作順序」第 3 步是「回到地圖選點並按開始。」——這幾句是暫時的，第 14 項的引導會重寫。公開版不會代使用者開通道，有沒有別的 VPN 已經把目標 IP 導回手機時還能不能傳送，沒有在實機試過。拆開比對：親友版除了執行檔，只有一條字串不同：「\nLocalDevVPN 已關閉。」的換行改由共用的程式接上，畫面上的字相同；公開版的 `Info.plist` 拿走了 `localdevvpn`，`NSLocalNetworkUsageDescription` 不再提 LocalDevVPN，字串少了交接的部分、多了上面幾句公開版的說明。主畫面的截圖和第 2 步相同（深色的工具列有一小塊差一個色階，是繪製的誤差）。公開版的執行檔還有 5 條提到 LocalDevVPN 的字串（CoreDevice 的錯誤說明、「LocalDevVPN 目標 IP 無效。」、「LocalDevVPN/CoreDevice 通道已驗證」），和第 5 步記下的兩句備份說明，留給第 10 項（`ae9aefc` 改了）。備份：iOS 的備份只有收藏、歷史、資料夾、路線、速度預設和兩個共用的設定，搬走的 6 樣都沒有寫進備份；不認識的設定鍵由共用的 `AppBackupCodec` 原樣保留，`testBackupPreservesForeignSettingsAcrossRoundTrip` 兩個版本的 test target 都跑，所以沒有另加「親友版的備份經公開版匯入再匯出」的測試

公開版的 `Info.plist` 沒有 `GFlyerMessageBoardAPIURL`、`GFlyerCoordinateLibraryURL`、`GFlyerUpdateSourceURL`，`LSApplicationQueriesSchemes` 也沒有 sidestore、altstore；localdevvpn 在第 9 項第 6 步（`89d8f98`）搬走 LocalDevVPN 的交接時拿走了。備份另加一個測試：親友版的備份經公開版匯入再匯出，鍵和值不變。

**這一階段不發新版。** 親友版在每一項之後都應該和之前相同，所以不用為它發佈；有其他改動要發時照常發。

## 第三階段：公開版才有的

第 12 項的程式 2026-10-21 做完（`190bf0d`），還沒有在實機試，見表下面的「第 12 項的進度」。第 14 項（首次設定的引導）的程式 2026-10-29 做完（`465bfc0`），還沒有在實機試，見「第 14 項的進度」。第 15 項的程式也做完（`8b46c61`），送審說明的 DDI 一段已起草，見「第 15 項的進度」。第 16 項的程式 2026-10-22 做完（`7c0a05c`），兩個版本都有，還沒有在實機試，見「第 16 項的進度」。第 17 項的程式也做完（`ec093a6`），公開版改用 Apple 的地點服務，不連 Nominatim，還沒有在實機試，見「第 17 項的進度」。第 18 項的程式也做完（`0e2d8ca`），兩個版本都有，見「第 18 項的進度」。第 19 項的正本和 App 內的入口也做完（`6b510f5`），網頁送審之前才放上去，見「第 19 項的進度」。第 20 項的私隱清單也做完（`bbe77ee`），App Store Connect 問卷的答案使用者已確認，有帳戶才填得到，見「第 20 項的進度」。第 21 項的加密申報也核對完（`6268304`），`Info.plist` 照舊寫「不用申報」，前提是不在法國上架（U9，使用者 2026-10-22 決定首版不上），見「第 21 項的進度」。

| # | 待辦 | 為甚麼和怎樣做 | 做完的標準 |
|---|---|---|---|
| 12 | App 內建的本機通道（Network Extension） | 審查指南 4.2.3 要求 App 不用另外安裝別的 App 就能運作。LocalDevVPN 雖然也上架了 App Store，公開版不可以要求使用者另外裝。做法：Packet Tunnel extension，只路由 `10.7.0.1` 這一個位址，把封包反射回手機本身。原理和 LocalDevVPN 相同，但程式自己寫，因為 LocalDevVPN 沒有標明授權。App 用 `NETunnelProviderManager` 開關；目標 IP 寫在通道設定的 `providerConfiguration`，不用 App Group；飛航模式輔助照舊。免費 Apple ID 不能簽 Network Extension，所以只有公開版有，親友版照舊用 LocalDevVPN | 沒有裝 LocalDevVPN 的 iPhone 用公開版建立通道並傳送；Wi-Fi 和行動網路（飛航模式流程）都試過；關掉通道後一般上網不受影響 |
| 13 | 「顯示開發者模式」 | 從 App Store 安裝的 App 不會讓開關出現。Apple 的文件說開始配對時開關才會出現，LL Pair 也有「顯示開發者模式」。推測做法是先開始廣播配對主機；LL Pair 沒有公開程式，要先實機確認 | 一支從沒接過電腦的 iOS 27 iPhone，從 TestFlight 安裝後能叫出開關 |
| 14 | 第一次設定的引導 | 一步一個畫面，文字照實機畫面寫：① 顯示開發者模式 ② 開啟開發者模式並重新開機 ③ 在手機上配對 ④ 建立本機通道 ⑤ 下載 DDI ⑥ 傳送一次並到 Apple 地圖確認 ⑦ 清除並恢復真實位置。iOS 26 以下的第 ③ 步改成匯入電腦產生的配對檔 | 沒看過說明的人照畫面能完成。程式 2026-10-29 做完（`465bfc0`），還沒有在實機試，見「第 14 項的進度」 |
| 15 | DDI 下載的說明 | 現在從第三方的 GitHub repo（`doronz88/DeveloperDiskImage`）下載 Apple 的映像，並核對 SHA-256。審查指南 4.2.3 要求第一次啟動要下載的資源先說明大小並詢問；2.5.2 不准下載會改變 App 功能的程式碼，DDI 是給 iOS 掛載的開發者映像，送審說明要寫清楚 | 下載前顯示大小並等使用者同意；送審說明寫明用途和來源 |
| 16 | 定位檢查頁（DRIFT D31） | 給審查員和使用者核對模擬有沒有生效、清除後有沒有恢復；Android 也是為審查做的。先在 GFlyer-Suite 寫 `docs/features/` 的規格，文字照 Android。用 `CLLocation.sourceInformation` 分辨模擬位置，要上機確認 | 規格寫好、兩邊文字一致，實機驗證 |
| 17 | 地名反查改用系統服務（DRIFT D33） | 公開的 Nominatim 只准全部用戶合計每秒一次，上了 App Store 一定超過。改用 `CLGeocoder`，照 `region-labels.md` 3.5a 和同一份 fixture；同意照 U7 | 公開版不連 Nominatim |
| 18 | 開放原始碼授權頁（DRIFT D34） | App Store 的使用者看不到 repo，散佈 idevice 和它連結的 Rust 程式庫要附上授權。清單從 Cargo.lock 產生；入口和頁名照 Android | 兩個版本都有，清單和實際打包的相符 |
| 19 | 私隱政策 | 審查指南 5.1.1 要求所有 App 在 App Store Connect 填私隱政策網址，App 內也要有入口。Android 的正本只寫 Android 公開版，要另寫 iOS 版：配對檔和通道只在手機上處理、DDI 從哪裏下載、掛載 DDI 時向 Apple 的簽署伺服器送出這部 iPhone 的晶片識別碼（見「第 15 項的進度」）、地名服務、聯絡電郵、資料保存多久和怎樣刪除。網址由使用者決定，例如和 Android 同一個網站 | 頁面公開，不用登入就看得到；App 內有「私隱政策」；內容和 App 的實際做法一致 |
| 20 | 私隱資訊清單和 App 私隱標籤 | App Store 要求 `PrivacyInfo.xcprivacy` 宣告用到的指定原因 API（例如 `UserDefaults`、檔案時間）；App Store Connect 的資料收集問卷照實填。Claude 按程式的實際做法起草，使用者確認 | 上傳時沒有私隱清單的警告；問卷已提交 |
| 21 | 加密的出口申報 | 配對和通道用 SRP、TLS-PSK 等標準加密。`Info.plist` 的 `ITSAppUsesNonExemptEncryption` 和 App Store Connect 的問題照實回答。Claude 起草，使用者確認 | 每次上傳不用再手動回答 |

### 第 12 項的進度

程式 2026-10-21 做完（`190bf0d`；CI run `39584119587` 四個 job 綠燈，親友版 327 個測試，公開版 257 個（多了 7 個 `PacketReflectorTests` 和 10 個 `LocalTunnelTests`），編譯警告和之前相同），**還沒有在實機試**：免費 Apple ID 簽不了 Network Extension，要等付費開發者帳戶（U1、第 22 項）。

- 通道 extension `GFlyerPublicTunnel`（`com.jetpiggy.gflyer.tunnel`）放在公開版 App 的 `PlugIns/`。它只把目標 IP 這一個位址（/32）的路由導進通道，沒有 DNS 設定。通道介面的位址是 `10.7.0.2`（目標 IP 是 `10.7.0.2` 時改用 `10.7.0.3`），`tunnelRemoteAddress` 也用它。送往目標 IP 的 IPv4 封包對調來源和目的位址後寫回去（`GFlyerIOS/Public/Tunnel/PacketReflector.swift`，App 和 extension 都編進去），iPhone 就把它當成目標 IP 連進來的連線；對調不用重算 checksum，其他封包丟掉。這些位址是自己定的，沒有參考 LocalDevVPN 的程式。
- 目標 IP 由 App 寫在通道設定的 `providerConfiguration`，從 iOS 的 VPN 設定直接開啟也讀得到，所以不用 App Group。目標 IP 改了，下次開通道時更新設定，開着的先關再開。
- App 端（`GFlyerIOS/Public/LocalTunnel.swift`、`Tunnel/SystemTunnel.swift`）：按開始時通道沒開就先開，等到送往目標 IP 的路由經過通道才開始，最多等 10 秒。不用切去別的 App，所以沒有親友版的「按開始時自動開啟」開關。設定頁「本機通道」有通道狀態和「開啟本機通道」／「關閉本機通道」；「恢復」有「清除後同時關閉本機通道」（預設關）。iOS 的 VPN 設定裏的名稱是「GFlyer 本機通道」。
- 第一次開啟時 iOS 會問可否加入 VPN 設定。App 裏只寫「iOS 會詢問可否加入 VPN 設定，要允許才能使用」，沒有寫按鈕的名稱：香港繁體中文的畫面還沒有人看過，第 14 項照實機截圖重寫。
- CI 檢查公開版 App 裏有這個 extension，bundle id、extension 類型對，版本號和 App 相同；`--app` 掃描連 extension 一起掃。
- 拆開比對：親友版的 IPA 和第 10 項之後完全相同，連執行檔；公開版多了 `PlugIns/GFlyerPublicTunnel.appex`，字串多了上面通道的說明。
- 實機要試的（做完的標準）：沒有裝 LocalDevVPN 的 iPhone 第一次開通道（iOS 的詢問）和傳送；Wi-Fi 和行動網絡（飛航模式流程）；關掉通道後一般上網；在 iOS 的 VPN 設定直接開關；改了目標 IP 之後重開。

### 第 14 項的進度

程式 2026-10-29 做完（`465bfc0`；CI run `40765114958` 綠燈，親友版 364 個測試（多了 1 個，核對「操作順序」一字不改），公開版 304 個（多了 9 個 `FirstSetupGuideTests` 和 1 個 `PublicEditionTests`，少了 `LocalTunnelTests` 裏舊的「操作順序」那 1 個），編譯警告和之前相同），**還沒有在實機試**：公開版要付費開發者帳戶才裝得到 iPhone（第 22 項），做完的標準「沒看過說明的人照畫面能完成」要等 TestFlight（第 24 項）。

- 只有公開版有。第一次打開 App 時自己打開（預覽模式和 CI 截圖時不打開），蓋在主畫面上；第 2 步重新開機之後再打開 GFlyer，回到同一步。按「關閉」、把畫面往下拉或做完按「完成」之後不再自己打開，要從設定頁「首次設定」最上面的「一步一步設定」打開，從關掉時那一步接着做。
- 一步一個畫面，次序照這一項：①「顯示開發者模式」②「開啟開發者模式並重新開機」③「在這支 iPhone 上配對」（iOS 26 以下是「匯入 Pairing File」）④「開啟本機通道」⑤「下載 DDI」⑥「傳送一次並確認」⑦「清除並恢復真實位置」。每一步用設定頁的同一組按鈕和狀態，所以字和設定頁相同：配對的幾列從設定頁搬到共用的 `OnDevicePairingRows`，通道和 DDI 用設定頁那兩組列；第 ⑥、⑦ 步推進定位檢查頁，用它的「傳送到選取的位置」和結論確認，第 ⑦ 步的「完整清除模擬定位」和設定頁「恢復」的相同。說明裏引號中的 GFlyer 按鈕、狀態和結論都用畫面上的同一個常數，測試核對。
- App 查得到結果的三步（配對、通道、DDI）要做完才按得到「下一步」，下面寫明要等甚麼；開發者模式、傳送和清除查不到，由使用者自己看。
- 第 ① 步的「顯示開發者模式」和「在這支 iPhone 上配對」是同一個動作（開始等待配對），照第 13 項推測的做法；第 13 項還沒有實機確認。按了之後還是找不到「開發者模式」的話，說明叫使用者經「聯絡我們」告訴我們。
- 設定頁「操作順序」改由 `Edition.usageSteps` 給：親友版的四步一字不改；公開版不再叫人用電腦產生 Pairing File，改成「1. 第一次使用時，按「首次設定」的「一步一步設定」，照着做完。」和原來的第 4 步。
- 版本介面多了兩樣：設定頁「首次設定」最上面版本專屬的列（`EditionModelFeatures.firstSetupRows`），以及 `settingsPresentations` 多傳 `SimulationController`（引導要用它）。親友版兩樣都是空的。
- iPhone 畫面上的名稱照「iOS 27 實機畫面」（香港繁體中文）。還沒有人看過的畫面不寫按鈕的名稱，上 TestFlight 時要截圖：
  1. 開發者模式還沒開時，「設定」>「私隱與保安」是否在按了「顯示開發者模式」之後才出現「開發者模式」（第 13 項）。
  2. 打開「開發者模式」的開關之後的提示、重新開機，和解鎖後再問一次的確認。說明現在寫「照 iPhone 的提示重新開機」「選開啟，再輸入 iPhone 的密碼」。
  3. 第一次開啟本機通道時，iOS 詢問可否加入 VPN 設定（第 12 項）。
  4. 定位檢查頁按「允許定位權限」之後 iOS 的定位權限詢問。
  5. 第 ⑥ 步說「也可以打開 iPhone 的「地圖」App，看藍點是不是在選取的位置」：iPhone 主畫面上這個 App 的名稱和藍點都要對過。
- iOS 26 以下用的電腦工具：使用者 2026-10-29 決定用 idevice_pair，不放網址。
  - 理由：它經 USB 產生的是 GFlyer 讀的 remote pairing（RPPairing）配對檔（`rp_pairing_file_read`），要 iOS 17.4 以上，和公開版的最低版本相同；作者也寫 idevice。Mac 和 Windows 都有現成的安裝檔（v1.1.0，2026-08-17：`idevice_pair--windows-x86_64.exe` 約 40 MB、`idevice_pair--macos-universal.dmg` 約 58 MB）。免費，README 寫 MIT 授權（repo 裏沒有授權檔），不用登入 Apple ID，也不在 iPhone 上安裝東西。LocationLab 的支援頁也把它列為產生配對檔的備用工具。
  - 不放網址：App 的字會出現在公開 repo，idevice_pair 在 GitHub 的個人帳戶下，品牌規則第 5 節不准連過去。說明只寫工具名和要下載哪個檔（Windows 的檔名有 `windows-x86_64`，Mac 的是 `.dmg`），使用者自己搜尋。在 idevice_pair 裏要揀 remote pairing，不是 lockdown，寫步驟時照它的畫面。
  - 沒有採用的：
    - iloader：要登入 Apple ID、會安裝 SideStore，等於叫 App Store 的使用者走親友版的安裝途徑（見「定位」）。
    - Xcode：只有 Mac，下載很大，也產生不到 GFlyer 能匯入的配對檔；只當 Mac 叫出開發者模式的後備。
    - pymobiledevice3、idevice 的命令列工具：對一般使用者太技術。
    - 像 LocationLab 一樣自己做電腦工具：等於多做一個產品；iOS 27 才是主要的路。
  - 還沒確認：idevice_pair 只讀開發者模式有沒有開，沒有叫出開關的功能（v1.1.0 的 `src/backend/link.rs`）。Apple 的文件（Enabling Developer Mode on a device）寫，開始配對或之前和 Mac 配對過，「設定」才顯示開發者模式；idevice_pair 經 USB 做的是同一種配對，推測配對之後開關會出現。要用一支從沒開過開發者模式的 iOS 26 iPhone 試：
    - 會出現：Mac 和 Windows 都只用 idevice_pair。
    - 不會出現：Mac 改用 Xcode 叫出開關；Windows 沒有乾淨的做法，App 裏主要叫人升級到 iOS 27。
  - App 裏 iOS 26 以下的第 ①、③ 步現在只寫「用電腦」。要等有了 idevice_pair（Windows 和 Mac）和那支 iPhone 的截圖，才照畫面寫出工具名和步驟。
- 拆開比對（和第 28 項的 run `39717230770` 比）：親友版的 IPA 只有執行檔不同，字串相同。公開版的字串少了舊的「操作順序」四句（「1. 用電腦產生這部 iPhone 的 pairing file。」等，現在只有親友版有），多了引導的字。建好的公開版 App 掃描照舊 45 個提醒。匯出 122 個檔案（多了新加的 4 個），提醒 202 處（多的 7 處都是註解提到 `docs/APP_STORE_PLAN.md`）。

### 第 15 項的進度

程式 2026-10-21 做完（`8b46c61`；CI run `39623879142` 的第二次四個 job 綠燈（第一次三個 macOS job 等不到 GitHub 的 runner，被取消），親友版 331 個測試，公開版 266 個（兩邊都多了 3 個 `DeveloperDiskImageStoreTests`；公開版另外多了 6 個 `DeveloperDiskImageDownloadTests`，親友版 1 個 `FamilyEditionTests`），編譯警告和之前相同），**還沒有在實機試**：公開版要付費開發者帳戶才裝得到 iPhone（第 22 項）。

- 公開版不會自己下載 DDI。設定頁（「裝置設定」）的「Developer Disk Image」有「DDI 狀態」（檢查中…／未下載／下載中…／已下載）和「下載 DDI（約 16.5 MB）」，按了才下載；說明寫明從 GitHub 下載固定版本、經 SHA-256 驗證、保留在本機。大小由三個檔案的大小加起來（`DeveloperDiskImageStore.downloadSizeText`，16,536,648 bytes，1 MB = 1,000,000 bytes，和 iOS 顯示的相同），改了 revision 要一起改。
- 還沒下載，iPhone 這次開機後也還沒掛載過 DDI 時按開始或「測試本機通道」，連線到要掛載 DDI 那一步會停下來（iPhone 已經掛載了就不用 DDI 的檔案，照常連線），顯示「還沒有下載 DDI。請到設定頁的「Developer Disk Image」按「下載 DDI（約 16.5 MB）」，完成後再試。」，不會下載（`Edition.developerDiskImageMissingMessage`）。下載失敗顯示「DDI 下載失敗：」加原因，按鈕可以再按。離開設定頁下載會繼續，回來時看到「下載中…」。
- 親友版照舊：第一次掛載時自己下載，設定頁的說明一字不改。拆開比對（和第 12 項的 run 比）：親友版的 IPA 只有執行檔不同（大 11,976 bytes），字串相同；公開版的字串少了親友版那句 DDI 說明，多了上面的狀態、按鈕和說明；建好的公開版 App 掃描照舊 45 個提醒。
- 掛載時 iPhone 如果沒有這個映像的個人化票據，idevice 會向 Apple 的簽署伺服器 `http://gs.apple.com/TSS/controller` 要一張（`3854a5d` 的 `idevice/src/tss.rs`），請求裏有這部 iPhone 的 BoardId、ChipID、ECID 和 nonce；Xcode 掛載時也一樣。這不經 `URLSession`，所以不受 App Transport Security 管。私隱政策（第 19 項）要寫。
- 實機要試的：新裝的公開版，iPhone 重新開機後未下載時按開始會停在上面那句；按下載後狀態變成「已下載」，再按開始能掛載並傳送；飛航模式下按下載會顯示失敗，按鈕可以再按。

送審說明的 DDI 一段（第 26 項用；按鈕和設定頁的名稱照 App 裏的字，送審前照 TestFlight 的畫面再核對一次）：

> **Developer Disk Image (DDI).** To simulate a location, iOS must first mount Apple's Personalized Developer Disk Image, the same image Xcode mounts when a developer runs an app on a device. GFlyer never downloads it by itself: the settings screen (裝置設定, gear button on the map) has a "Developer Disk Image" section that shows the status and a button "下載 DDI（約 16.5 MB）" ("Download DDI, about 16.5 MB"). Nothing is downloaded until the user taps it; if the user starts a simulation before that and iOS has not mounted the image yet, GFlyer stops and points to that button. The three files (`Image.dmg`, `Image.dmg.trustcache`, `BuildManifest.plist`, 16.5 MB in total) are Apple's files from Xcode, downloaded from the public GitHub repository `doronz88/DeveloperDiskImage` at a fixed revision. GFlyer checks each file against a SHA-256 hash built into the app and keeps them on the device. iOS itself mounts the image, and only with a personalization ticket from Apple's signing server (`gs.apple.com`), which GFlyer requests the same way Xcode does. The DDI is not code that GFlyer runs and it does not add or change any GFlyer feature (guideline 2.5.2); it provides the developer services that iOS uses for location simulation.

### 第 16 項的進度

程式 2026-10-22 做完（`7c0a05c`；CI run `39660389201` 四個 job 綠燈，親友版 342 個測試，公開版 277 個，兩邊都多了 11 個 `LocationCheckTests`，編譯警告和之前相同），**還沒有在實機試**。規格先寫在 GFlyer-Suite 的 `docs/features/location-check.md`，fixture `contracts/fixtures/location-check/verdict-and-text.json`（Suite `eafe172`），都照 Android 的 `model/LocationCheck.kt` 和 `ui/LocationCheckPage.kt`。

- 兩個版本都有，和 Android 一樣，都在共用的程式裏（`GFlyerIOS/Model/LocationCheck.swift`、`Services/LocationCheckReader.swift`、`UI/LocationCheckView.swift`）。入口在設定頁「目前位置與背景路線」的「定位檢查」，推進一頁；只在裝置版出現，和「恢復」一樣。
- 頁面照 Android：說明、「本 App 正在推送」、「其他 App 收到的位置」五列（座標、精度、時間、來源、和推送的位置相距）、結論的卡片、「傳送到選取的位置」和「停止模擬」。結論的文字和 Android 一字不差；兩句說明是 iOS 的寫法：停止後仍是模擬位置時指到「完整清除模擬定位」，模擬中收不到推送的位置時叫使用者按「停止模擬」再傳送一次。Android 的「模擬位置應用程式」那一列 iOS 沒有。
- 位置用這一頁自己的 `CLLocationManager` 讀，只在頁面開著、App 在前景時讀，不儲存、不傳送；「來源」是 `isSimulatedBySoftware`。沒有權限時卡片有「允許定位權限」：還沒問過就跳系統的詢問，拒絕過就開 iOS 設定。
- 「傳送到選取的位置」：地圖是「定點傳送」時照按開始；別的模式沒有在模擬時先切到「定點傳送」（路線清掉）；別的模式而且在模擬中，顯示「請先停止目前的定位模擬，再傳送到選取的位置。」。Android 直接改成定點，iOS 不行，因為 `status.mode` 跟着地圖的模式（規格第 7 節）。跨日時區提醒在這一頁跳出。
- 「和推送的位置相距」的公里照十進位四捨五入（1,250 公尺是 1.3 公里），和 Android 的 `String.format` 相同。
- 拆開比對（和第 15 項的 run 比）：兩個版本都只有執行檔不同，多的字串是這一頁的字，兩邊相同；建好的公開版 App 掃描照舊 45 個提醒。
- 實機要試的（規格第 6 節）：模擬中結論是「其他 App 收到的就是本 App 推送的位置」（也就是經 DDI 模擬的位置 `isSimulatedBySoftware` 是 true）；一般停止後的結論；「完整清除模擬定位」之後是「現在沒有模擬，收到的是手機的真實位置」；路線播放中；沒有權限時的「允許定位權限」。親友版經 SideStore 安裝就可以試，不用等付費帳戶；要發佈才裝得到。

### 第 17 項的進度

程式 2026-10-22 做完（`ec093a6`；CI run `39672264473` 四個 job 綠燈，親友版 357 個測試，公開版 289 個：兩邊都多了 13 個 `RegionLookupConsentTests`；Nominatim 的 3 個 fixture 測試從共用的 `RegionLabelTests` 搬到只有親友版跑的 `NominatimRegionLabelTests`，親友版另外多了 2 個；公開版多了 2 個 `AppleGeocoderRegionLabelTests`；編譯警告和之前相同），**還沒有在實機試**：公開版要付費開發者帳戶才裝得到（第 22 項）。照 GFlyer-Suite `docs/features/region-labels.md` 3.5a 和 3.10。U7 照建議做（先問，文字照 Android 公開版），使用者 2026-10-22 決定照建議。

- 佇列、快取和顯示照舊是共用的 `RegionLookup`：一次一筆、每筆之後隔 1.1 秒、快取在 `gflyer.region-labels.v1`、查失敗到下次開 App 才再查。查哪個服務由 `Edition.makeRegionLabelSource()` 決定。Nominatim 的請求和解析搬到 `GFlyerIOS/Family/Services/NominatimRegionLabels.swift`，只編進親友版；親友版的行為不變，也不問。
- 公開版用 `CLGeocoder` 的 `reverseGeocodeLocation`，語言固定 `zh_TW`（`GFlyerIOS/Public/Services/AppleGeocoderRegionLabels.swift`）。標籤照 3.5a：國家加城市，城市用 `locality`、`subAdministrativeArea`、`administrativeArea` 裏第一個不是空白的；城市和國家相同就只寫國家。`AppleGeocoderRegionLabelTests` 照抄 Suite 的 `contracts/fixtures/region/platform-geocoder-labels.json`（13 個例子，Android 公開版的 `PlatformGeocoderTextTest` 讀同一份）。
- 同意照 Android 公開版：要查之前先問「顯示收藏的國家與城市？」，按鈕「不用」「允許」，兩段說明和 Android 一字不差，服務名稱是「Apple 的地點服務」。開 App 時有收藏要查而還沒問過就問；按 ☆ 時還沒問過，先問再開「收藏位置」。還沒允許時不送、不顯示本機快取裏的地名，「收藏位置」也不預填名稱。答案存在 `gflyer.region-lookup-consent.v1`，不放進備份檔。按「不用」之後收藏變動也不再問。
- 公開版的設定頁多了「提示與地名」：「跨日時區提示」從「路線播放」搬過來，加上「顯示收藏的國家與城市」和「收藏的座標會送往 Apple 的地點服務查詢」。打開時先跳出同一個詢問，按「允許」才打開；關掉馬上生效，還在排隊的拿掉。親友版的設定頁不變。
- `scripts/check_public_sources.py` 多了一條（共 29 條）：公開版的原始碼和建好的 App 不可以有 `nominatim.openstreetmap.org`。
- 拆開比對（和第 16 項的 run 比）：兩個版本都只有執行檔不同，版本照舊 0.6.17 (30)。兩邊的字串都多了詢問的說明、按鈕和「提示與地名」（共用的程式，親友版不會顯示）；公開版另外多了「Apple 的地點服務」。建好的公開版 App 掃描照舊 45 個提醒；親友版的執行檔裏照舊有 Nominatim 的位址。
- 實機要試的：新裝的公開版按 ☆，先問再出現「收藏位置」，按「允許」後照常預填名稱，按「不用」不預填、清單不顯示國家與城市；已有收藏時開 App 就問；回答過之後重開不再問；「提示與地名」的開關；Apple 回的地名和 fixture 的層級是否一致（例如臺北、香港、新加坡）；收藏很多時 Apple 的頻率限制。親友版的反查程式搬了位置，下次發佈後確認收藏的國家與城市照常出現。

### 第 18 項的進度

程式 2026-10-22 做完（`0e2d8ca`；CI run `39677137567` 五個 job 綠燈，親友版 362 個測試，公開版 294 個，兩邊都多了 5 個 `OpenSourceLicensesTests`，編譯警告和之前相同），**還沒有在實機看過**。D34 寫明 iOS 的做法自己決定，所以沒有共用規格；頁面照 Android 的 `ui/OpenSourceLicensesPage.kt`。

- 入口在設定頁「關於」的最後一列「開放原始碼授權」，底下一行「App 用到的程式庫的授權」。Android 放在設定「系統」的最後一項，和版本、聯絡我們同一組；iOS 的那一組就是「關於」。兩個版本都有。
- 頁面照 Android：說明「這個 App 用到下列開放原始碼程式庫。點一項可以看授權全文。」、「程式庫（140）」，每一列是名稱、版本和授權；點一列推進全文頁，最上面是版本和授權，每一份全文一段，用等寬字，可以選取。讀不到時是「讀不到授權清單」「讀不到授權全文」，和 Android 相同。
- 和 Android 不同的字：入口底下那一行和說明只寫「程式庫」，Android 是「程式庫和圖示」「程式庫和素材」。iOS 沒有第三方的圖示（SF Symbols 和 JetPiggy 自己的飛豬），所以也沒有「圖示」那一段；Android 從 AAR 抽出的「程式庫內含的開放原始碼」iOS 也沒有。
- 清單 `GFlyerIOS/Resources/OpenSourceLicenses.json`（約 428 KB）由 `scripts/open_source_licenses.py` 產生，不手改：用 `build_idevice.sh` 的 package、target 和 features（從腳本讀，不會不同步）跑 `cargo tree`，只算一般的依賴（build script 和 proc macro 只在建置時執行，沒有編進 App），得到 139 個 Rust 套件，加上 Rust 標準程式庫。授權是 Cargo.toml 的 license，全文是套件附的 LICENSE、COPYING、NOTICE 等檔案，相同的全文只放一份（118 份）。
- 自動做不到的三個寫在腳本的 `OVERRIDES`：`idevice-ffi` 的 Cargo.toml 沒寫 license（用 repo 的 MIT）；`plist-macro` 和 `plist_ffi` 寫了 MIT，但套件和上游 repo 都沒有授權檔，用 MIT 的標準全文配上 Cargo.toml 寫的作者（Jackson Coxson）。沒有附全文、授權又可以選 Apache-2.0 的（`ns-keyed-archive`、Rust 標準程式庫）用 Apache-2.0 的全文。
- CI 新的「Open source licences」job（Linux，不建置）下載釘住的 idevice，重新產生清單和提交的比對，不同就失敗並上傳產生的清單。改 `build_idevice.sh` 的 revision 或 features 時，同一次改動用 `--write` 重新產生（`AGENTS.md`）。
- 授權全文裏有第三方版權人的名字和電郵（例如 Michael Wright、兩個 gmail.com 的地址），會撞到公開版掃描的「個人姓名」「私人電郵」。`scripts/check_public_sources.py` 只在這個檔、只放行這幾段字（`NOTICES_ALLOWED`），原始碼和建好的 App 都一樣；清單換了內容又撞到時，確認是第三方的版權人才加。
- 實機要看的：設定頁「關於」的入口；清單捲得順、140 個都在；打開 `ring` 這種有三份全文的，段落和框線照原樣；深色模式看得清楚。

### 第 19 項的進度

正本和 App 內的入口 2026-10-22 做完（`6b510f5`；CI run `39685853297` 五個 job 綠燈，親友版 363 個測試，公開版 295 個，親友版多了 1 個 `FamilyEditionTests`，公開版多了新的 `PublicEditionTests`；編譯警告和之前相同。第一次跑時親友版的 `CoordinateLibraryTests.testLastCheckedAtRecordsOnlySuccessfulDownloads` 失敗：它最多等 2 秒讓下載完成，runner 慢的時候等不到，和這次的改動無關，重跑通過），**網頁還沒有放上去**，所以做完的標準裏的「頁面公開」還沒有達到。

- 使用者 2026-10-22 決定：U7 照建議（先問）；網址是 `https://gflyer.jetpiggy.com/ios/privacy.html`，英文 `/en/ios/privacy.html`；正本現在寫，送審之前（第 25 項）才放上網站，因為 JetPiggy RULES 第 5 節只准寫已推出或已公開的功能，而且這一節不可以放寬。
- 正本 `docs/privacy-policy.md`，中英文，結構和用字照 Android 公開版的正本（GFlyer `docs/privacy-policy.md`），iOS 做法不同的地方逐項改寫，每一句的根據寫在正本開頭。和 Android 不同的主要是：存在 iPhone 上的多了最後一次的真實位置、Pairing File 和 DDI；iPhone 的 iCloud 備份和電腦備份會包括這些資料，只有 DDI 排除在外（Android 寫的是不經雲端備份）；多了「Pairing File、本機通道和 DDI」一節，寫配對時在本機網絡公告甚麼、通道只導入目標 IP、DDI 從 GitHub 下載，以及掛載時向 `gs.apple.com` 送出 ECID 等（經 HTTP，沒有加密）；連線到的服務只有 Apple（地圖、搜尋、國家與城市、簽署伺服器）和 GitHub；iOS 不讀剪貼簿。
- RULES 第 5 節不准網站連去個人帳戶下的 repo，所以正本只寫「GitHub 上一個公開的 repo」，不寫 DDI repo 的名稱。
- App 內：公開版設定頁「關於」在「聯絡我們」下面多了「私隱政策」，用 Safari 打開中文頁（`Edition.privacyPolicyURL`）。Android 的「私隱政策」鈕在「隱私與使用範圍」的說明裏；iOS 沒有那個說明，所以放在「關於」。親友版沒有這一列（Android 親友版也沒有）。網頁放上去之前按了會打不開；公開版要付費帳戶才裝得到，所以沒有人會按到。
- 拆開比對：兩個 IPA 都只有執行檔不同，字串各多了「私隱政策」一條；親友版的網址是 nil，畫面上沒有這一列。建好的公開版 App 掃描照舊 45 個提醒。
- 寫正本時發現：Pairing File 存在 Application Support，沒有排除在 iPhone 的 iCloud 備份和電腦備份之外（只有 DDI 排除了）。`PairingFileStore` 兩個版本共用，親友版已經上機驗證過，所以正本照實寫，程式沒有改。使用者 2026-10-22 決定不排除，照舊跟着 iPhone 的備份（正本已經這樣寫）。
- 放上網站的步驟（送審之前）：一、把正本兩種語言的「生效日期」改成那一天，commit；二、在 `JetPiggy` repo 開新 session，交接附上正本「中文」和「English」兩節的全文（網站 session 不讀這個 repo），照 Android 那兩頁的外觀做成 `/ios/privacy.html` 和 `/en/ios/privacy.html`；三、照 RULES 第 5 節把要公開的內容列給使用者確認，部署等使用者明確要求；四、實機按「私隱政策」確認打得開；五、App Store Connect 的私隱政策網址（第 25 項），中文填中文頁，英文填英文頁。
- 第 20 項的 App 私隱標籤和 `PrivacyInfo.xcprivacy` 要和這份一致。

### 第 20 項的進度

私隱清單和 CI 的核對 2026-10-22 做完（`bbe77ee`；CI run `39707669808` 五個 job 綠燈，親友版 363 個測試，公開版 295 個，和之前相同（這次沒有加 Swift 測試），編譯警告也相同；新的「Check the public app's privacy manifest」通過），**問卷還沒有填**：要有第 22 項的帳戶；答案使用者 2026-10-22 確認照草稿。

- 私隱清單 `GFlyerIOS/Public/PrivacyInfo.xcprivacy` 只有公開版有：沒有追蹤，不收集資料。寫了三類指定原因 API：`UserDefaults`（`CA92.1`）、檔案時間（`C617.1`，idevice 連結的 Rust 標準程式庫用 `stat`、`fstat`、`lstat`、`fstatat`）、開機時間（`35F9.1`，「探索」的地圖縮放用 `systemUptime`）。每一項的理由寫在 `docs/app-store-privacy.md`。
- `scripts/check_privacy_manifest.py` 做 App Store Connect 收到上傳時的同一種檢查：從 App 和通道 extension 執行檔的未定義符號和 Objective-C selector 找出用到的類別，和私隱清單比對，少寫就失敗。它不用 Mac：Windows 上用親友版的執行檔試過，掃到同樣三類。CI 的 archive job 對建好的公開版 App 跑它，另外跑 `plutil -lint`；Linux 的 job 跑 `--self-test`。通道 extension 沒有用到這些 API，所以沒有自己的清單。
- App Store Connect 的「App 私隱」問卷起草在 `docs/app-store-privacy.md`：答「不收集資料」，商店上顯示「Data Not Collected」。理由：
  - 地圖、搜尋和地名經 Apple 自己的 framework，Apple 寫明它收集的不用開發者申報。
  - 掛載 DDI 時送去 `gs.apple.com` 的 ECID，收到的也是 Apple。
  - 從 GitHub 下載只帶 IP 地址。
  - 「聯絡我們」的電郵由使用者的電郵 App 寄出，和 Android 相同。
- 和 Android 的標籤不同：Android 的資料安全性申報了位置、搜尋記錄和 Maps SDK 的四項，因為 Google Play 的定義不同，而且 Android 版加了 Google 的 Maps SDK。兩邊的做法相同。
- 使用者 2026-10-22 照建議決定：
  - 整份答「不收集」，包括 ECID，不申報 Device ID。申報的話，商店會顯示 App 收集裝置 ID，和 JetPiggy 實際收不到任何資料不符。
  - 「聯絡我們」的電郵不申報。
- 做完的標準：第 23 項第一次上傳時沒有收到 ITMS-91053 之類的電郵；有第 22 項的帳戶之後，在 App Store Connect 填好問卷。

### 第 21 項的進度

2026-10-22 核對完（`6268304`；CI run `39711079005` 五個 job 綠燈，親友版 363 個測試，公開版 295 個，和之前相同，編譯警告也相同；archive job 新加的檢查通過）。U9 使用者 2026-10-22 決定照建議：首版不在法國上架。理由和來源寫在 `docs/app-store-encryption.md`，是整理 Apple 和美國法規的公開資料，不是法律意見。

- 公開版 `Info.plist` 的 `ITSAppUsesNonExemptEncryption` 照舊是 `NO`。這個鍵從原型就有，第 8 項分版本時兩個版本各帶一份，之前沒有核對過理由。CI 的「Check and summarize the public app」檢查建好的公開版 App 這個鍵是 `NO`，少了或改了就失敗。親友版不上 App Store，不改。
- App 用到的加密都在 idevice 裏，用來連接同一部 iPhone 的開發者服務：
  - 驗證 Pairing File：X25519、Ed25519、HKDF、ChaCha20-Poly1305。
  - 之後的通道：idevice 自己實作的 TLS 1.2 PSK（AES-CBC）。
  - 在手機上配對：SRP-6a。
  - 另外連結了 rustls 和 ring。
  - 全部是 IETF 等的公開標準，沒有自創的。Swift 只用 Apple 系統的 HTTPS 和 SHA-256。
- 照 App Store Connect 說明的對照表，用了不是 Apple 系統提供的標準加密，只有在法國上架才要交文件（法國 ANSSI 的加密申報）；不在法國上架就算免交文件，可以寫 `NO`。美國方面，GFlyer 是大眾市場的完整 App（5D992.c），照現行的 15 CFR 740.17(e)(3)，不用交每年的自我分類報告，也不用 CCATS。
- 所以第 22 項建 App 時「價格與供應狀況」不選法國。之後要在法國上架，送審之前先申報、上載文件、拿到代碼，`Info.plist` 改成 `YES` 再加 `ITSEncryptionExportComplianceCode`，次序見那份文件第 4 節。
- 做完的標準：第 23 項第一次上傳之後，TestFlight 的建置不顯示缺少出口合規資料，也不用回答加密的問題。

### 第 23 項的進度

2026-10-29 先做不用帳戶的部分：上傳用的 release 建置（`71d5ed7`、`4088e38`；CI run `40769781971` 綠燈，親友版 364 個測試，公開版 304 個，和之前相同，編譯警告也相同；`export-public.yml` 的 run `40776387662` 綠燈，匯出的資料夾裏 `scripts/ci.sh archive` 的同一個檢查也通過）。第一次跑時，親友版測試的 job 到了 30 分鐘上限被取消，但步驟全部成功；上次同一個 job 用 11 分鐘，所以是 runner 慢。重跑那個 job 用了 10 分鐘，綠燈。簽署和上傳的 workflow 也寫好了，見最後一點。

- `project.yml` 新加 release 類的 `AppStore` 設定。公開版的 target 在這個設定下連結 idevice 的四項設定，和 `Idevice` 相同，改其中一個時兩個一起改。`GFlyerPublic-Idevice` 的 archive 改用 `AppStore`；在 iPhone 上執行照舊用 `Idevice`（debug 類）。
- 親友版不受影響：它的 scheme 和設定沒有改，IPA 的摘要和上次的 run `40765114958` 完全相同，連執行檔。
- CI 的 archive job 新加「Check the public app is an upload build」，檢查兩樣：archive 裏有 App 和通道兩份 dSYM；兩個執行檔都沒有 `$GITHUB_WORKSPACE/` 底下的路徑。公開 repo 的 `scripts/ci.sh archive` 做同樣的檢查（用 `$PWD/`）。匯出的 `project.yml` 沒有註解，所以兩個設定的分別寫進匯出工具加的檔頭（`4088e38`）。
- 結果：
  - 建好的公開版 App 掃描由 45 個提醒變 0 個。
  - 公開版的執行檔由 23.7 MB 變 4.3 MB，通道由 139 KB 變 93 KB。
  - 私隱清單核對照舊 0 個提醒。
  - 第 10 項說的 debug map 路徑已經沒有。
- 要知道的：release 建置把 15 個位元組以下的 Swift 字串常數直接寫在指令裏（例如「上一步」「下載 DDI」），`strings` 和公開版的摘要都列不出來。這次的摘要少了 224 句這樣的短字。插值的長片段反而在編譯時併成整句，例如「1. 打開「設定」>「私隱與保安」>「開發者模式」，打開最上面的開關。」。所以：
  - 以後拆開比對公開版，要和 run `40769781971` 或之後的摘要比，不要和之前 debug 類的比。
  - `--app` 掃描看不到 Swift 原始碼裏的短字。這些字原始碼掃描已經掃過（第 10 項）；`--app` 要管的是建置時才加進來的東西（資源、`Info.plist`、連結進來的程式庫），這部分不受影響。
- 簽署和上傳的 workflow 2026-10-29 寫好（`00857a8`、`577f789`）。CI 的結果：
  - run `40792079736` 綠燈：親友版 364 個測試，公開版 304 個，和之前相同，編譯警告也相同；兩個版本的 IPA 摘要和 run `40769781971` 完全相同。
  - 「App Store upload」的 run `40792079738`：self-test 綠燈。
  - `export-public.yml` 的 run `40792079726` 綠燈：匯出 122 個檔案、202 處提醒，和之前相同。

  **還沒有真的簽署或上傳過**：要第 22 項的帳戶。
  - `.github/workflows/app-store.yml`：只在使用者手動觸發、而且在 `main` 時簽署；勾了「上傳」才上傳。push 改到簽署工具時，只跑不用秘密的 self-test。秘密放在 `app-store` environment，只准 `main` 用。
  - 做法：
    - 手動簽署：Apple Distribution 憑證的 .p12，加上 App 和本機通道兩個 App Store Connect 描述檔。不用自動簽署：每次新的 runner 會建一張新的開發憑證，又要登記裝置。
    - 上傳用 `xcodebuild -exportArchive` 加 API 金鑰。不用 `altool`：Xcode 26 的 altool 上傳失敗時，不一定回傳失敗的結束碼。
    - `libidevice_ffi.a` 每次從釘住的原始碼重新建置，不用快取。
    - `project.yml` 的 AppStore 設定多了 `PROVISIONING_PROFILE_SPECIFIER`，讀 `GFLYER_APP_PROFILE` 和 `GFLYER_TUNNEL_PROFILE`。平日是空的，所以兩個版本的 IPA 摘要都不變。
  - 上傳之前核對兩次：
    - archive 用 `tools/app-store/check_public_app.sh`。每次 push 的未簽署 archive 也改用它，檢查多了兩樣：版本號和 `project.yml` 相同、通道的 `CFBundleVersion` 和 App 相同。公開 repo 的 `scripts/ci.sh archive` 一起加了。
    - 匯出的 IPA 用 `signing.py check-ipa`：由這個團隊的 Apple Distribution 憑證簽、有 Packet Tunnel entitlement、沒有 `get-task-allow`、有 `beta-reports-active`、描述檔是裝好的那兩個。
  - 沒有 Mac 也準備得到簽署檔：`tools/app-store/signing.py` 的 `request`、`certificate` 和 `secrets` 在自己的電腦上跑（Windows 用 Git Bash 的 openssl）。它們產生 CSR 和 .p12、核對全部檔案，再用 gh 放進 environment。
  - self-test 用自己產生的假憑證和假描述檔試每一步：
    - Windows 上試到 `secrets --dry-run`，擋下 16 個應該擋下的例子。
    - macOS（runner）上連 `install`、`check-ipa` 和 `cleanup`，擋下 19 個。所以 macOS 26 的 `security import` 讀得到 OpenSSL 3 產生的 .p12（PBE-SHA1-3DES）。
  - 第一次真的跑時才知道的：
    1. Apple 網站的按鈕名稱：`docs/app-store-signing.md` 照 Apple 的英文說明頁寫，做第 22 項時截圖再改。
    2. 真的憑證在 runner 上是否有效。找不到 Apple 的中繼憑證時，`install` 照憑證裏寫的網址下載。
    3. Developer 角色的 API 金鑰夠不夠上傳。
    4. 簽好的 App 有沒有 `check-ipa` 要求的 `beta-reports-active`。
  - 做完的標準照表：TestFlight 出現建置。

### 第 28 項的進度

2026-10-22 寫好匯出工具（`cea85e6`；CI run `39717230770` 五個 job 綠燈，親友版 363 個測試，公開版 295 個，和之前相同，編譯警告也相同；新加的 `export-public.yml` 的 run `39717230754` 綠燈）。公開 repo 還沒有建立：建 repo 和 push 等使用者明確要求（`AGENTS.md`「匯出公開版」）。

- 工具是 `tools/export-public/export.py`，照 Android 的同名工具。它用 `git archive` 匯出一個 commit。頂層路徑、`GFlyerIOS/` 和 `GFlyerIOSTests/` 底下的資料夾、`scripts/` 底下的每一項都要分類，未分類就停。
- 不匯出的：兩個 `Family/`、`docs/`、`HANDOFF.md`、`.claude/`、`tools/`，以及 `scripts/` 裏的三個：
  - `check_public_sources.py`：清單本身就是禁用字。
  - `ipa_summary.py`：開發用的比較工具。
  - `make_brand_art.py`：要讀品牌中心；轉好的圖已經在 `Assets.xcassets`。
- `project.yml` 由工具產生：拿走親友版的兩個 target（`GFlyerIOS`、`GFlyerIOSTests`）、兩個 scheme（`GFlyerIOS`、`GFlyerIOS-Idevice`）、`- Family` 和全部註解（註解寫到親友版），換上公開版的說明。以下情況會停：
  - 多了沒有分類的 target 或 scheme。
  - 少了公開版的。
  - 剩下的引用指向親友版。
- 掃描範圍是匯出的全部檔案，連 overlay、scripts 和產生的 `project.yml`。禁用字用 `scripts/check_public_sources.py` 的同一份，再加親友版的 Bundle ID 和親友版 `Info.plist` 裏的三個私人網址。也擋 `.p8`（App Store Connect 的 API 金鑰）等檔案，和與親友版一模一樣的檔案。
- `--self-test` 確認每一道關卡都擋得住。故意拿走其中五道試過，self-test 都會失敗。
- 公開 repo 自己的檔案在 `tools/export-public/overlay/`：
  - README（中英文）：功能、要準備甚麼、建置、私隱、授權。
  - `AGENTS.md`，和只有 `@AGENTS.md` 的 `CLAUDE.md`。
  - `LICENSE`：Apache-2.0，和 Android 公開版同一份。
  - `NOTICE`：品牌名稱、App 圖示和飛豬圖不在授權範圍內，列出三張圖。
  - `.gitignore`。
  - CI：`.github/workflows/ci.yml` 的三個 job（模擬器測試、未簽署的 archive、開放原始碼授權）逐步呼叫 `scripts/ci.sh`。
- `ci.sh archive` 核對的和這個 repo 的「Check and summarize the public app」相同：`Assets.car`、App 圖示、Bundle ID、`ITSAppUsesNonExemptEncryption`、通道 extension 和私隱清單。不同的是它不檢查親友版的 `Info.plist` 鍵，因為鍵名本身就是禁用字。
- CI 怎樣跑：
  - 「Public edition source scan」每次 push 都跑 `--self-test`，再匯出和掃描一次。
  - `export-public.yml` 在匯出工具、`project.yml`、`scripts/` 或 `THIRD_PARTY_NOTICES.md` 改了時跑。它在 macOS 上加 `--build` 匯出，在匯出的資料夾跑公開 repo 的 `scripts/ci.sh` 全部步驟，再用這個 repo 的掃描器掃從匯出建出來的 App。
- `cea85e6` 的結果：
  - 匯出 118 個檔案。
  - 匯出的資料夾裏：Xcode 26.6；授權清單相符；公開版 295 個測試全過，和開發 repo 相同；archive 的檢查和私隱清單核對通過（`GFlyerPublic 0.6.17 (30)`）。
  - 掃建好的 App：沒有問題，也沒有提醒。開發 repo 建的公開版 App 有 45 個提醒，都是執行檔裏 `/Users/runner/work/GFlyer_IOS/...` 的路徑；從匯出的資料夾建的，路徑裏沒有 `GFlyer_IOS`。
- 這次用了 `macos-xcode.yml` 快取的 `libidevice_ffi.a`。快取沒有命中時，`ci.sh idevice` 會自己建置；這條路還沒有跑過，公開 repo 第一次跑 CI 時會跑到。
- 提醒共 195 處，不擋匯出：
  - 84 處 GFlyer-Suite：註解裏的出處。
  - 106 處提到開發 repo 才有的文件，多數是 `docs/APP_STORE_PLAN.md` 和 `docs/features/`。
  - 5 處連到 GitHub 上 JetPiggy 以外的帳戶：
    - `scripts/build_idevice.sh` 和 `scripts/ci.sh`：idevice 的原始碼（`jkcoxson/idevice`）。
    - App 下載 DDI 的來源：`doronz88/DeveloperDiskImage`。
    - 授權全文裏的 `agl` 和 `rust-lang`。
- Android 的公開版也留着註解裏的出處。公開 repo 的 `AGENTS.md` 寫明，它們是維護者的開發文件。
- 做完的標準是「匯出的 repo 自己的 CI 綠燈」。現在由 `export-public.yml` 代替證明；公開 repo 建好、第一次 push 之後，再看它自己的 CI。
- 使用者 2026-10-22 決定四項都照建議：
  1. 授權：照 Android 公開版用 Apache-2.0（overlay 的 `LICENSE`）。
  2. 名稱：repo 叫 `JetPiggy/GFlyer-iOS`，本機資料夾叫 `GFlyer-iOS-public`。
  3. idevice 的原始碼和 DDI 都在個人帳戶下的 repo，程式要從那裏下載，照留。RULES 第 5 節不准連去個人帳戶下的 repo，所以只有程式和建置腳本用到它們，README、NOTICE 和網站都不連去。沒有採用的做法：
     - 把 idevice fork 到 JetPiggy 名下，改用 fork：之後每次升 revision，都要先同步 fork。
     - 自己轉載 DDI：DDI 是 Apple 的檔案。
  4. 甚麼時候建 repo、第一次 push：送審之前（第 25 項前後），和私隱政策網頁一起。README 寫的是「暫時沒有在 App Store 提供」，上架之後要改。
- repo 建好之後，在 JetPiggy-Brand 的 session 登記（品牌規則第 8 節）：
  - `registry.md` 加 GFlyer iOS 的資料夾和 repo。
  - 更新 `repo-map.html`。

## 第四階段：簽署、TestFlight、送審

| # | 待辦 | 為甚麼和怎樣做 | 誰做 | 做完的標準 |
|---|---|---|---|---|
| 28 | 匯出公開版到 JetPiggy 的 repo | U8。照 Android 的 `tools/export-public/export.py`：按清單只匯出共用和 `Public/` 的檔案，掃描禁用字，檢查沒有和親友版一模一樣的檔案，在匯出的 repo 自己建置得到；加 `AGENTS.md`、`NOTICE`，並照品牌規則第 8 節登記。建 repo 和 push 等使用者明確要求 | Claude 寫工具，使用者建 repo | 匯出的 repo 自己的 CI 綠燈；裏面沒有親友版的檔案和禁用字。工具 2026-10-22 做好；repo 送審之前（第 25 項前後）才建，見「第 28 項的進度」 |
| 22 | 付費開發者帳戶、App ID 和權限 | U1。App 和通道的 extension 各要一個 App ID，開 Network Extension（第 12 項不用 App Groups），建發佈憑證和描述檔，再建 API 金鑰、放進 GitHub（步驟見 `docs/app-store-signing.md` 第一部分）。建 App 時「價格與供應狀況」不選法國（U9、第 21 項） | 使用者 | 帳戶通過審核；App Store Connect 建好 App |
| 23 | CI 簽署並上傳 | 沒有 Mac，所以由 GitHub Actions 建置、簽署，並用 App Store Connect API 金鑰上傳。憑證、描述檔和金鑰只放 GitHub 的加密 secrets，不 commit（`AGENTS.md`）。repo 是公開的，從 fork 開的 PR 拿不到 secrets；上傳的 job 只在使用者手動觸發時執行。上傳的建置用 release 類的 `AppStore` 設定。兩樣都在 2026-10-29 做好：release 建置，以及簽署和上傳的 workflow（`.github/workflows/app-store.yml`，步驟見 `docs/app-store-signing.md`），還沒有真的跑過，見「第 23 項的進度」 | 使用者建 secrets；Claude 寫 workflow | TestFlight 出現建置 |
| 24 | TestFlight 實機測試 | iOS 27、從沒配對過電腦的 iPhone 全程不用電腦：安裝、開發者模式、配對、通道、DDI、傳送、清除。另外測 iOS 26 以下匯入配對檔、Wi-Fi 和行動網路、重新開機後重建、路線在背景和鎖屏時繼續、清除後真實位置恢復（`docs/RELEASE_PROCESS.md` 不可回退的決定第 5 點） | 使用者 | 每一項有結果，記進 `HANDOFF.md` |
| 25 | 商店資訊 | 名稱、副標題、說明、關鍵字、截圖、支援網址、私隱網址。不提遊戲和「作弊」，截圖和說明只展示公開版真正有的功能；照 JetPiggy 的規則檢查 | Claude 起草，使用者確認 | 全部填好 |
| 26 | 送審說明 | 審查指南 2.3.1 要求說明寫清楚每個功能。附示範影片：開發者模式、配對、通道、傳送、定位檢查、清除。逐項說明為甚麼要開發者模式、本機網路、通道和背景執行 | Claude 起草，使用者錄影片 | 已送審 |
| 27 | 送審和發佈 | | 使用者 | App Store 上看得到 |

## 上架之後（不阻擋首版）

想加回的功能要在送審之前做完合規的工作，不可以當成過審後才打開的隱藏功能。和 Android 公開版的第二階段相同：

- 留言板：審查指南 1.2 要求過濾、檢舉、封鎖和公開的聯絡方法；要公開版自己的後端和條款，並給審查員能用的測試帳號。在那之前，分享座標和路線用 GPX 和備份檔。
- 自訂或已取得授權的座標集，代替座標圖鑑。
- 蛇形探索的 530 米間距改成可以自訂。
- 匯入地圖連結建立路線。

## 風險和還沒確認的事

- **審查可能拒絕。** 這是最大的不確定。LocationLab 和 LL Pair 都過了審查，是好的先例；但審查逐案判斷，上架之後也可能被下架。
- **本機通道沒有在實機試過**（第 12 項）：只導一個 /32 位址、通道介面用 `10.7.0.2`、`tunnelRemoteAddress` 用通道介面的位址，這些設定都還沒有在 iPhone 上跑過；要付費開發者帳戶才簽得了 Network Extension。
- **「顯示開發者模式」的做法是推論**（第 13 項），要用一支從沒配對過的 iOS 27 iPhone 確認。
- **背景播放路線。** 現在靠背景定位模式和 `CLBackgroundActivitySession` 讓路線在背景繼續。審查指南 2.5.4 只准背景服務用在原本的用途，送審時要照實說明，審查員可能有意見。
- **個人帳戶和 VPN**，見 U1。
- **DDI 的來源。** Apple 的映像放在第三方的 GitHub repo，公開版靠它下載（第 15 項）。repo 不見了或改了內容，SHA-256 核對不過就下載不到，要改 App 換來源。
- **Apple 的地點服務**（第 17 項）。Apple 的文件說反查有每個 App 的頻率限制，沒有公布數字；收藏很多的人第一次允許時，可能有一部分查不到，要到下次開 App 才再查（`region-labels.md` 3.6）。另外 Apple 開發者論壇有人說 iOS 26 SDK 把 `CLPlacemark` 的部分欄位標成 deprecated，改推 MapKit 的 `MKReverseGeocodingRequest`；最低 iOS 是 17.4，CI 沒有出現警告，GFlyer 用的欄位有沒有一起標還沒有在 SDK 的標頭確認。最低 iOS 升到 26 時再看要不要改，改了要重新對 fixture。
- **沒有 Wi-Fi 時能不能配對**還不知道。LL Pair 和 StikPair 都要求本機網路權限。
- **iOS 更新。** Apple 以後可能改變配對或 DDI 的做法。Apple 的 Device Hub 文件說升級 iOS 之後要重新配對，要實測對 GFlyer 的配對檔有沒有影響。
- **iOS 26 以下仍然要電腦。**
- **在手機上配對**（第 4 項）：2026-10-20 實機確認「設定」找得到同一支 iPhone 上廣播的 GFlyer；`BGContinuedProcessingTask` 在 SideStore 簽的 App 上也被接受（系統顯示「在這支 iPhone 上配對」的進度），GFlyer 在「設定」裏一直等到配對完成。還不知道「設定」用哪種位址連進來（GFlyer 沒有記錄），也還沒試過台灣繁體中文或其他語言的「設定」。
- **Liquid Glass 外觀。** 用 iOS 26 SDK 建置的 App 在 iOS 26 以上會自動換成新外觀。第 1 項在 `Info.plist` 加了 `UIDesignRequiresCompatibility`，暫時保留舊外觀，讓第 1 項只換 toolchain。Apple 在 WWDC25 說這個選項會在下一個主要版本拿掉；用 iOS 27 SDK 建置時系統不理會這個鍵。所以 CI 升到 Xcode 27 之前，要先改用新外觀，並且逐頁看過 CI 截圖和實機。App Store 甚麼時候開始只收 Xcode 27 建置的版本，Apple 還沒有公布。

## 已做

- **第 1 項：CI 從 Xcode 16.4 升到 Xcode 26**（2026-10-19，`754e800`、`d6905e7`；實機 2026-10-20）：兩個 job 改在 `macos-26` 用 Xcode 26.6（Swift 6.3.3、iOS 26.5 SDK）建置。CI run `39272157905` 兩個 job 綠燈，294 個測試通過，編譯警告和 Xcode 16.4 時同樣 5 個。拆開 IPA：檔案和 Xcode 16.4 時相同，有 `Assets.car` 和 `AppIcon60x60@2x.png`；版本 0.6.13 (26)，`MinimumOSVersion` 17.4，`DTSDKName` iphoneos26.5。`Info.plist` 加了 `UIDesignRequiresCompatibility`，CI 截圖和 Xcode 16.4 時一樣。iOS 26 的模擬器第一次啟動要 50 秒左右才畫出畫面，原本固定等 8 秒，截到的是空白畫面，截圖步驟已改成等畫面出現。實機：用 Xcode 26 建置的 0.6.14 (27)（`ec4feb6`）2026-10-19 發佈，使用者 2026-10-20 經 SideStore 更新後回報沒有問題，沒有逐項回報。
- **第 2 項：升級 idevice 的釘選版本**（2026-10-20，`0944cb4`；實機 2026-10-20）：從 `37ee77c` 升到上游 2026-10-08 的 `3854a5d`，包含配對主機的取消（`393b438`）、OPACK 解碼（`6fb49ae`）和 10 月 8 日的四個擁有權修正。Swift 用到的 19 個 idevice 函式，簽名和擁有權都沒有變，七個 features 都還在。GFlyer-Suite `native/idevice/` 升到同一個 revision（Suite `40386f4`），Windows 的 DLL 還沒有重建。用它建置的 0.6.15 (28)（`3bd4fb2`）2026-10-20 發佈，使用者經 SideStore 更新後回報沒有問題，沒有逐項回報。
- **第 3 項：配對主機的 FFI**（2026-10-20，`0c73596`、`dd09d31`）：不用自己寫。第 2 項升到的 `3854a5d` 已經包含上游 2026-09-12 加入的 `ffi/src/pairing_host.rs`（`6fb49ae`，上游註明參考 AltStore 的 FFI），分工正是原先打算自己寫的那樣：`pairable_host_prepare` 產生主機身分，交回 service identifier 和 TXT（XML plist，含 `authTag`），不綁 port、不廣播；`pairable_host_accept_fd` 接手 Swift 已經 accept 的連線，跑完配對，交回配對檔；`pairable_host_free` 釋放。三個函式由 `build_idevice.sh` 現有的 `tunnel_tcp_stack` 帶進來的 `remote_pairing` feature 編入，features 不用改。CI 的「Verify the idevice library is complete」現在檢查它們在 `idevice.h` 和 `libidevice_ffi.a` 的符號索引裏都有，少了就失敗；CI run `39305795528` 檢查通過，archive 成功。檢查要看符號索引（`nm --print-armap`），不能用 `nm` 逐個 `.o` 列：Rust 1.99 用 LLVM 23，Xcode 26.6 的 `nm` 是 LLVM 21，讀 Rust `.o` 裏附帶的 bitcode 會報錯，一個 Rust 函式都列不出來。連結器靠的也是符號索引，所以 App 照樣連結得到。不要用旁邊 `ffi/src/pairable_host.rs` 的 `pairable_host_accept`：它用 Rust 的 `mdns_sd` 自己送 multicast，iOS 上要 Apple 個別核准的權限。這三個函式只有 iOS 用得到，GFlyer-Suite 的 `native/idevice/` 不用改。
- **第 4 項：Swift 的配對流程**（2026-10-20，`983f3ae`；實機 2026-10-20，`0.6.16 (29)`）：CI run `39311965583` 綠燈，新加 14 個測試。網路全由 Swift 做（`GFlyerIOS/Services/PairingHost.swift`）：開一個 IPv4、IPv6 都收得到的 TCP socket，port 由系統挑；呼叫 `pairable_host_prepare` 取得 service identifier 和 TXT，用 dns_sd 以 service identifier 作名稱廣播 `_remotepairing-pairable-host._tcp`。不用 `NetService`，它已經 deprecated，dns_sd 就是它底下的 API。「設定」連進來之後，把連線的 fd 交給 `pairable_host_accept_fd`；一次沒有成功（例如 PIN 打錯）就繼續等下一次。取消和 5 分鐘逾時要對連線呼叫 `shutdown`，因為上游會 `dup` 這個 fd，只 `close` 不會讓它返回。連線要設 `SO_NOSIGPIPE`，否則對方先斷線時，SIGPIPE 會結束整個 App。`Info.plist` 加了 `NSBonjourServices` 和 `BGTaskSchedulerPermittedIdentifiers`（`<bundle id>.pairing.*`），本機網路的說明也改了。使用者切去「設定」時，`BGContinuedProcessingTask`（iOS 26 起）讓 App 繼續等，不用無聲音訊之類的做法（審查指南 2.5.4）；它的進度用經過的秒數。PIN 用本機通知和這個背景工作的標題顯示，使用者在「設定」裏就看得到。入口只在 iOS 27 以上的 idevice 版出現，模擬進行中不能按。配對成功就寫進 `PairingFileStore`，第 5 項的存檔部分因此已經做了。實機（iOS 27，香港繁體中文）：「設定」>「私隱與保安」>「開發者模式」的「其他裝置」列出「Pair with GFlyer」，按「配對」、輸入 GFlyer 的 6 位數字後配對成功，GFlyer 存好新的 Pairing File；畫面見第一階段的「iOS 27 實機畫面」。用新檔建立通道算在第 5 項。
- **第 5 項：存檔和匯出**（2026-10-20，`b92b36e`、`c168834`；實機 2026-10-21，`0.6.17 (30)`）：存檔在第 4 項已經做好：配對成功後寫進 `PairingFileStore` 的同一個位置（`save(_:)`，和手動匯入共用），檔案保護相同；新的配對成功才取代舊檔。匯出：設定頁「首次設定」有 Pairing File 時多一個「匯出 Pairing File」，用 `.fileExporter` 原樣存成 `gflyer-pairing-file.plist`（XML plist，和 idevice_pair 產生的 RP Pairing File 同一種格式），新加 4 個 `PairingFileStoreTests`。實機：0.6.16 重開 App 後用在手機上配對得到的檔傳送成功；0.6.17 匯出到「檔案」、移除後匯入匯出的檔、傳送、「完整清除模擬定位」都通過。SideStore 的 nightly（0.7.0）在「Settings › Pairing File Management › Remote Pairing File」收 RP Pairing File，但要先「Reset Pairing Files」，失敗時 SideStore 不能重簽，所以沒有叫使用者試；做完的標準因此改成「匯出的檔匯回 GFlyer 能傳送」。2026-10-21 使用者回報「移除 Pairing File」一按就刪，`63258ea` 改成先跳「移除 Pairing File？」問一次，還沒有發佈。
- **第 6 項：App 內的配對說明**（2026-10-20，`02c741c`；`0.6.17 (30)`）：0.6.16 的說明和更新說明都寫「「設定」的「開發者模式」」，漏了「私隱與保安」，使用者照着找不到。照使用者的實機截圖重寫（見第一階段的「iOS 27 實機畫面」），名稱用香港繁體中文；配對進行中步驟也留在畫面上。文字和截圖一字不差，但沒有另外找沒看過說明的人照着試。
- **第 11 項：公開版的名稱和圖示**（2026-10-21，`e713a01`；CI run `39512133325` 三個 job 綠燈，兩個版本各 314 個測試、313 個通過、1 個依條件略過）：名稱「GFlyer - 飛豬人」在第 8 項已經設好。圖示照使用者 2026-10-21 的要求，親友版和公開版都換成 JetPiggy 飛豬，和 Android 兩個版本相同（GFlyer-Suite DRIFT D36）：`scripts/make_brand_art.py` 從品牌中心的正本轉出三張圖到兩個版本共用的 `GFlyerIOS/Resources/Assets.xcassets`。App 圖示和導覽列的 `GFlyerIcon` 是坐着的飛豬（`sit`），構圖和 Android 桌面上看得到的圖示相同；地圖上選取位置的 `GFlyerMarker` 是風鏡藍的定位針（`head_small`），和 Android 的逐個像素相同，`MainView` 的錨點改成針尖的 (0.5, 0.96)。第 8 項的暫時圖刪掉，親友版的舊超人飛豬也換掉。拆開比對：親友版和第 8 項之後比，只有兩個 App 圖示、`Assets.car` 和執行檔（錨點）不同，`Info.plist` 和字串相同；兩個版本的 App 圖示和 `Assets.car` 一模一樣。CI 截圖上導覽列的飛豬和地圖上的定位針淺色、深色都正常，還沒上機看。`NOTICE` 跟匯出的 repo 一起加（第 28 項）；App Store 上的名稱在第 22 項建 App 時查有沒有被用。
- **第 8 項：`project.yml` 分成兩個 App target**（2026-10-21，`32bc48a`、`be8da0d`）：`GFlyerIOS`（親友版）照舊，新加 `GFlyerPublic`（公開版，`com.jetpiggy.gflyer`，「GFlyer - 飛豬人」）和 `GFlyerPublicTests`。親友版的 `Info.plist`、entitlements 和三張飛豬圖搬到 `GFlyerIOS/Family/`；公開版在 `GFlyerIOS/Public/`，`Info.plist` 沒有三個私人網址和 sidestore、altstore，圖是沒有品牌的暫時圖。版本號改寫在 `project.yml`，兩個版本共用。版本介面 `EditionFeatures` 的第一個成員是回呼 scheme（親友版 `gflyer`，公開版 `jetpiggy-gflyer`），三個測試檔的回呼網址改用它。CI run `39509700101` 三個 job 綠燈：兩個版本各跑 314 個測試（新加 2 個 `EditionTests`），313 個通過、1 個依條件略過；編譯警告和之前相同，公開版只多了親友版本來就有的方向警告。`32bc48a` 的 run `39508327960` 公開版有一個測試失敗：`StepRecorderTests` 寫死了編碼後的 `gflyer%3A%2F%2F`，`be8da0d` 改掉。拆開前後比對（`scripts/ipa_summary.py`，拆開前是 `2f6ae06` 的 run `39507099264`）：親友版 IPA 只有執行檔不同（大 2,608 bytes，是新加的 `Edition`），`Info.plist`、`Assets.car`、兩個 App 圖示和677 條中文字串完全相同。公開版的 `Assets.car` 只有三張暫時圖，字串和親友版相同。這一項沒有發佈，也不用實機驗證：親友版的 IPA 內容沒有變。
- **第 10 項：CI 掃描公開版的原始碼**（2026-10-21，`ae9aefc`、`59b7f58`；CI run `39533536641` 四個 job 綠燈，親友版 327 個測試、公開版 240 個，和之前相同，編譯警告也相同）：`scripts/check_public_sources.py` 掃描公開版會編譯的檔案（`GFlyerIOS/` 和 `GFlyerIOSTests/` 扣掉 `Vendor/` 和兩個 `Family/`，檔名和內容，連註解和二進位檔）。禁用字照 Android 匯出工具的清單，再加明信片、SideStore、AltStore 和 LocalDevVPN；`overflowError` 不算「flower」，因為連結進來的 idevice（Rust 的 regex 套件）有這個字。也擋簽署用的檔案、Pairing File，和與親友版一模一樣的檔案（兩個版本的 entitlements 都是空的，列為允許）；`project.yml` 兩個公開版 target 的 sources 和掃描的範圍不同時也會失敗。CI 新加 Linux 的「Public edition source scan」job：先跑 `--self-test`（每條規則都要擋得住一個例子，範圍外的不擋），再掃描。archive job 上傳公開版的摘要之後，用 `--app` 再掃一次建好的公開版 App 的檔名、`Info.plist` 和每個檔案裏的字串，管建置時才加進來的字；拿親友版的 App 試過，擋下的全是親友版的字，沒有 idevice 的。私人 repo 的名稱（GFlyer-Suite、GFlyer-updates、GFlyer_IOS）只列提醒：原始碼 68 個，都是註解裏的出處；建好的 App 40 個，都是 debug map 裏 `/Users/runner/work/GFlyer_IOS/...` 的路徑（見第 23 項）。掃描之前先改的：共用的程式裏提到 LocalDevVPN 的 5 句、「使用教學」的網址和兩句備份說明，改由 `Edition` 給（`tunnelWording`、`userGuideURL`、`restoreConfirmationMessage`、`backupFormatNote`）。親友版的字一字不改；公開版用中性的暫時說法（例如「CoreDevice/RSD 交握失敗：請重新建立本機通道；…」，第 14 項的引導會重寫），沒有「使用教學」，備份說明不提留言板。另外改寫了三段提到親友版功能的註解。拆開比對：親友版除了執行檔完全相同；公開版只有上面幾句字串不同；主畫面的截圖和第 2 步相同（差一、兩個色階，是繪製的誤差）。`ae9aefc` 的 run `39533257317` 編譯失敗：兩個 `Edition.swift` 少了 `import Foundation`，`59b7f58` 補上。做完的標準：暫時的 branch 在共用的 `TunnelRoute.swift` 加一行提到「種花」的註解，run `39534682262` 的掃描 job 失敗（`GFlyerIOS/Services/TunnelRoute.swift:66：「種花」`），之後取消那次 run、刪掉 branch
- **第 7 項：發佈有「在這支 iPhone 上配對」的親友版**（`0.6.16 (29)`、`0.6.17 (30)`，2026-10-20）：兩版的實機結果記在 `HANDOFF.md`；GFlyer-Suite PARITY「在手機上配對」的 iOS 格子改成 ✅。

2026-10-09 和 2026-10-19 的研究結果寫在上面，來源見下一節。

## 參考

- LocationLab：<https://locationlab.net/>，App Store id6800266871（開發者工具，最低 iOS 26）
- LL Pair：<https://locationlab.net/ll-pair/support.html>，App Store id6819981217（2026-10-12 上架，最低 iOS 27）
- Apple：[Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)、[Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [SDK 最低要求](https://developer.apple.com/news/upcoming-requirements/)
- idevice：<https://github.com/jkcoxson/idevice>（MIT；GFlyer 用的配對主機 FFI 在 `ffi/src/pairing_host.rs`。同一層的 `ffi/src/pairable_host.rs` 用 Rust 自己廣播，iOS 上不能用）
- StikPair：<https://github.com/StikDebug/StikPair>（只參考做法；授權禁止商業用途）
