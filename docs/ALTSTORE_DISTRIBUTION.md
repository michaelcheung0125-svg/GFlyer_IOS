# 用 AltStore / SideStore 安裝與更新 GFlyer iOS

這份文件說明如何改用 AltStore 或 SideStore 安裝 GFlyer iOS，以及如何維護
自動更新用的 AltStore 來源（AltSource）。

## 為什麼要換

Sideloadly 每次安裝都要接電腦。AltStore 與 SideStore 是常駐在 iPhone 上的
安裝器：它們會用你的 Apple ID 重新簽名，並在來源有新版時直接在 App 內
更新。SideStore 更進一步，可以在裝置上自行重簽，不需要電腦。

這不會改變簽名期限。免費 Apple ID 的 provisioning profile 仍然是 7 天，
AltStore / SideStore 只是把「每 7 天重簽一次」變成自動執行。

## 兩者的差別

| | AltStore | SideStore |
|---|---|---|
| 首次安裝 | 需要電腦執行 AltServer | 需要電腦產生 pairing file |
| 之後重簽 | 電腦與 iPhone 在同一個 Wi-Fi 時自動 | 在 iPhone 上自行完成 |
| 額外需求 | AltServer 常駐 | pairing file 與本機 VPN |

GFlyer 的裝置模式本來就需要 pairing file 與 LocalDevVPN，所以 SideStore
需要的東西你已經有了，不需要再讓電腦常駐。兩者使用同一種來源格式，下面
建立的來源檔對兩者都適用。

## 安裝 SideStore

SideStore 目前的官方安裝流程用 **iloader** 與 **LocalDevVPN**，正好是 GFlyer
裝置模式已經需要的兩樣工具，所以不會多裝新東西。

1. iPhone 用 USB 接上電腦並解鎖，開啟 iloader。
2. 在 iloader 登入 Apple ID，按「重新整理裝置」（`Refresh Devices`）後選擇這部裝置。
3. 在「安裝程式」（`Installers`）的「揀版本」（`Choose a build`）選
   **SideStore（夜晚版）**（`SideStore (Nightly)`）。新 iOS 需要的修正通常先進
   夜晚版，穩定版有時落後幾個月；代價是官方不受理夜晚版的問題回報。四個選項中
   帶 LiveContainer 的兩個 GFlyer 用不到。iloader 會依序跑「下載 SideStore」→
   「簽署同安裝 SideStore」→「放入配對檔案」，最後一步會自動把配對檔寫進
   SideStore 容器，預防下面那個 UDID 故障。
4. iPhone 上到**設定 → 一般 → VPN 與裝置管理**，信任「開發者 App」下的
   Apple ID。iOS 18 以上確認時會順帶重新啟動裝置。
5. iOS 16.1 以上需要開啟**設定 → 隱私權與安全性 → 開發者模式**。
6. 開啟 LocalDevVPN 並連線。
7. 開啟 SideStore 登入 Apple ID，點畫面上的 **7 DAYS** 計數器做一次重簽，
   確認流程正常。

之後 SideStore 就能在 iPhone 上自行重簽，不需要再接電腦。若登入時出現
anisette 相關錯誤，到 SideStore 的設定換一個 Anisette 伺服器再試。

裝了夜晚版之後，在 SideStore 設定開啟 beta 更新並選 `nightly`，新的夜晚版就會
直接在 SideStore 內出現，不用再接電腦。夜晚版不穩時，用同一個 iloader 改揀
**SideStore（穩定版）** 重裝即可；資料一般會保留，但官方不保證，改之前先在
GFlyer 匯出備份檔。

## 安裝 GFlyer

加入來源之後直接在 SideStore 裡安裝：

1. SideStore → **Browse → Sources → +**
2. 貼上 `https://michaelcheung0125-svg.github.io/GFlyer-updates/altstore.json`
3. 在來源裡選 GFlyer 安裝

也可以用未簽名的 IPA 手動安裝：下載 release 資產或 CI artifact，傳到
iPhone 的「檔案」App，在 SideStore 選 **My Apps → +** 挑該檔案。

換用 SideStore 安裝前，先在 GFlyer 的**設定 → 資料匯入與匯出 → 匯出備份檔**
備份收藏與路線。簽名身分改變時 iOS 會視為不同的 App，舊資料不會保留；
pairing file 需要重新匯入，留言板也要用邀請碼重新加入。

## App 內更新提示

GFlyer 會讀取同一份 `altstore.json` 比對版本，有新版時提示，並把安裝交給
SideStore 的 `sidestore://install?url=` 連結。App 自己不會、也無法安裝 IPA。

- 回到前景時最多每 6 小時自動檢查一次
- **設定 → 軟體更新**可以手動檢查，也有一鍵把來源加入 SideStore 的按鈕
- 提示可以選「今日不再顯示」

更新來源網址存在 `Info.plist` 的 `GFlyerUpdateSourceURL`；`canOpenURL` 需要
`LSApplicationQueriesSchemes` 宣告 `sidestore` 與 `altstore`，兩者都已設定。

## 自動更新來源

來源檔放在公開的 `GFlyer-updates` repository，和 Android 的 `latest.json`
同一個位置：

```text
https://michaelcheung0125-svg.github.io/GFlyer-updates/altstore.json
```

在 AltStore / SideStore 的 **Browse → Sources → +** 加入這個網址之後，新版
會出現在 App 內，一鍵更新。

IPA 必須放在**公開**的網址上才抓得到。`GFlyer_IOS` 是私有 repository，它的
release 與 Actions artifact 都需要登入，所以 iOS 的 IPA 和 Android 的 APK
一樣，發佈到公開的 `GFlyer-updates` releases。

## 發佈新版的流程

完整步驟（升版、CI、拆 IPA 驗證、release、來源檔、線上驗證、文件記錄）
統一寫在 [docs/RELEASE_PROCESS.md](RELEASE_PROCESS.md)——那是唯一的正式
發佈 runbook，程式碼改動要交付時照著走。本文件保留 SideStore 安裝教學、
來源檔格式與疑難排解。

## 安裝或更新卡在轉圈

SideStore 需要 LocalDevVPN 連線才能安裝，**VPN 斷掉時它不會報錯，而是一直
轉圈**。iOS 會在記憶體壓力下或重開機後自行終止 VPN extension，所以這個狀況
會反覆出現：實測就遇過一次 LocalDevVPN 被 iOS 殺掉，導致更新一直卡住。

卡住時先確認 LocalDevVPN 仍然連線（順手強制關閉 GFlyer，它的裝置模式用同
一條通道），再依序嘗試 SideStore 官方的排查步驟：重啟 SideStore、清除快取、
更換 Anisette 伺服器、重啟裝置、重新產生 pairing file。

SideStore 另有一個已知的畫面問題：進度轉圈凍住但安裝仍在背景進行，切到主
畫面可以讓它完成。判斷是否真的裝好，看 GFlyer 的**設定 → 關於 → App 版本**
比看轉圈可靠。

> 完整的案例紀錄（含試過但無效的做法）見
> [TROUBLESHOOTING_CASES.md](TROUBLESHOOTING_CASES.md)。

## 配對與 UDID 問題（實測記錄）

`SideStore could not determine this device's UDID`／Health Check 顯示
`InvalidPairing (protocol: rppairing, reason: RPPairing UDID not found)`：

**SideStore 讀的是它自己容器裡的配對檔，不是使用者手動匯入的那一份。**
用 iloader 重新配對之後，必須點 **Manage Pairing File（管理配對檔案）→ Place In All Apps**
（或指定放到 SideStore 旁邊）把檔案寫進 App 容器；只按 Load／Install 不會
更新容器裡的舊檔案。實測確認這一步才是解法——重開機、重新產生配對檔、
重裝 SideStore、改 Tunnel IP 全部無效。

相關但不同的另一個狀況：LocalDevVPN **1.3** 把 Tunnel IP 從 `10.7.0.0/32`
改成 `10.7.1.1/32`，與 SideStore 對不上時 Health Check 會顯示
`Loaded (Connection down)`。改回 `10.7.0.0/32` 或刪除 LocalDevVPN 重裝即可。

診斷順序：Health Check 的訊息會區分這兩層——`Connection down` 指向 VPN／
通道，`RPPairing UDID not found` 指向配對檔沒放進容器。不要看到 UDID 字樣
就直接重新產生配對檔，那通常不是原因。

## 來源檔格式（不要簡化掉重複欄位）

SideStore 讀的是舊版 AltStore 來源格式，**不是**只有 `versions` 陣列的新
格式。少了下面任何一項，加入來源時會出現 `Failed to install / StoreApp is
not valid`：

- 頂層 `identifier`
- App 物件上的扁平欄位 `version`、`versionDate`、`downloadURL`、`size`
  （與 `versions[0]` 重複是正常的，SideStore 只看扁平欄位）
- `permissions` 必須是陣列；新格式的 `appPermissions` 物件不會被讀取
- 日期要用 ISO-8601 帶時間，例如 `2026-09-01T15:40:00Z`；只寫日期會失敗

`scripts/update_altstore_source.py` 會在每次發佈時自動把扁平欄位同步成最新
版本，所以正常流程不需要手動維護。要改格式前，先抓一份實際可用的來源
（例如 `https://apps.sidestore.io`）比對欄位，不要只依文件推測。

SideStore 會快取來源內容。改過來源檔後若沒看到新版，把來源移除再重新加入。

## 注意事項

- 每次改動 Swift 程式碼都需要新的 IPA。座標圖鑑與留言板是 HTTPS 抓取的
  資料，改資料不需要重新發佈 App。
- 免費 Apple ID 同時只能側載 3 個 App，AltStore / SideStore 本身佔一個。
- 來源檔與 IPA 都是公開的。IPA 未經簽名，其他人仍然需要用自己的 Apple ID
  才能安裝，你的簽名身分不會包含在裡面。
- `altstore.json` 的 `sha256` 只是給人核對用，AltStore 不會強制驗證；真正
  的完整性保證來自 HTTPS 與 GitHub release。
