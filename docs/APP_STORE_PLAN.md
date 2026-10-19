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

## 第一階段：Xcode 26 與在手機上配對

兩個版本都用得到。先在親友版做完，用 SideStore 裝到 iOS 27 的 iPhone 驗證；現在的使用者升級之後也不用再開 idevice_pair。

| # | 待辦 | 為甚麼和怎樣做 | 做完的標準 |
|---|---|---|---|
| 4 | Swift 的配對流程 | 程式已寫好（`983f3ae`，CI run `39311965583` 綠燈），等 iOS 27 實機。網路全由 Swift 做（`GFlyerIOS/Services/PairingHost.swift`）：開一個 IPv4、IPv6 都收得到的 TCP socket，port 由系統挑；呼叫 `pairable_host_prepare` 取得 service identifier 和 TXT，用 dns_sd 以 service identifier 作名稱廣播 `_remotepairing-pairable-host._tcp`。不用 `NetService`，它已經 deprecated，dns_sd 就是它底下的 API。「設定」連進來之後，把連線的 fd 交給 `pairable_host_accept_fd`；一次沒有成功（例如 PIN 打錯）就繼續等下一次。取消和 5 分鐘逾時要對連線呼叫 `shutdown`，因為上游會 `dup` 這個 fd，只 `close` 不會讓它返回。連線要設 `SO_NOSIGPIPE`，否則對方先斷線時，SIGPIPE 會結束整個 App。`Info.plist` 加了 `NSBonjourServices` 和 `BGTaskSchedulerPermittedIdentifiers`（`<bundle id>.pairing.*`），本機網路的說明也改了。使用者切去「設定」時，`BGContinuedProcessingTask`（iOS 26 起）讓 App 繼續等，不用無聲音訊之類的做法（審查指南 2.5.4）；它的進度用經過的秒數。PIN 用本機通知和這個背景工作的標題顯示，使用者在「設定」裏就看得到。入口只在 iOS 27 以上的 idevice 版出現，模擬進行中不能按。配對成功就寫進 `PairingFileStore`，第 5 項的存檔部分因此已經做了。設定頁上的說明是暫時的，第 6 項照實機畫面改寫 | iOS 27 實機上，「設定」的開發者模式頁列出 GFlyer，輸入 PIN 後配對成功 |
| 5 | 存檔和匯出 | 存檔已在第 4 項做好：配對成功後寫進 `PairingFileStore` 的同一個位置（`save(_:)`，和手動匯入共用），檔案保護相同；新的配對成功才取代舊檔。剩下的是匯出到「檔案」，給 SideStore 等其他工具用 | 重開 App 後用新檔建立通道並傳送一次；SideStore 收得下匯出的檔 |
| 6 | App 內的配對說明 | 每一步的文字要和 iOS 27 實機畫面一字不差，先拿到使用者的截圖再寫 | 沒看過說明的人照畫面能完成配對 |
| 7 | 發佈有「在這支 iPhone 上配對」的親友版 | 照 `docs/RELEASE_PROCESS.md` | 實機驗證並記進 `HANDOFF.md`；PARITY「在手機上配對」的 iOS 格子改成 ✅ |

## 第二階段：分成兩個版本

照 Android 的做法（GFlyer `AGENTS.md` 的「兩個版本」）。

| # | 待辦 | 為甚麼和怎樣做 | 做完的標準 |
|---|---|---|---|
| 8 | `project.yml` 分成兩個 App target | 親友版的 target 不變：bundle id、名稱、圖示、SideStore 來源都照舊。公開版是新的 target（U2）。資料夾：`GFlyerIOS/` 兩個版本共用，`GFlyerIOS/Family/` 只給親友版，`GFlyerIOS/Public/` 只給公開版。共用的程式只經一個版本介面碰版本專屬的功能，照 Android 的 edition 介面。從這一項起，做新功能之前先決定它給不給公開版；拿不準就放 `Family/`，並問使用者 | 兩個 target 都在 CI 編譯，共用的單元測試兩個版本都跑；親友版的 IPA 和拆開之前相同 |
| 9 | 把親友版專屬的功能搬進 `Family/` | 和 Android 公開版拿走的相同：留言板（連同地圖工具列的分享）、座標圖鑑（連同前往紀錄、到訪標記、NEW 和資料過時回報）、步數補錄（審查指南 5.1.3 不准寫入不實的健康資料，經使用者的捷徑寫也一樣）、超過 20 km/h 的種花提示。iOS 專屬的兩項：檢查新版和 SideStore 的連結（公開版經 App Store 更新），以及 LocalDevVPN 的交接（公開版改用第 12 項）。飛航模式輔助和它用的捷徑橋接留在共用 | 公開版的 App 裏沒有這些畫面和程式；親友版照舊；備份格式不變，公開版把沒有的功能的設定鍵當外來鍵保留、匯出時寫回（DRIFT D1 的做法） |
| 10 | CI 掃描公開版的原始碼 | 照 Android 匯出工具的禁用字檢查：公開版 target 會編譯的檔案不可以有遊戲用語（例如種花、明信片、皮克敏、Pikmin、找菇）、私人網址（留言板的 Worker、GFlyer-updates 的 Pages），以及 SideStore 和 AltStore | 故意加一個禁用字會讓 CI 失敗 |
| 11 | 公開版的名稱和圖示 | U2。圖檔的來源和授權要清楚，品牌素材照 JetPiggy 的規則（`C:\Project\JetPiggy-Brand\RULES.md`） | 公開版 IPA 的名稱和圖示正確，親友版不變 |

## 第三階段：公開版才有的

| # | 待辦 | 為甚麼和怎樣做 | 做完的標準 |
|---|---|---|---|
| 12 | App 內建的本機通道（Network Extension） | 審查指南 4.2.3 要求 App 不用另外安裝別的 App 就能運作。LocalDevVPN 雖然也上架了 App Store，公開版不可以要求使用者另外裝。做法：Packet Tunnel extension，只路由 `10.7.0.1` 這一個位址，把封包反射回手機本身。原理和 LocalDevVPN 相同，但程式自己寫，因為 LocalDevVPN 沒有標明授權。App 用 `NETunnelProviderManager` 開關，兩邊用 App Group 共享狀態；飛航模式輔助照舊。免費 Apple ID 不能簽 Network Extension，所以只有公開版有，親友版照舊用 LocalDevVPN | 沒有裝 LocalDevVPN 的 iPhone 用公開版建立通道並傳送；Wi-Fi 和行動網路（飛航模式流程）都試過；關掉通道後一般上網不受影響 |
| 13 | 「顯示開發者模式」 | 從 App Store 安裝的 App 不會讓開關出現。Apple 的文件說開始配對時開關才會出現，LL Pair 也有「顯示開發者模式」。推測做法是先開始廣播配對主機；LL Pair 沒有公開程式，要先實機確認 | 一支從沒接過電腦的 iOS 27 iPhone，從 TestFlight 安裝後能叫出開關 |
| 14 | 第一次設定的引導 | 一步一個畫面，文字照實機畫面寫：① 顯示開發者模式 ② 開啟開發者模式並重新開機 ③ 在手機上配對 ④ 建立本機通道 ⑤ 下載 DDI ⑥ 傳送一次並到 Apple 地圖確認 ⑦ 清除並恢復真實位置。iOS 26 以下的第 ③ 步改成匯入電腦產生的配對檔 | 沒看過說明的人照畫面能完成 |
| 15 | DDI 下載的說明 | 現在從第三方的 GitHub repo（`doronz88/DeveloperDiskImage`）下載 Apple 的映像，並核對 SHA-256。審查指南 4.2.3 要求第一次啟動要下載的資源先說明大小並詢問；2.5.2 不准下載會改變 App 功能的程式碼，DDI 是給 iOS 掛載的開發者映像，送審說明要寫清楚 | 下載前顯示大小並等使用者同意；送審說明寫明用途和來源 |
| 16 | 定位檢查頁（DRIFT D31） | 給審查員和使用者核對模擬有沒有生效、清除後有沒有恢復；Android 也是為審查做的。先在 GFlyer-Suite 寫 `docs/features/` 的規格，文字照 Android。用 `CLLocation.sourceInformation` 分辨模擬位置，要上機確認 | 規格寫好、兩邊文字一致，實機驗證 |
| 17 | 地名反查改用系統服務（DRIFT D33） | 公開的 Nominatim 只准全部用戶合計每秒一次，上了 App Store 一定超過。改用 `CLGeocoder`，照 `region-labels.md` 3.5a 和同一份 fixture；同意照 U7 | 公開版不連 Nominatim |
| 18 | 開放原始碼授權頁（DRIFT D34） | App Store 的使用者看不到 repo，散佈 idevice 和它連結的 Rust 程式庫要附上授權。清單從 Cargo.lock 產生；入口和頁名照 Android | 兩個版本都有，清單和實際打包的相符 |
| 19 | 私隱政策 | 審查指南 5.1.1 要求所有 App 在 App Store Connect 填私隱政策網址，App 內也要有入口。Android 的正本只寫 Android 公開版，要另寫 iOS 版：配對檔和通道只在手機上處理、DDI 從哪裏下載、地名服務、聯絡電郵、資料保存多久和怎樣刪除。網址由使用者決定，例如和 Android 同一個網站 | 頁面公開，不用登入就看得到；App 內有「私隱政策」；內容和 App 的實際做法一致 |
| 20 | 私隱資訊清單和 App 私隱標籤 | App Store 要求 `PrivacyInfo.xcprivacy` 宣告用到的指定原因 API（例如 `UserDefaults`、檔案時間）；App Store Connect 的資料收集問卷照實填。Claude 按程式的實際做法起草，使用者確認 | 上傳時沒有私隱清單的警告；問卷已提交 |
| 21 | 加密的出口申報 | 配對和通道用 SRP、TLS-PSK 等標準加密。`Info.plist` 的 `ITSAppUsesNonExemptEncryption` 和 App Store Connect 的問題照實回答。Claude 起草，使用者確認 | 每次上傳不用再手動回答 |

## 第四階段：簽署、TestFlight、送審

| # | 待辦 | 為甚麼和怎樣做 | 誰做 | 做完的標準 |
|---|---|---|---|---|
| 22 | 付費開發者帳戶、App ID 和權限 | U1。App 和通道的 extension 各要一個 App ID，開 Network Extension 和 App Groups，建發佈憑證和描述檔 | 使用者 | 帳戶通過審核；App Store Connect 建好 App |
| 23 | CI 簽署並上傳 | 沒有 Mac，所以由 GitHub Actions 建置、簽署，並用 App Store Connect API 金鑰上傳。憑證、描述檔和金鑰只放 GitHub 的加密 secrets，不 commit（`AGENTS.md`）。repo 是公開的，從 fork 開的 PR 拿不到 secrets；上傳的 job 只在使用者手動觸發時執行 | 使用者建 secrets；Claude 寫 workflow | TestFlight 出現建置 |
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
- **「顯示開發者模式」的做法是推論**（第 13 項），要用一支從沒配對過的 iOS 27 iPhone 確認。
- **背景播放路線。** 現在靠背景定位模式和 `CLBackgroundActivitySession` 讓路線在背景繼續。審查指南 2.5.4 只准背景服務用在原本的用途，送審時要照實說明，審查員可能有意見。
- **個人帳戶和 VPN**，見 U1。
- **DDI 的來源。** Apple 的映像放在第三方的 GitHub repo，公開版靠它下載（第 15 項）。
- **沒有 Wi-Fi 時能不能配對**還不知道。LL Pair 和 StikPair 都要求本機網路權限。
- **iOS 更新。** Apple 以後可能改變配對或 DDI 的做法。Apple 的 Device Hub 文件說升級 iOS 之後要重新配對，要實測對 GFlyer 的配對檔有沒有影響。
- **iOS 26 以下仍然要電腦。**
- **在手機上配對要實機確認的事**（第 4 項）：「設定」找不找得到同一支 iPhone 上廣播的 GFlyer、用哪種位址連進來；`BGContinuedProcessingTask` 能不能讓 GFlyer 在「設定」裏一直等到配對完成。SideStore 重簽時如果改了 bundle id，背景工作的識別碼可能不被接受，那時只剩 `beginBackgroundTask` 大約 30 秒的背景時間。
- **Liquid Glass 外觀。** 用 iOS 26 SDK 建置的 App 在 iOS 26 以上會自動換成新外觀。第 1 項在 `Info.plist` 加了 `UIDesignRequiresCompatibility`，暫時保留舊外觀，讓第 1 項只換 toolchain。Apple 在 WWDC25 說這個選項會在下一個主要版本拿掉；用 iOS 27 SDK 建置時系統不理會這個鍵。所以 CI 升到 Xcode 27 之前，要先改用新外觀，並且逐頁看過 CI 截圖和實機。App Store 甚麼時候開始只收 Xcode 27 建置的版本，Apple 還沒有公布。

## 已做

- **第 1 項：CI 從 Xcode 16.4 升到 Xcode 26**（2026-10-19，`754e800`、`d6905e7`；實機 2026-10-20）：兩個 job 改在 `macos-26` 用 Xcode 26.6（Swift 6.3.3、iOS 26.5 SDK）建置。CI run `39272157905` 兩個 job 綠燈，294 個測試通過，編譯警告和 Xcode 16.4 時同樣 5 個。拆開 IPA：檔案和 Xcode 16.4 時相同，有 `Assets.car` 和 `AppIcon60x60@2x.png`；版本 0.6.13 (26)，`MinimumOSVersion` 17.4，`DTSDKName` iphoneos26.5。`Info.plist` 加了 `UIDesignRequiresCompatibility`，CI 截圖和 Xcode 16.4 時一樣。iOS 26 的模擬器第一次啟動要 50 秒左右才畫出畫面，原本固定等 8 秒，截到的是空白畫面，截圖步驟已改成等畫面出現。實機：用 Xcode 26 建置的 0.6.14 (27)（`ec4feb6`）2026-10-19 發佈，使用者 2026-10-20 經 SideStore 更新後回報沒有問題，沒有逐項回報。
- **第 2 項：升級 idevice 的釘選版本**（2026-10-20，`0944cb4`；實機 2026-10-20）：從 `37ee77c` 升到上游 2026-10-08 的 `3854a5d`，包含配對主機的取消（`393b438`）、OPACK 解碼（`6fb49ae`）和 10 月 8 日的四個擁有權修正。Swift 用到的 19 個 idevice 函式，簽名和擁有權都沒有變，七個 features 都還在。GFlyer-Suite `native/idevice/` 升到同一個 revision（Suite `40386f4`），Windows 的 DLL 還沒有重建。用它建置的 0.6.15 (28)（`3bd4fb2`）2026-10-20 發佈，使用者經 SideStore 更新後回報沒有問題，沒有逐項回報。
- **第 3 項：配對主機的 FFI**（2026-10-20，`0c73596`、`dd09d31`）：不用自己寫。第 2 項升到的 `3854a5d` 已經包含上游 2026-09-12 加入的 `ffi/src/pairing_host.rs`（`6fb49ae`，上游註明參考 AltStore 的 FFI），分工正是原先打算自己寫的那樣：`pairable_host_prepare` 產生主機身分，交回 service identifier 和 TXT（XML plist，含 `authTag`），不綁 port、不廣播；`pairable_host_accept_fd` 接手 Swift 已經 accept 的連線，跑完配對，交回配對檔；`pairable_host_free` 釋放。三個函式由 `build_idevice.sh` 現有的 `tunnel_tcp_stack` 帶進來的 `remote_pairing` feature 編入，features 不用改。CI 的「Verify the idevice library is complete」現在檢查它們在 `idevice.h` 和 `libidevice_ffi.a` 的符號索引裏都有，少了就失敗；CI run `39305795528` 檢查通過，archive 成功。檢查要看符號索引（`nm --print-armap`），不能用 `nm` 逐個 `.o` 列：Rust 1.99 用 LLVM 23，Xcode 26.6 的 `nm` 是 LLVM 21，讀 Rust `.o` 裏附帶的 bitcode 會報錯，一個 Rust 函式都列不出來。連結器靠的也是符號索引，所以 App 照樣連結得到。不要用旁邊 `ffi/src/pairable_host.rs` 的 `pairable_host_accept`：它用 Rust 的 `mdns_sd` 自己送 multicast，iOS 上要 Apple 個別核准的權限。這三個函式只有 iOS 用得到，GFlyer-Suite 的 `native/idevice/` 不用改。

2026-10-09 和 2026-10-19 的研究結果寫在上面，來源見下一節。

## 參考

- LocationLab：<https://locationlab.net/>，App Store id6800266871（開發者工具，最低 iOS 26）
- LL Pair：<https://locationlab.net/ll-pair/support.html>，App Store id6819981217（2026-10-12 上架，最低 iOS 27）
- Apple：[Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)、[Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [SDK 最低要求](https://developer.apple.com/news/upcoming-requirements/)
- idevice：<https://github.com/jkcoxson/idevice>（MIT；GFlyer 用的配對主機 FFI 在 `ffi/src/pairing_host.rs`。同一層的 `ffi/src/pairable_host.rs` 用 Rust 自己廣播，iOS 上不能用）
- StikPair：<https://github.com/StikDebug/StikPair>（只參考做法；授權禁止商業用途）
