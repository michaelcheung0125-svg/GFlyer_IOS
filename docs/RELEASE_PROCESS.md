# GFlyer iOS 發佈流程（正式 Runbook）

**任何程式碼改動要交付給使用者，都必須走完這份流程。** 這份文件寫給未來的
維護者與 AI 助理：照著做就能把一個 commit 變成使用者 iPhone 上會自動跳出
更新提示的新版本。

## 全貌

```text
改程式碼
  → 升版本號（Info.plist，兩個欄位都要）
  → commit + push（私有 GFlyer_IOS）
  → GitHub Actions macOS CI（唯一的編譯驗證；Windows 不能編譯 Swift）
  → 下載 unsigned IPA artifact
  → 拆開 IPA 驗證內容（必做，CI 綠燈不代表產物正確）
  → 在公開 GFlyer-updates 建立 release 並上傳 IPA
  → 用腳本更新 altstore.json → commit + push（GitHub Pages 發佈）
  → 線上驗證來源檔與下載網址
  → 把版本記錄寫回 HANDOFF.md（重大行為變更同步 README 與 IMPLEMENTATION_PLAN）
使用者端：App 每 6 小時讀一次同一份 altstore.json，看到新版本就提示，
一鍵交給 SideStore 重簽安裝。
```

## 兩個 repository 的分工

| Repo | 可見性 | 內容 |
|---|---|---|
| `michaelcheung0125-svg/GFlyer_IOS`（本 repo） | **私有** | 原始碼、CI、文件 |
| `michaelcheung0125-svg/GFlyer-updates`（本機 `C:\Project\GFlyer-updates`） | **公開** | iOS IPA release、`altstore.json` 更新來源、Android APK 與 `latest.json`、圖示 |

IPA 一定要發佈到**公開** repo：SideStore 與 App 內更新檢查都是匿名 HTTPS
抓取，私有 repo 的 release 與 Actions artifact 需要登入、抓不到。
Android 的 tag 是 `v<版本>`，iOS 一律用 **`ios-v<版本>`** 避免衝突。

## 逐步指令

以發佈 `0.4.5` 為例，換成實際版本號即可。

### 1. 升版本號

改 `GFlyerIOS/Info.plist` 的**兩個**欄位：

- `CFBundleShortVersionString`：`0.4.5`
- `CFBundleVersion`：`11`（每次發佈 +1）

沒有升版，App 內更新檢查不會提示（版本比較：先比行銷版本、再比 build）。

### 2. Commit、push、等 CI

```bash
git add -A && git commit -F <訊息檔> && git push origin main
gh run list --repo michaelcheung0125-svg/GFlyer_IOS --limit 1
gh run watch <run-id> --repo michaelcheung0125-svg/GFlyer_IOS --exit-status
```

CI 是唯一的編譯驗證。兩個 job：`Preview scheme tests`（Simulator 單元測試）
與 `Idevice unsigned archive`（arm64 IPA）。失敗時先修編譯錯誤，不要改測試
遷就。純文件改動在 commit 訊息加 `[skip ci]`。

### 3. 下載 artifact 並「拆開驗證」（必做）

```bash
gh run download <run-id> --repo michaelcheung0125-svg/GFlyer_IOS \
  --name GFlyerIOS-Idevice-unsigned --dir <暫存目錄>
unzip -l GFlyerIOS-Idevice-unsigned.ipa
```

必須確認：

- `Payload/GFlyer.app/Assets.car` 存在（0.4.0 之前每一版都缺整個資產目錄，
  而 CI 全綠——**建置少了資源不會失敗**）
- `AppIcon60x60@2x.png` 存在
- `Payload/GFlyer.app/Info.plist` 的版本號與 build 是這次要發佈的

任何一項不對就回去修，不要發佈。

### 4. 建立公開 release

```bash
cp GFlyerIOS-Idevice-unsigned.ipa GFlyerIOS-0.4.5-unsigned.ipa
gh release create ios-v0.4.5 GFlyerIOS-0.4.5-unsigned.ipa \
  --repo michaelcheung0125-svg/GFlyer-updates \
  --title "GFlyer iOS v0.4.5" --notes-file <說明檔>
```

### 5. 更新 AltStore 來源檔

```bash
python scripts/update_altstore_source.py \
  --ipa GFlyerIOS-0.4.5-unsigned.ipa \
  --source ../GFlyer-updates/altstore.json \
  --tag ios-v0.4.5 \
  --notes "使用者看得懂的更新說明"
```

腳本會從 IPA 讀出版本／build／bundle id／最低 iOS 版本，計算大小與
SHA-256，並自動維護 SideStore 需要的扁平欄位。同版本重跑會就地取代。

### 6. 推送來源檔（注意 rebase）

```bash
cd ../GFlyer-updates
git fetch origin && git rebase origin/main   # Android 也會推這個 repo
git add altstore.json && git commit -m "Publish GFlyer iOS 0.4.5 (11) in the AltStore source"
git push origin main
```

### 7. 線上驗證（必做）

等 GitHub Pages 重建（約一分鐘），然後：

- 抓 `https://michaelcheung0125-svg.github.io/GFlyer-updates/altstore.json`，
  確認 App 物件的扁平 `version` 是新版本
- 對 `downloadURL` 發 HEAD，確認 HTTP 200 且 `Content-Length` 等於來源檔
  的 `size`

### 8. 記錄

在 `HANDOFF.md` 的版本清單加上這一版做了什麼；重大行為變更同步
`README.md` 與 `docs/IMPLEMENTATION_PLAN.md`（`AGENTS.md` 的規定）。
文件 commit 用 `[skip ci]`。

## 使用者端會看到什麼

- 0.4.0 起 App 讀同一份 `altstore.json`，回到前景每 6 小時檢查一次，
  有新版跳提示；設定 → 軟體更新可手動檢查
- 「用 SideStore 更新」走 `sidestore://install?url=` 深連結**直接安裝**，
  SideStore 的 My Apps 清單可能不顯示「有更新」——裝完版本變了就是成功
- 免費 Apple ID 簽名仍是 7 天效期，SideStore 自動重簽；發佈流程與簽名無關

## 不可回退的決定（改動前先讀）

這些是實機驗證後定下的，看起來「可以簡化」的地方往往就是當初的 bug：

1. **來源檔維持 SideStore 舊版扁平格式**：頂層 `identifier`、App 物件上的
   `version`/`versionDate`/`downloadURL`/`size`（與 `versions[0]` 重複是
   刻意的）、`permissions` 是陣列、日期含時間。缺任何一項 SideStore 報
   `StoreApp is not valid`。腳本自動維護，不要手改格式。
2. **更新檢查的 bundle id 三層比對**（相等 → 點號邊界前綴 → 單一 App）
   不可改回完全相等：SideStore 重簽會在 bundle id 加 team id 後綴（實機
   確認）。
3. **`project.yml` 的 Resources 必須留在 `sources`**：XcodeGen 沒有
   target 層級 `resources` 欄位，寫了會被靜默忽略，資產就不會打包。
4. **MainView / SetupView 保持拆層**：body 堆成單一運算式會讓 Swift 型別
   檢查器直接放棄（compile error）。
5. **清除模擬不可宣稱「已恢復真實定位」而不驗證**：實機確認即使拆掉模擬
   session，iOS 仍沿用快取的模擬定位，需要開關一次飛行模式才會回報真實
   位置。一般停止保留 session；「完整清除」拆 session 並驗證後如實回報。
6. **`LocalDataSnapshot` 維持容錯解碼**：新增欄位一律 decodeIfPresent 加
   預設值，否則升版會清空使用者的收藏與路線。

## 疑難排解速查

| 症狀 | 原因與處理 |
|---|---|
| SideStore 安裝一直轉圈 | 幾乎都是 LocalDevVPN 斷線（iOS 會自行終止 VPN），不會報錯。重連 VPN 再試 |
| 加入來源報 `StoreApp is not valid` | 來源檔缺扁平欄位，見上方第 1 點 |
| App 不提示新版本 | 版本號沒升、Pages 還沒重建，或未到 6 小時檢查間隔（可手動檢查） |
| 改了來源檔但 SideStore 沒反應 | SideStore 快取來源：移除來源再重新加入 |
| 停止後其他 App 仍在模擬位置 | 預期行為，用「完整清除模擬定位」並照指引開關飛行模式 |
