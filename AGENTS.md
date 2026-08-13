# GFlyer iOS 專案協作規則

## 專案範圍

- 這是一個獨立的個人側載 iOS 專案，與 Android 專案 `C:\Project\GFlyer` 分開維護。
- 原始碼位於 `GFlyerIOS/`；XcodeGen 設定位於 `project.yml`。
- 不要把 Android Kotlin 檔案、Android build output 或 Android backend 搬回本專案。

## 目前目標

- 先完成「裝置級 GPS 模擬」硬性可行性測試，再擴充完整 GFlyer 功能。
- 使用者可第一次連接電腦，但正常使用期間不需要持續連接電腦。
- 目前只做個人側載，不做 App Store 發佈。

## 開發規則

- 不要複製 StikDebug 的 AGPL UI 或應用程式碼。
- 可使用 MIT 授權的 `idevice`，並保留 `THIRD_PARTY_NOTICES.md`。
- 不要提交 Pairing File、Apple 私密金鑰、provisioning profile、DDI 二進位檔或 `libidevice_ffi.a`。
- `GFlyerIOS/Vendor/idevice/`、`.build/`、產生的 `.xcodeproj` 都應保持未追蹤。
- 不要加入反偵測、修改第三方遊戲客戶端或規避第三方定位檢查功能。

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
