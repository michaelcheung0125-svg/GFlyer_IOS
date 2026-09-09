# GFlyer iOS — 專案簡介與使用教學

> 給第一次接觸這個專案的人：5 分鐘了解它是什麼、能做什麼、怎麼用。

## 一、這是什麼？

GFlyer iOS 是一個**個人側載（不上架 App Store）的 iPhone App**，可以在**不越獄**的前提下，模擬整部手機的 GPS 位置。地圖 App（如 Apple Maps）、以及其他讀取系統定位的 App，都會看到你設定的假位置。

它與 Android 版 GFlyer（`C:\Project\GFlyer`）是兩個獨立專案。Android 有系統級的「模擬位置」功能，iOS 沒有公開 API，所以這個專案改走 Apple 開發者服務的私有協定（CoreDevice / RemoteXPC 的 `location_simulation_set`），這也是它需要設定 Pairing File 與 VPN 的原因。

核心原理（簡化）：

```
匯入 Pairing File → 連 LocalDevVPN（10.7.0.1:49152）
→ 建立 CoreDevice 通道 → 首次下載並驗證 Personalized DDI
→ 透過 RemoteXPC 呼叫 location_simulation_set / clear
```

### 重要限制

- **個人使用**：以個人 Apple ID 簽署，7 天後 App 會無法開啟，需重簽。
- **正常使用不需接電腦**：只有初次安裝、產生 Pairing File、重簽時需要電腦。
- iOS 系統更新可能使 Pairing File / DDI / 私有協定失效，屆時需重新設定。
- 本專案**不含反偵測功能**、不修改任何第三方 App；第三方 App 仍可能自行拒絕模擬位置。
- Pairing File 內含憑證，等於電腦對這支手機的信任憑證，**必須保密**。

## 二、App 功能一覽

| 功能 | 說明 |
|---|---|
| 地圖主畫面 | MapKit 地圖，點選地點、搜尋地址或座標、顯示目前位置 |
| 四種模擬模式 | **傳送**（直接跳到定點）、**單點**、**多點路線**、**螺旋探索**（繞定點盤旋） |
| 路線播放 | 沿多點路線移動，速度 1.8–900 km/h，可自訂速度預設 |
| 播放控制 | 暫停／繼續／停止；循環模式（走回起點或直接返回起點） |
| 背景播放 | 使用 iOS 17 背景定位活動，切到別的 App 仍繼續模擬 |
| 搖桿 | 前景模式下用虛擬搖桿推動位置 |
| 收藏與歷史 | 收藏地點（可分資料夾）、命名路線、歷史記錄；路線草稿在重啟後可恢復 |
| 地點搜尋 | 搜尋地址或直接輸入經緯度座標 |
| 設定頁 | 後端狀態、LocalDevVPN 目標 IP、通道測試、速度預設 |
| 一鍵還原 | 按 Stop 時自動呼叫 `location_simulation_clear()`，恢復真實 GPS |

App 有兩種後端：

- **Preview 後端**（一般 Debug 安裝）：沒有原生庫也能跑，用來開發與驗證 UI／路線引擎，不會真正改變定位。
- **idevice 後端**（`GFlyerIOS-Idevice` scheme）：真正做裝置級 GPS 模擬。

## 三、前置需求

- iPhone：iOS 17.4 以上，已開啟 **Developer Mode**（設定 → 隱私與安全性 → 開發者模式）。
- Mac：現行 Xcode＋CLI tools、XcodeGen（`brew install xcodegen`）、Rust（rustup）。
- 個人 Apple ID（免費即可）。
- 一條能連到電腦/VPN 伺服器的網路（Wi-Fi 或熱點皆可）。
- 使用者端的完整安裝步驟（Windows + SideStore）見[線上教學](https://michaelcheung0125-svg.github.io/GFlyer-updates/USER_GUIDE_ZH_HK.html)。

## 四、安裝與建置（Mac）

```bash
# 1. 產生 Xcode 專案
xcodegen generate

# 2. 先用一般 scheme 裝 Debug 版，驗證 UI 與路線引擎（預覽模式）
#    在 Xcode 選 GFlyerIOS scheme → 選個人 Team → 安裝到 iPhone

# 3. 建置裝置模式（真正 GPS 模擬）
chmod +x scripts/build_idevice.sh
./scripts/build_idevice.sh
xcodegen generate

# 4. 在 Xcode 選 GFlyerIOS-Idevice scheme → 個人 Team → 安裝到 iPhone
```

`build_idevice.sh` 會 clone 固定 commit 的 MIT 授權 `idevice` 函式庫，用 Rust 編出 `libidevice_ffi.a` 放到 `GFlyerIOS/Vendor/idevice/`（此目錄不進 Git）。

## 五、首次設定（裝置模式）

1. **產生 Pairing File**：用可信電腦的配對流程為這支 iPhone 產生 pairing file，透過 AirDrop 等方式傳到手機的「檔案」App（避免副檔名被移除）。
2. **匯入**：打開 GFlyer → 設定 → 匯入 Pairing File。檔案會以完整檔案保護存在 App 私人目錄。
3. **連 VPN**：安裝並連上 LocalDevVPN（預設目標 IP `10.7.0.1`），在設定頁按「Test LocalDevVPN tunnel」測試通道（port 49152）。
4. **首次模擬**：在地圖選點按開始。第一次會自動下載約 16 MB 的 Personalized DDI（有固定 SHA-256 驗證），完成後位置即生效。首次需授與定位權限（選「使用 App 期間」）。
5. **驗證**：打開 Apple Maps 確認位置已改變。

## 六、日常使用

1. 開 App → 連 LocalDevVPN。
2. 在地圖點選、搜尋地址／座標，或從收藏/歷史/路線挑選。
3. 選模式（傳送／單點／路線／螺旋）與速度，按開始。
4. 可暫停、繼續、循環播放；切到背景仍繼續。
5. **用完先按 Stop**（會自動恢復真實 GPS），再關 VPN。

行動網絡用戶：建立第一條通道時請先開飛行模式再連 Wi-Fi/熱點，通道建立後才開行動網絡；純 Wi-Fi／熱點不需要。

## 七、常見問題

| 症狀 | 處理 |
|---|---|
| App 顯示「預覽模式」 | 你裝到的是一般 Debug 版；需用 `GFlyerIOS-Idevice` scheme 重裝 |
| Tunnel 測試失敗 | 確認 VPN 已連、目標 IP 正確（預設 10.7.0.1） |
| DDI 下載／驗證失敗 | 檢查網路後重試；驗證失敗代表檔案損毀，重下載 |
| 切背景後斷線（BrokenPipe / Channel closed） | App 會自動重建一次；仍失敗就回到前景重試 |
| 停止後仍是假位置 | 在 App 內再按一次 Stop 確認 clear 成功 |
| 7 天後 App 打不開 | 個人簽署過期，重新簽署安裝 |

更多疑難排解見[線上教學的疑難排解章節](https://michaelcheung0125-svg.github.io/GFlyer-updates/USER_GUIDE_ZH_HK.html#p11)，實測案例見 [TROUBLESHOOTING_CASES.md](TROUBLESHOOTING_CASES.md)。

## 八、想深入了解

- `README.md` — 專案總覽與快速入門
- `docs/IMPLEMENTATION_PLAN.md` — 里程碑（M0–M4）與測試矩陣
- `docs/DEVICE_FEASIBILITY_CHECKLIST.md` — 實機可行性關卡記錄
- `HANDOFF.md` — 開發交接現況
- 程式架構：`GFlyerIOS/UI/`（畫面）、`GFlyerIOS/Services/`（模擬控制、後端、儲存）、`GFlyerIOS/Model/`（資料模型）
