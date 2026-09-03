# 疑難排除案例紀錄

這份文件記錄**實際發生過並且已經解決**的問題，供日後撰寫正式疑難排除文件時
取用。每個案例都保留：症狀、確切錯誤訊息、根本原因、有效解法，以及**試過但
無效的做法**——後者往往比解法更省時間，因為它讓人不必重走冤枉路。

只記錄真正驗證過的案例。推測或未確認的請勿寫入。

---

## 案例 1 · SideStore 找不到裝置 UDID

**日期**：2026-09-03 ～ 09-04
**驗證狀態**：✅ 實機確認解決

### 症狀

- App 內按更新後，SideStore 失敗並顯示
  `SideStore could not determine this device's UDID. Please replace your pairing using iloader.`
- SideStore 的 **Settings → Health Check** 依序顯示過兩種訊息：
  - `Pairing file: Loaded (Connection down)`
  - `InvalidPairing (protocol: rppairing, reason: RPPairing UDID not found)`
- 前幾天同樣的設定可以正常自動更新，中間沒有刻意改過任何設定

### 根本原因

**SideStore 讀取的是它自己 App 容器裡的那份配對檔，不是使用者手動匯入或
另外存在電腦／「檔案」App 裡的那一份。**

用 iloader 重新產生配對檔並不會更新容器裡的舊檔案，所以 SideStore 一直在讀
一份無法解析出 UDID 的舊配對。

### 解法

在 iloader 完成配對之後，點 **Manage Pairing File → Place in All Apps**
（或指定放到 SideStore 旁邊），把配對檔實際寫入 App 容器。

完整流程：

1. 電腦先開一次 iTunes，確認看得到 iPhone
2. iPhone 接電腦、解鎖，按畫面上的**信任**
3. iloader 登入 Apple ID，按 **Refresh** 認到裝置
4. 完成配對
5. **Manage Pairing File → Place in All Apps** ← 關鍵步驟
6. 開 LocalDevVPN，回 SideStore 重新整理

### 試過但無效

以下全部做過，問題依舊：

- 重新啟動 iPhone（多次）
- 用 idevice_pair 重新產生配對檔並匯入
- 重新安裝 SideStore
- 把 LocalDevVPN 的 Tunnel IP 改回 `10.7.0.0/32`
- 更換 Anisette 伺服器
- 確認 iloader 已是最新版（2.3.1，非版本過舊問題）

### 判讀要點

Health Check 的兩種訊息指向**不同層**，解法完全不同：

| Health Check 訊息 | 問題層 | 方向 |
|---|---|---|
| `Loaded (Connection down)` | VPN／通道 | 檢查 LocalDevVPN 連線與 Tunnel IP |
| `RPPairing UDID not found` | 配對檔位置 | 用 Place in All Apps 寫入容器 |

**看到 UDID 字樣不要直接去重新產生配對檔**——那通常不是原因。

---

## 案例 2 · LocalDevVPN 1.3 改變 Tunnel IP

**日期**：2026-09-03
**驗證狀態**：⚠️ 社群回報確認，本機未成為主因

### 症狀

- 更新 LocalDevVPN 之後突然無法重新整理
- SideStore 表示未連接 VPN，但 LocalDevVPN 顯示已連線
- Health Check 顯示 `Loaded (Connection down)`，或
  `InvalidVPN: VPN tunnel iface is up and tunnel peer IP 10.7.1.2 is known, but TCP port poll failed`

### 根本原因

LocalDevVPN **1.3** 把 Tunnel IP 從 `10.7.0.0/32` 改成 `10.7.1.1/32`，
與 SideStore 預期的位址不一致。

### 解法

擇一：

- 在 LocalDevVPN 把 Tunnel IP 改回 `10.7.0.0/32`（Device IP 維持 `10.7.0.1`）
- 或直接刪除 LocalDevVPN 重新安裝，讓它帶入正確設定（SideStore 維護者建議）

### 備註

多位使用者在 2026-09-03 前後同時回報，時間點一致。若你的 Tunnel IP 顯示
`10.7.1.1`，代表你在 1.3 版之後。

---

## 案例 3 · SideStore 安裝／更新一直轉圈

**日期**：2026-09-01
**驗證狀態**：✅ 實機確認解決

### 症狀

安裝或更新時進度圈一直轉，沒有任何錯誤訊息，長時間沒有反應。

### 根本原因

**LocalDevVPN 被 iOS 終止了。** iOS 會在記憶體壓力下或重開機後自行關閉 VPN
extension，而 SideStore 在 VPN 斷線時**不會報錯，只會一直轉圈**。

### 解法

重新連接 LocalDevVPN 再試。

### 備註

- 這會反覆發生，不是一次修好就永久
- SideStore 另有一個已知畫面問題：轉圈凍住但安裝其實仍在背景進行，
  切到主畫面可以讓它完成
- 判斷是否真的裝好，看 GFlyer 的**設定 → 關於 → App 版本**比看轉圈可靠

---

## 案例 4 · 停止模擬後其他 App 仍顯示模擬位置

**日期**：2026-09-01 ～ 09-02
**驗證狀態**：✅ 實機確認

### 症狀

GFlyer 顯示已清除模擬位置，但 Google 地圖等其他 App 仍停在模擬位置。

### 根本原因

**iOS 會沿用快取的最後已知定位，直到取得新的真實定位為止。** 即使關閉了
模擬 session 也一樣——這不是 App 能控制的。

### 解法

1. GFlyer **設定 → 恢復 → 完整清除模擬定位**（會清除、關閉模擬 session
   並自動驗證目前定位）
2. 若驗證顯示仍是模擬座標：關閉 LocalDevVPN，然後**開關一次飛行模式**

實機確認：**開關飛行模式是必要的**，其他 App 才會回到真實位置。

### 備註

一般的「停止」不做 session 拆除（保留通道，蜂窩網路下次開始比較快），
訊息也不宣稱已恢復真實定位。要還原給其他 App 用時才用「完整清除」。

飛行模式在另一個地方也有影響：行動網絡下**先開飛行模式再建立模擬**成功率
明顯較高。0.6.0 起地圖工具列有「飛航模式輔助」會偵測網絡並引導這串操作，
細節見 [SHORTCUTS.md](SHORTCUTS.md)。

---

## 案例 5 · 按更新後 SideStore 清單沒顯示更新，但 App 已是新版

**日期**：2026-09-01
**驗證狀態**：✅ 實機確認為正常行為

### 症狀

在 GFlyer 按「用 SideStore 更新」後，SideStore 的 My Apps 清單沒有顯示待更新，
但回到 GFlyer 發現版本已經變新。

### 說明

**這是正常的。** GFlyer 用的是 `sidestore://install?url=` 深連結，會叫
SideStore **直接從該網址安裝**，不會排進「有更新」清單。

判斷成功與否看 GFlyer 的**設定 → 關於 → App 版本**即可。

---

## 案例 6 · 加入來源顯示 StoreApp is not valid

**日期**：2026-09-01
**驗證狀態**：✅ 修正後實機確認

### 症狀

在 SideStore 加入 GFlyer 來源時顯示 `Failed to install / StoreApp is not valid`。

### 根本原因

來源檔寫成了 AltStore 2.0 的新格式（只有 `versions` 陣列），但 **SideStore
讀的是舊版扁平格式**。

### 解法

來源檔必須具備：

- 頂層 `identifier`
- App 物件上的扁平欄位 `version`、`versionDate`、`downloadURL`、`size`
  （與 `versions[0]` 重複是正常的，SideStore 只看扁平欄位）
- `permissions` 為陣列（新格式的 `appPermissions` 物件不會被讀取）
- 日期為 ISO-8601 帶時間，只寫日期會失敗

`scripts/update_altstore_source.py` 會自動維護這些欄位，正常發佈流程不需要
手動處理。

### 備註

SideStore 會快取來源內容。改過來源檔後若沒看到新版，把來源移除再重新加入。

---

## 撰寫正式疑難排除文件時的建議

1. **依症狀而非依原因分類**——使用者只知道自己看到什麼，不知道哪一層壞了
2. **保留確切錯誤訊息原文**，方便搜尋比對
3. **列出無效的嘗試**，價值不亞於解法
4. **標示驗證狀態**，區分實機確認與社群回報
5. 有分層診斷工具時（例如 SideStore 的 Health Check），先教怎麼判讀，
   再給對應解法，比讓人逐項亂試有效率得多
