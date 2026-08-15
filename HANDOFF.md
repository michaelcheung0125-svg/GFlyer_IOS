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
- Personalized Developer Disk Image 下載、固定 revision、SHA-256 驗證及需要時掛載
- 修正固定 DDI commit 的 BuildManifest SHA-256 與 iPhoneOS Rust sysroot 建置參數
- App 重啟/強制關閉後的「強制清除模擬定位」恢復路徑
- `GFlyerIOS-Idevice` XcodeGen scheme
- GitHub Actions macOS simulator test 與 unsigned device archive workflow
- 實機硬性可行性測試記錄表
- `idevice` MIT 授權 notice 與個人側載限制文件

GitHub Actions 的兩個 job 已在 Xcode 16.4 完整通過。Simulator unit test 曾因
App target 的 `PRODUCT_NAME` 是 `GFlyer`，
而 XcodeGen 預設 test host 仍指向 `GFlyerIOS.app/GFlyerIOS` 而失敗；目前已在
`project.yml` 明確設定 `TEST_HOST` 與 `BUNDLE_LOADER` 指向
`GFlyer.app/GFlyer`。該問題排除後，測試編譯進一步發現 `PRODUCT_NAME`
同時把 Swift module 改名為 `GFlyer`，與測試的 `@testable import GFlyerIOS`
不一致；固定 `PRODUCT_MODULE_NAME: GFlyerIOS` 後，Simulator tests 與
`Idevice unsigned archive` 均已通過。通過的程式 commit 是 `b777985`。

## 重要檔案

```text
project.yml
README.md
THIRD_PARTY_NOTICES.md
docs/IMPLEMENTATION_PLAN.md
scripts/build_idevice.sh
GFlyerIOS/Model/GeoCoordinate.swift
GFlyerIOS/Model/SimulationModels.swift
GFlyerIOS/Services/SimulationController.swift
GFlyerIOS/Services/DeviceLocationService.swift
GFlyerIOS/Services/IdeviceLocationSimulationBackend.swift
GFlyerIOS/Services/DeveloperDiskImageStore.swift
GFlyerIOS/Services/PairingFileStore.swift
GFlyerIOS/UI/MainView.swift
GFlyerIOS/UI/SetupView.swift
GFlyerIOSTests/GeoMathTests.swift
GFlyerIOSTests/FeatureModelTests.swift
GFlyerIOS/Services/LocalDataStore.swift
GFlyerIOS/Services/PlaceSearchService.swift
GFlyerIOS/UI/LibraryViews.swift
```

## 下一個對話應先做什麼

新對話開始時，先讀取本檔案、`AGENTS.md`、`README.md` 及 `docs/IMPLEMENTATION_PLAN.md`，然後依序處理：

### 1. 驗證目前第 1 至第 3 階段

目前第 1 至第 3 階段的 UI、移動模式與本機資料功能已實作，但本次修改只在
Windows 完成靜態檢查。將專案推送到 GitHub 後，以
`workflow_dispatch` 或 push 執行 workflow，確認以下兩個 job 都通過：

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
- iOS 更新可能讓 pairing file、DDI 或 Apple 私有協定失效。
- 個人簽署 profile 會過期，過期時可能需要重新簽署或使用電腦刷新。
- 地圖及搜尋需要網路；定位控制本身透過 LocalDevVPN/裝置開發服務。
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
GPX、冷卻計時、跨日期提示與路線重排仍屬後續工作。
