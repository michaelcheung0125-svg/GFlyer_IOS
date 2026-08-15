# GFlyer iOS 完整安裝與使用教學

> 適用於沒有 Mac、使用 Windows 電腦及個人 Apple ID 側載的使用者。
> 文件版本：2026-08-14

本教學由取得安裝檔開始，逐步完成 iPhone 安裝、Developer Mode、Remote Pairing、LocalDevVPN、首次定位測試、日常使用及每 7 天重新簽署。請依次完成，不要跳過配對或停止定位測試。

GFlyer 使用 iPhone 的開發者服務作全機定位模擬，只適合個人測試及研究用途。它不是 App Store App，也不包含反偵測、修改第三方 App 或規避第三方定位檢查功能。使用任何第三方服務前，仍須遵守該服務的條款及所在地法律。

## 先看結論

| 問題 | 答案 |
|---|---|
| 沒有 Mac 能否安裝？ | 可以。Windows 可使用 Sideloadly，以自己的 Apple ID 簽署 unsigned IPA。 |
| 免費 Apple ID 可用多久？ | 一般約 7 天。到期前要在電腦上重新簽署並覆蓋安裝。 |
| 每 7 天是否要重新下載或重建 IPA？ | 不需要。只要程式沒有更新，同一份 unsigned IPA 可一直重複使用。 |
| 重新簽署前要刪除 App 嗎？ | 不要。直接覆蓋安裝，較有機會保留 Pairing File 及 App 資料。 |
| Developer Mode 可否關閉？ | 正常使用 GFlyer 裝置模式時應保持開啟。關閉後 App 或裝置開發服務可能不能運作。 |
| 使用 GFlyer 前是否要先開 LocalDevVPN？ | 是。順序是 LocalDevVPN 開啟、GFlyer 開始、GFlyer 停止、LocalDevVPN 關閉。 |
| 多人可否使用同一份 IPA？ | 可以共用同一份未簽署 IPA；每人仍要用自己的 Apple ID 簽署，並為自己的 iPhone 產生 Pairing File。 |

## 完整流程概覽

1. 取得 `GFlyerIOS-Idevice-unsigned.ipa` 及 `THIRD_PARTY_NOTICES.md`。
2. 在 Windows 安裝 Apple 驅動、iCloud 及 Sideloadly。
3. 用自己的 Apple ID 簽署並把 IPA 安裝到自己的 iPhone。
4. 在 iPhone 開啟 Developer Mode，並信任開發者憑證。
5. 開啟 GFlyer，確認畫面顯示「裝置模式」。
6. 用 `idevice_pair` 為這部 iPhone 建立 Remote Pairing 檔案。
7. 把 Pairing File 私下傳到 iPhone，並匯入 GFlyer。
8. 安裝及開啟 LocalDevVPN，目標 IP 保持 `10.7.0.1`。
9. 第一次在 GFlyer 開始定位，等候 Personalized DDI 下載及驗證。
10. 用 Apple Maps 驗證第一個位置、第二個位置及停止後恢復真實 GPS。
11. 日後每次依正確次序開啟及停止；免費簽署約每 7 天覆蓋安裝一次。

## 1. 準備裝置與帳戶

### iPhone 要求

- iPhone 使用 iOS 17.4 或以上版本。
- iPhone 已設定鎖機密碼。
- 可在 iPhone 開啟 Developer Mode。
- 可安裝 App Store 的 LocalDevVPN。
- 第一次設定時可用 USB 線連接 Windows 電腦。
- 第一次下載 Personalized DDI 時要有網絡，下載量約 16 MB。

### Windows 電腦要求

- Windows 10 或 Windows 11，建議使用 64-bit 系統。
- 可安裝 iTunes、iCloud、Sideloadly 及 `idevice_pair`。
- 有可傳輸資料的 USB 線。只有充電功能的線不能使用。
- 第一次配對時，iPhone 要保持解鎖並停留在主畫面。

### Apple ID 要求

請使用你自己的 Apple ID。免費 Apple ID 已足夠，但簽署通常只有約 7 天有效期。付費 Apple Developer 帳戶通常可取得較長的簽署有效期，但不是本教學的必要條件。

不要把 Apple ID 密碼、雙重認證碼、App-specific password、憑證或 provisioning profile 交給 IPA 提供者或其他使用者。簽署應在你自己的電腦上完成。

## 2. 取得 GFlyer 安裝檔

你需要以下兩個檔案：

- `GFlyerIOS-Idevice-unsigned.ipa`
- `THIRD_PARTY_NOTICES.md`

只有名稱包含 `Idevice` 的版本才有全機定位後端。一般 Preview 版本只會在 App 內更新預覽座標，不能改變 Apple Maps 或其他 App 的位置。

### 方法 A：由 GitHub Actions 下載

1. 開啟 [GFlyer iOS repository](https://github.com/michaelcheung0125-svg/GFlyer_IOS)。
2. 登入有權讀取此 repository 的 GitHub 帳戶。
3. 點選 repository 上方的 **Actions**。
4. 在左側選擇 **macOS Xcode validation**。
5. 開啟最近一個兩個 job 都是綠色勾號的 workflow run。
6. 在頁面下方 **Artifacts** 區域，點選 `GFlyerIOS-Idevice-unsigned`。
7. 解壓縮下載的 ZIP。
8. 找出 `GFlyerIOS-Idevice-unsigned.ipa`。一般使用者不需要 `.xcarchive`。
9. 另外下載公開的 [THIRD_PARTY_NOTICES.md](https://michaelcheung0125-svg.github.io/GFlyer-updates/THIRD_PARTY_NOTICES.md)。

此 repository 的 workflow artifact 保留期目前是 14 天。若 Artifacts 區域沒有檔案，請由專案維護者重新執行 workflow，或向維護者取得同一版本的 unsigned IPA。

### 方法 B：由維護者直接取得

維護者可直接把未簽署的 `GFlyerIOS-Idevice-unsigned.ipa` 連同 `THIRD_PARTY_NOTICES.md` 提供給使用者。建議同時提供檔案版本、來源 commit 及 SHA-256，以便使用者確認檔案未被更換。

不要使用來歷不明、已被其他人簽署或被重新封裝的 IPA。其他人的已簽署 IPA 通常綁定對方帳戶或裝置，也不應包含在分享包內。

## 3. 在 Windows 安裝必要軟件

### 3.1 安裝 Apple 的 Windows 元件

Sideloadly 官方目前要求 Windows 使用 Apple 網站下載的 iTunes 及 iCloud，而不是 Microsoft Store 版本。

1. 若已安裝 Microsoft Store 版 iTunes 或 iCloud，先在 Windows「已安裝的應用程式」移除它們。
2. 由 Sideloadly 下載頁提供的 Apple 連結安裝 Web 版 iTunes 及 Web 版 iCloud。
3. 安裝完成後重新啟動 Windows。
4. 開啟 iTunes，把 iPhone 用 USB 接上電腦。
5. iPhone 出現「信任此電腦？」時按 **信任**，再輸入 iPhone 密碼。
6. 確認 iTunes 能看見 iPhone，才繼續下一步。

若 iTunes 看不見 iPhone，先更換 USB 插口或傳輸線，再重裝 Apple Mobile Device Support。`idevice_pair` 和 Sideloadly 都依賴這套 USB 驅動。

### 3.2 安裝 Sideloadly

1. 開啟 [Sideloadly 官方網站](https://sideloadly.io/)。
2. 下載 Windows 64-bit 版本；只有 32-bit Windows 才選 32-bit。
3. 完成安裝後開啟 Sideloadly。
4. 暫時不要移除 iTunes、iCloud 或 Apple 驅動。

### 3.3 下載 idevice_pair

1. 開啟 [`idevice_pair` 官方 repository](https://github.com/jkcoxson/idevice_pair)。
2. 下載 [Windows x86_64 最新版本](https://github.com/jkcoxson/idevice_pair/releases/latest/download/idevice_pair--windows-x86_64.exe)。
3. 將程式放在只有你本人可存取的資料夾。

`idevice_pair` 是跨平台的配對工具。本教學使用它建立 GFlyer 所需的 **Remote pairing（RPPairing）**檔案。

## 4. 用 Sideloadly 簽署及安裝 GFlyer

1. 解鎖 iPhone，以 USB 接上 Windows 電腦。
2. 若再次出現「信任此電腦？」提示，按 **信任**。
3. 開啟 Sideloadly。
4. 在 Device 欄選擇你的 iPhone。若清單是空白，先回到 iTunes 確認電腦能看見 iPhone。
5. 把 `GFlyerIOS-Idevice-unsigned.ipa` 拖到 Sideloadly 的 IPA 區域，或點選 IPA 圖示選取檔案。
6. 在 Apple ID 欄輸入你自己的 Apple ID 電郵地址。
7. 保持與第一次安裝相同的 App/Bundle ID 設定。除非你清楚原因，否則不要隨意啟用修改 Bundle ID 的選項。
8. 點 **Start** 開始簽署及安裝。
9. 按 Sideloadly 或 Apple 的提示完成登入及雙重認證。認證資料只應輸入你信任的本機 Sideloadly 流程。
10. 等候 Sideloadly 顯示完成，再查看 iPhone 主畫面是否出現 GFlyer。

首次側載時，Windows 防火牆或防毒軟件可能詢問是否允許 Sideloadly。只應允許從官方網站下載的程式，並核對檔案來源。

### 安裝完成但 App 打不開

先不要刪除 GFlyer。依次完成下一節的 Developer Mode 及開發者信任設定。若點 App 後立即顯示未受信任開發者，通常不是 IPA 壞掉，而是尚未信任個人簽署憑證。

## 5. 開啟 Developer Mode 及信任開發者

### 5.1 開啟 Developer Mode

1. 在 iPhone 開啟「設定」。
2. 進入「私隱與保安」。
3. 向下尋找「Developer Mode／開發者模式」。
4. 開啟 Developer Mode。
5. iPhone 會要求重新啟動，按提示重啟。
6. 解鎖後再次確認開啟 Developer Mode，並輸入 iPhone 密碼。

若看不到 Developer Mode，先確認 GFlyer 已透過 Sideloadly 安裝，然後重新連接電腦及重啟 iPhone。不同 iOS 語言的選單名稱可能略有差異。

### 5.2 信任個人開發者憑證

若 iPhone 顯示「未受信任的開發者」：

1. 開啟「設定」。
2. 進入「一般」。
3. 進入「VPN 與裝置管理」或相近名稱的裝置管理頁面。
4. 在「開發者 App」下選擇與你 Apple ID 對應的項目。
5. 點選「信任」，並再次確認。
6. 返回主畫面開啟 GFlyer。

正常使用裝置模式時，Developer Mode 應保持開啟。關閉 Developer Mode 後，GFlyer 可能無法啟動或無法連接裝置開發服務；重新開啟時通常要再次重啟 iPhone。

## 6. 確認安裝的是裝置模式

開啟 GFlyer 後，查看畫面左上方：

- 顯示「裝置模式」：正確，可繼續。
- 顯示「預覽模式」：安裝了錯誤版本，不能控制全機 GPS。

再點右上角齒輪進入「裝置設定」，確認：

- 「目前後端」不是 Preview backend。
- 「全機 GPS」顯示「可用」。
- LocalDevVPN 目標 IP 是 `10.7.0.1`。

若顯示預覽模式，重新取得並安裝 `GFlyerIOS-Idevice-unsigned.ipa`。不要使用由 `GFlyerIOS` Preview scheme 建立的 IPA。

## 7. 為自己的 iPhone 建立 Remote Pairing File

Pairing File 是這部 iPhone 對可信任電腦的配對憑證，內容具有敏感性。每部 iPhone 都要建立自己的檔案；不能從朋友的手機複製，也不能公開上傳。

1. 保持 iPhone 解鎖並停留在主畫面。
2. 以 USB 將 iPhone 接上已安裝 Apple 驅動的 Windows 電腦。
3. 若 iPhone 詢問是否信任電腦，按 **信任** 並輸入 iPhone 密碼。
4. 開啟 `idevice_pair--windows-x86_64.exe`。
5. 在裝置下拉清單選擇你的 iPhone。
6. 選擇 **Remote pairing**，不要選 `Lockdown`。
7. 點 **Create** 建立 RPPairing 檔案。
8. 建立後點 **Validate**。只有驗證成功才繼續。
9. 點 **Save to file...**，把檔案存到本機私人資料夾。
10. 保留原有副檔名。GFlyer 可匯入 `.mobiledevicepairing`、`.mobiledevicepair` 或 plist 格式。

Remote pairing 需要 iOS 17.4 或以上。若 Create 或 Validate 失敗：

- 確認 iPhone 已解鎖並在主畫面。
- 拔除再插入 USB，重新按信任。
- 確認 iTunes 能辨識 iPhone。
- 關閉其他正在佔用 iPhone USB 連線的工具。
- 重新建立一份新檔案，不要繼續使用驗證失敗的檔案。

不要把 Pairing File 放入公開 GitHub、網盤共享資料夾、群組聊天或電郵群發。電腦上的副本應存放在只有你本人可讀取的位置。

## 8. 把 Pairing File 傳到 iPhone

建議使用 [LocalSend](https://localsend.org/) 在同一個可信任的本地網絡內直接傳送：

1. 在 Windows 及 iPhone 安裝 LocalSend。
2. 讓兩部裝置連接同一個可信任 Wi-Fi。
3. 在 Windows LocalSend 選擇剛建立的 Pairing File。
4. 選擇你的 iPhone 作接收裝置。
5. 在 iPhone 接受檔案，並儲存到「檔案」App 的本機私人位置。
6. 傳送完成後，確認檔案名稱及副檔名沒有被聊天 App 改掉。

亦可使用 USB 檔案傳輸或其他端對端私人方式，但不要經公開下載連結或不受信任的中轉站。完成匯入後，可刪除 iPhone「下載項目」內多餘的明文副本；GFlyer 會把內容複製到自己的受保護儲存空間。

## 9. 在 GFlyer 匯入 Pairing File

1. 開啟 GFlyer。
2. 點右上角齒輪進入「裝置設定」。
3. 在「首次設定」查看 Pairing File 狀態。
4. 點「匯入 Pairing File」。
5. 在 iOS 檔案選擇器選取剛傳入的檔案。
6. 匯入後確認狀態由「未匯入」變成「已匯入」。

若顯示「匯入失敗」：

- 確認選取的是 `idevice_pair` 產生的 plist 配對檔，而不是 ZIP、捷徑或文字說明。
- 確認檔案沒有被重新命名成 `.txt`。
- 回到 `idevice_pair` 使用 **Remote pairing** 重新 Create 及 Validate。
- 不要在未查明原因前按「移除 Pairing File」；先保留可用副本。

## 10. 安裝及設定 LocalDevVPN

1. 在 iPhone App Store 安裝 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)。
2. 開啟 LocalDevVPN。
3. 首次使用時，允許 iOS 加入 VPN 設定。
4. 將裝置／目標 IP 保持為 GFlyer 預設使用的 `10.7.0.1`。如 App 顯示多個網絡欄位，除非維護者另有指定，先保留其預設值。
5. 點選連接，確認 iPhone 狀態列或控制中心顯示 VPN 已開啟。
6. 返回 GFlyer，在「裝置設定」確認目標 IP 同樣是 `10.7.0.1`。

iOS 同一時間通常只能使用一個主要 VPN。使用 GFlyer 時，其他廣告攔截、公司、WireGuard、Tailscale 或私人 VPN 可能與 LocalDevVPN 衝突。若連接失敗，先暫停其他 VPN，再開 LocalDevVPN。

LocalDevVPN 建立的是裝置內的本地開發通道。它不是用來改變上網地區的傳統 VPN。

## 11. 第一次全機定位測試

第一次測試只做單點，不要立即測長路線。

### 11.1 傳送第一個位置

1. 確認 Developer Mode 已開啟。
2. 確認 GFlyer 已顯示「裝置模式」及 Pairing File「已匯入」。
3. 先開啟 LocalDevVPN，確認 VPN 已連接。
4. 返回 GFlyer。
5. 在底部模式選擇「傳送」。
6. 在地圖點選一個容易辨認的位置。
7. 點「開始」。
8. 第一次裝置模式會下載約 16 MB 的 Personalized Developer Disk Image（DDI），並作 SHA-256 驗證。保持 GFlyer 在前景並等待完成，不要切斷網絡或 VPN。
9. GFlyer 顯示「裝置定位模擬中」後，開啟 Apple Maps。
10. 等候定位更新，確認 Apple Maps 的藍點移到選取位置。

DDI 正常情況只需下載一次，會保留在 App 的 Application Support。每 7 天重新簽署不代表每次都要重新下載 DDI；但若刪除 App、App 資料被清除或版本要求改變，便可能要重新下載。

### 11.2 傳送第二個位置

1. 返回 GFlyer，但不要關閉 LocalDevVPN。
2. 在地圖選另一個明顯不同的位置。
3. 再按「開始」。
4. 返回 Apple Maps，確認藍點更新到第二個位置。

第二次成功代表現有連線可重用，不只是第一次偶然成功。

### 11.3 停止並恢復真實 GPS

1. 返回 GFlyer。
2. 按底部的停止方形按鈕。
3. 等候狀態顯示「已清除模擬位置」。
4. 開啟 Apple Maps，確認位置逐步恢復到真實位置。
5. 確認恢復後，才返回 LocalDevVPN 並關閉 VPN。

不要直接先關 LocalDevVPN。GFlyer 需要通道仍然存在，才能呼叫清除定位服務。

如果曾強制關閉 GFlyer、重啟 iPhone，或 Apple Maps 仍停留在模擬位置：先開 LocalDevVPN，再開 GFlyer 的「裝置設定」，點「強制清除模擬定位」。

## 12. 日常使用方法

每次正常使用都遵守以下次序：

1. 確認 Developer Mode 保持開啟。
2. 開啟 LocalDevVPN 並連接。
3. 開啟 GFlyer。
4. 選擇位置或設定路線。
5. 按「開始」。
6. 使用完成後回到 GFlyer，按停止方形按鈕。
7. 確認顯示「已清除模擬位置」。
8. 最後才關閉 LocalDevVPN。

簡記：

```text
LocalDevVPN 開 -> GFlyer 開始 -> GFlyer 停止/清除 -> LocalDevVPN 關
```

### 傳送模式

1. 在模式選擇「傳送」。
2. 點地圖選取位置。
3. 按「開始」。
4. 要改位置時，點另一處再按「開始」。

### 路線模式

完成單點硬性測試後才使用路線：

1. 在模式選擇「路線」。
2. 依行走次序點選至少兩個地圖位置。
3. 用倒轉箭嘴移除最後一個點，或用垃圾桶清除整條路線。
4. 設定速度，範圍為 1 至 50 km/h。
5. 如要重複，開啟「循環路線」。
6. 選擇「走回起點」或「直接返回」。
7. 按「開始」。可使用暫停及繼續按鈕。

目前應以 GFlyer 保持在前景的路線播放為準。iOS 可能暫停背景 App，因此不要假設鎖屏或長時間切到其他 App 後路線仍會持續。

## 13. 免費 Apple ID 每 7 天重新簽署

免費簽署一般約 7 天後到期。這是 Apple 的簽署期限，不代表 GFlyer 每 7 天有新版本，也不代表要重新編譯 IPA。

建議在第 5 或第 6 天主動覆蓋安裝，避免到期後臨時不能開啟。

### 手動覆蓋安裝步驟

1. 不要刪除 iPhone 上現有的 GFlyer。
2. 使用第一次安裝時的同一部電腦、同一個 Apple ID 及同一份 IPA。
3. 以 USB 連接 iPhone，解鎖並按需要信任電腦。
4. 開啟 Sideloadly。
5. 選擇同一部 iPhone。
6. 載入原本的 `GFlyerIOS-Idevice-unsigned.ipa`。
7. 輸入與第一次相同的 Apple ID。
8. 保持與第一次相同的 Bundle ID／進階設定。
9. 點 **Start**，讓 Sideloadly 重新簽署並覆蓋安裝。
10. 完成後拔線，開啟 GFlyer，確認仍是「裝置模式」。
11. 進入「裝置設定」，確認 Pairing File 仍顯示「已匯入」。
12. 開 LocalDevVPN，做一次短距離單點開始及停止測試。

覆蓋安裝通常可保留 GFlyer 的 Pairing File、DDI 及設定，但不能把它視為唯一備份。電腦上仍應安全保存自己的 Remote Pairing File；它不可分享給其他人。

### 何時才需要重新下載或重建 IPA

以下情況才需要新的 IPA：

- 專案維護者發布了修正或新功能。
- 新 iOS 版本令現有程式、DDI 或 `idevice` 協定不相容。
- 現有 IPA 損壞，或來源無法驗證。
- 維護者明確通知舊版本停止使用。

單純簽署到期只需重新簽署，不需重新執行 GitHub Actions，也不需每週重建。

### Sideloadly 自動刷新

Sideloadly 提供自動刷新功能，但是否成功取決於電腦是否開機、iPhone 與電腦能否連線、Apple 驅動、同一網絡及 Sideloadly 設定。首次使用建議先掌握 USB 手動覆蓋流程；自動刷新失敗時仍可用上述方法處理。

## 14. 把同一份 IPA 給其他使用者

可以把同一份 `GFlyerIOS-Idevice-unsigned.ipa` 給多位使用者重複簽署。unsigned IPA 本身不會在 7 天後過期；到期的是每位使用者自己產生的簽署。

每位使用者必須各自完成：

1. 在自己的 Windows 或 Mac 安裝 Sideloadly 及 Apple 驅動。
2. 使用自己的 Apple ID 簽署 IPA。
3. 把 App 安裝到自己的 iPhone。
4. 在自己的 iPhone 開啟 Developer Mode。
5. 用 `idevice_pair` 為自己的 iPhone 建立 Remote Pairing File。
6. 把自己的 Pairing File 匯入自己的 GFlyer。
7. 在自己的 iPhone 安裝及開啟 LocalDevVPN。
8. 約每 7 天用自己的帳戶重新簽署。

可以共用：

- 未簽署的 GFlyer IPA。
- 本教學。
- `THIRD_PARTY_NOTICES.md`。
- 公開的工具下載連結。

絕對不要共用：

- Apple ID 密碼或雙重認證碼。
- 已簽署 IPA、Apple 憑證、私密金鑰或 provisioning profile。
- Pairing File。
- iPhone 裝置識別資料或含敏感內容的完整紀錄。

若維護者重新封裝或分發 GFlyer，應同時附上 `THIRD_PARTY_NOTICES.md`，保留 `idevice` 的 MIT 授權聲明。

## 15. 更新 iOS、重新啟動或異常關閉後

### iPhone 重新啟動後

1. 確認 Developer Mode 仍然開啟。
2. 開啟 LocalDevVPN。
3. 開啟 GFlyer。
4. 先做單點開始及停止測試。

一般重啟不應刪除 Pairing File，但 VPN 需要重新連接。

### iOS 更新後

iOS 更新可能令 Pairing File、Personalized DDI 或 Apple 私有開發協定失效。更新後應依以下次序檢查：

1. 確認 GFlyer 簽署未過期。
2. 確認 Developer Mode 仍開啟。
3. 確認 LocalDevVPN 可連接。
4. 做一次單點定位。
5. 若出現 pairing 或 tunnel 類錯誤，用 `idevice_pair` 重新建立及 Validate Remote Pairing File，再匯入 GFlyer。
6. 若出現 DDI 下載、驗證或掛載錯誤，先不要反覆刪除 App；記錄 iOS 版本及完整錯誤文字，交給維護者判斷是否需要新版 IPA。

### GFlyer 被強制關閉後

若模擬位置仍未清除：

1. 開啟 LocalDevVPN。
2. 開啟 GFlyer。
3. 進入「裝置設定」。
4. 點「強制清除模擬定位」。
5. 用 Apple Maps 確認真實 GPS 恢復。
6. 最後才關閉 LocalDevVPN。

## 16. 故障排除

請先找出失敗階段，不要一次刪除所有東西。記錄 iPhone 型號、iOS 版本、GFlyer 版本、LocalDevVPN 版本及畫面上的完整錯誤文字，但不要公開 Pairing File 內容或 Apple 帳戶資料。

### Sideloadly 看不到 iPhone

- 解鎖 iPhone，重新插入 USB。
- 在 iPhone 重新按「信任此電腦」。
- 用 iTunes 確認 Apple 驅動是否正常。
- 更換可傳輸資料的 USB 線及 USB 插口。
- 移除 Microsoft Store 版 iTunes/iCloud，改用 Sideloadly 指示的 Web 版。
- 重啟 Apple Mobile Device Service 或重新啟動 Windows。

### IPA 安裝失敗

- 確認 IPA 是完整的 `GFlyerIOS-Idevice-unsigned.ipa`，不是仍包在 artifact ZIP 內。
- 確認 Apple ID 可登入及完成雙重認證。
- 免費帳戶可能受 Apple 的側載 App 或 App ID 限制；先移除不再使用的其他側載 App，再重試。
- 若是重新簽署，保持同一 Apple ID 及 Bundle ID 設定。
- 不要改用別人已簽署的 IPA。

### App 顯示預覽模式

- 安裝了錯誤 scheme 的版本。
- 重新取得 `GFlyerIOS-Idevice-unsigned.ipa` 並覆蓋安裝。
- 在「裝置設定」確認「全機 GPS」顯示「可用」。

### Pairing File 無法建立或驗證

- iPhone 要解鎖並停在主畫面。
- iPhone 必須已信任這部電腦。
- 確認 iOS 為 17.4 或以上。
- 在 `idevice_pair` 選 **Remote pairing**，不要選 `Lockdown`。
- Create 後必須 Validate 成功。
- iOS 更新後建立全新檔案。

### Pairing File 無法匯入

- 確認它是有效 plist，而不是 ZIP、HTML 或 `.txt`。
- 保留 `.mobiledevicepairing`、`.mobiledevicepair` 或 plist 副檔名。
- 重新用 LocalSend 傳送，避免聊天 App 改名。
- 重新 Create 及 Validate，不要使用其他 iPhone 的檔案。

### 顯示 LocalDevVPN 目標 IP 無效

- GFlyer「裝置設定」的目標 IP 應填 `10.7.0.1`。
- 不要加入 `http://`、連接埠、空格或其他文字。

### Tunnel／連線失敗

- 確認 LocalDevVPN 已連接，而不是只開啟了 App。
- 暫停其他 VPN、廣告攔截或企業網絡工具。
- 確認 GFlyer 與 LocalDevVPN 都使用 `10.7.0.1`。
- 關閉 LocalDevVPN，重新連接後再開 GFlyer。
- 若剛更新 iOS，重新建立 Remote Pairing File。

### DDI 下載失敗

- 確認 iPhone 可上網。
- 保持 GFlyer 在前景，不要鎖屏。
- 確認有足夠儲存空間。
- 稍後再試；若固定顯示下載網址或伺服器錯誤，向維護者報告。

### DDI SHA-256 驗證失敗

- 不要略過驗證，也不要自行放入其他來源的 DDI。
- 重新嘗試下載一次。
- 若持續失敗，記錄錯誤及 iOS 版本，等待維護者修正 pinned 檔案或發布新版。

### 開始後 Apple Maps 沒有移動

- 確認 GFlyer 顯示「裝置定位模擬中」，不是預覽模式。
- 確認 Apple Maps 的定位權限已開啟。
- 等候數秒讓 Apple Maps 更新，必要時重新開啟 Maps。
- 回到 GFlyer 選第二個位置再測試。
- 若 GFlyer 有錯誤提示，按 pairing、tunnel、DDI、RemoteXPC 或 location set 階段處理。

### 停止後仍然是假位置

1. 不要先關 LocalDevVPN。
2. 回到 GFlyer 再按停止。
3. 若 App 曾重啟，使用「裝置設定」內的「強制清除模擬定位」。
4. 開 Apple Maps 等候真實 GPS 恢復。
5. 成功後才關閉 LocalDevVPN。

### 7 天後 App 打不開

- 這通常是免費簽署到期，不是 Pairing File 到期。
- 不要先刪除 App。
- 用同一 Apple ID、同一 IPA 及同一 Bundle ID 設定在 Sideloadly 覆蓋安裝。
- 完成後檢查 Pairing File 是否仍在，再做短距離開始及停止測試。

## 17. 安全及私隱規則

- 只從可信任來源取得 IPA、Sideloadly、LocalDevVPN、LocalSend 及 `idevice_pair`。
- 每個人只在自己的電腦輸入自己的 Apple ID 認證資料。
- Pairing File 視同裝置憑證，不公開、不群發、不交給 IPA 維護者。
- 不把 Apple 私密金鑰、provisioning profile、DDI 二進位檔或配對檔提交到 GitHub。
- 不使用來歷不明的「永久簽署」服務上傳 Apple 帳戶或裝置資料。
- 停止模擬後要用 Apple Maps 確認真實 GPS 已恢復。
- 不依賴 GFlyer 規避第三方 App 的模擬定位檢查。
- 分發 IPA 時保留 `THIRD_PARTY_NOTICES.md`。

## 18. 已知限制

- 這種全機定位模擬依賴 Apple 開發者服務，不適合 App Store 發布。
- iOS 更新可能令 pairing、DDI 或私人協定暫時失效。
- 免費 Apple ID 通常約 7 天要重新簽署。
- iOS 可能暫停背景中的 GFlyer，路線模式目前以 App 保持前景為準。
- LocalDevVPN 可能與其他 VPN 衝突。
- 地圖圖磚及首次 DDI 下載需要網絡。
- 第三方 App 可拒絕模擬位置，並可按其服務條款限制帳戶。
- GFlyer 停止前若先中斷 VPN，清除定位可能失敗。

## 19. 完成檢查表

首次設定完成後，應全部答「是」：

- [ ] 使用自己的 Apple ID 成功簽署及安裝。
- [ ] Developer Mode 已開啟。
- [ ] GFlyer 顯示「裝置模式」。
- [ ] `idevice_pair` Remote pairing Create 及 Validate 成功。
- [ ] Pairing File 已匯入，狀態顯示「已匯入」。
- [ ] LocalDevVPN 已連接，IP 是 `10.7.0.1`。
- [ ] Personalized DDI 成功下載及驗證。
- [ ] Apple Maps 顯示第一個模擬位置。
- [ ] 第二個位置可正常更新。
- [ ] GFlyer 停止後 Apple Maps 恢復真實 GPS。
- [ ] 拔掉電腦後仍可重複開始及停止。
- [ ] 已記下免費簽署的下一次刷新日期。
- [ ] Pairing File 及 Apple 認證資料沒有分享給其他人。

## 20. 官方及專案連結

- [GFlyer iOS repository](https://github.com/michaelcheung0125-svg/GFlyer_IOS)
- [Sideloadly](https://sideloadly.io/)
- [`idevice_pair`](https://github.com/jkcoxson/idevice_pair)
- [LocalDevVPN App Store](https://apps.apple.com/us/app/localdevvpn/id6755608044)
- [LocalSend](https://localsend.org/)
- [GitHub：下載 workflow artifacts](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/downloading-workflow-artifacts)
- [Apple：Developer Mode 文件](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [第三方授權聲明](https://michaelcheung0125-svg.github.io/GFlyer-updates/THIRD_PARTY_NOTICES.md)
