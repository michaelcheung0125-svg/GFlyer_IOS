# GFlyer iOS 專案協作規則

## 專案範圍

- 這是一個獨立的 iOS 專案，與 Android 專案 `C:\Project\GFlyer` 分開維護。目前發佈的是個人側載的親友版；上架 App Store 的公開版在規劃中（見「目前目標」）。
- 原始碼位於 `GFlyerIOS/`；XcodeGen 設定位於 `project.yml`。有兩個 App target：`GFlyerIOS`（親友版）和 `GFlyerPublic`（公開版）。`GFlyerIOS/` 兩個版本共用，`GFlyerIOS/Family/` 只給親友版，`GFlyerIOS/Public/` 只給公開版，`GFlyerPublicTunnel/` 是公開版內建的本機通道（Network Extension，`docs/APP_STORE_PLAN.md` 第 12 項）；共用的程式只經 `Edition` 和 `EditionModel`（介面在 `GFlyerIOS/Edition/EditionFeatures.swift`）碰版本專屬的東西。App 圖示和飛豬圖兩個版本相同，由 `scripts/make_brand_art.py` 從 JetPiggy 品牌中心的正本轉出，不要手改；正本換了就重跑。
- 不要把 Android Kotlin 檔案、Android build output 或 Android backend 搬回本專案。

## 跨平台功能（改功能前先判斷）

- 這個 App 不是唯一的平台：Android 版在 `C:\Project\GFlyer`（**參考實作**），Windows 版規劃在 GFlyer-Suite 的 `apps/windows/`。跨平台的規格（`docs/features/`）、共用 fixture（`contracts/`）、功能對照表 `docs/PARITY.md`、差異紀錄 `docs/DRIFT.md` 與發佈工具都在 `C:\Project\GFlyer-Suite`。
- 改任何使用者看得到的功能或資料格式之前，先查 GFlyer-Suite `docs/PARITY.md` 對應的那一列與 `docs/DRIFT.md`：
  - **平台專屬**（PARITY 標 ➖，例如 LocalDevVPN、Pairing File、DDI、捷徑）：照本檔規則做，不用動 Suite。
  - **Android 也有這個功能，或會碰到共用格式**（備份、留言板 API、座標圖鑑資料、GPX、`contracts/` 裡的任何東西）：照 `C:\Project\GFlyer-Suite\AGENTS.md` 的流程 —— 先改 `docs/features/` 規格與 `contracts/`，再改這個 App；行為與文字以 Android 為準，使用者看得到的文字三平台一字不差。
- 讀 Android 的程式碼來對照永遠可以；**要修改 Android 或其他 repo，必須是使用者這次指定的範圍**（`HANDOFF.md` 開頭「唯一工作目錄」那句是寫給單純 iOS 工作的 session）。
- 改完回報時一定要列出：Android 要不要跟著改、Windows 要不要（目前多半只需寫進規格）、要不要記進 `DRIFT.md`，並問使用者要「現在一起改」還是「先記進 DRIFT」。不要自己決定跳過另一個平台。
- 跨 repo 的修改在各 repo 各自 commit，後 commit 的一邊在訊息寫出先 commit 那一邊的 hash。

## 目前目標

- 先完成「裝置級 GPS 模擬」硬性可行性測試，再擴充完整 GFlyer 功能。
- 使用者可第一次連接電腦，但正常使用期間不需要持續連接電腦。
- 親友版（現在的 App）照舊個人側載，經 SideStore 安裝。
- 2026-10-19 使用者決定：iOS 照 Android 分成親友版和公開版，公開版以上架 App Store 為目標，在 iOS 27 以上做到全程不用電腦。計劃、次序和要使用者決定的事在 `docs/APP_STORE_PLAN.md`；跨平台的紀錄是 GFlyer-Suite DRIFT D35 與 PARITY「iOS 的兩個版本」。
- 2026-10-21 起分成兩個 target（`docs/APP_STORE_PLAN.md` 第 8 項）。做新功能之前先決定它給不給公開版，拿不準就只放 `GFlyerIOS/Family/` 並問使用者。
- 公開版會編譯的檔案（`GFlyerIOS/`、`GFlyerPublicTunnel/` 和 `GFlyerIOSTests/` 扣掉 `Vendor/` 和 `Family/`，連註解）要通過 `scripts/check_public_sources.py`：不可以有遊戲用語、親友版的功能名稱、SideStore／AltStore／LocalDevVPN、私人網址、個人帳戶和本機路徑。CI 的「Public edition source scan」跑它，建好的公開版 App 也再掃一次。共用的程式要說到這些，改由 `Edition` 給字，或搬進 `Family/`；改 `project.yml` 的 sources 時，同步改這個檔案的範圍。

## 開發規則

- 寫、審或修改任何 Swift 程式碼前，先讀 `.claude/skills/write-swift/SKILL.md` 開頭的「本專案版本護欄」。那一節寫明本專案的 toolchain（Swift 5 語言模式、CI 釘在 Xcode 26.6、最低 iOS 17.4）與因此不能使用的語言特性，並且優先於該 skill 其餘內容。
- 不要複製 StikDebug 的 AGPL UI 或應用程式碼。
- 可使用 MIT 授權的 `idevice`，並保留 `THIRD_PARTY_NOTICES.md`。
- 不要提交 Pairing File、Apple 私密金鑰、provisioning profile、DDI 二進位檔或 `libidevice_ffi.a`。
- `GFlyerIOS/Vendor/idevice/`、`.build/`、產生的 `.xcodeproj` 都應保持未追蹤。
- 不要加入反偵測、修改第三方遊戲客戶端或規避第三方定位檢查功能。

## 發佈規則

- 要把程式碼改動交付給使用者，必須依照 `docs/RELEASE_PROCESS.md` 的流程：
  升版本號 → CI → **拆開 IPA 驗證內容** → 公開 release → 更新
  `altstore.json` → 線上驗證 → 記錄到 `HANDOFF.md`。
- CI 綠燈不等於產物正確；發佈前一定要驗證 IPA 內含 `Assets.car`、App 圖示
  與正確版本號。
- `docs/RELEASE_PROCESS.md` 末段列出「不可回退的決定」；修改相關程式碼前
  先讀那一節。

## 建置限制

- 本專案必須在 macOS/Xcode 上完成真正的 iOS 編譯與實機驗證。
- Windows 可以編輯、審查與執行不依賴 Xcode 的靜態檢查，但不能宣稱已完成 iOS 實機驗證。
- 使用 XcodeGen 產生專案：`xcodegen generate`。
- 正常預覽 scheme：`GFlyerIOS`。
- 真實裝置 scheme：`GFlyerIOS-Idevice`。
- `GFlyerIOS-Idevice` 需要先執行 `scripts/build_idevice.sh`。

## 驗證順序

1. 先驗證個人簽署與 IPA 安裝。
2. 匯入 Pairing File。
3. 開啟 LocalDevVPN，預設目標 IP 是 `10.7.0.1`。
4. 第一次裝置模式啟動時，讓 App 下載並驗證 Personalized DDI。
5. 用 Apple Maps 驗證單點位置、第二個位置更新及清除定位。
6. 實機單點成功後，才測試路線、循環、暫停與重新啟動恢復。

## 變更完成條件

- 相關 Swift 原始碼可由 Swift parser 解析。
- plist/XML、YAML 與 shell script 語法檢查通過。
- 在 Mac 上執行 Xcode build/test；在 Windows 上不得把靜態檢查當成 Xcode build。
- 重大行為變更要同步更新 `README.md`、`docs/IMPLEMENTATION_PLAN.md` 與 `HANDOFF.md`。
