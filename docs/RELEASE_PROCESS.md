# GFlyer iOS 發佈流程（正式 Runbook）

**任何程式碼改動要交付給使用者，都必須走完這份流程。** 這份文件寫給未來的
維護者與 AI 助理：照著做就能把一個 commit 變成使用者 iPhone 上會自動跳出
更新提示的新版本。

## 全貌

```text
改程式碼
  → 升版本號（Info.plist，兩個欄位都要）
  → commit + push（公開 GFlyer_IOS）
  → GitHub Actions macOS CI（唯一的編譯驗證；Windows 不能編譯 Swift）
  → 下載 unsigned IPA artifact
  → 拆開 IPA 驗證內容（必做，CI 綠燈不代表產物正確）
  → 在公開 GFlyer-updates 建立 release 並上傳 IPA
  → 用 GFlyer-Suite 的 tools/release/release_manifest.py（build ios → project）
    更新 altstore.json 與 releases.json（DRIFT D8）→ commit + push（GitHub Pages 發佈）
  → 線上驗證來源檔與下載網址
  → 把版本記錄寫回 HANDOFF.md（重大行為變更同步 README 與 IMPLEMENTATION_PLAN）
使用者端：App 每 6 小時讀一次同一份 altstore.json，看到新版本就提示，
一鍵交給 SideStore 重簽安裝。
```

## 三個 repository 的分工

| Repo | 可見性 | 內容 |
|---|---|---|
| `michaelcheung0125-svg/GFlyer_IOS`（本 repo） | **公開** | 原始碼、CI、文件 |
| `michaelcheung0125-svg/GFlyer-updates`（本機 `C:\Project\GFlyer-updates`） | **公開** | iOS IPA release、`altstore.json` 更新來源、Android APK 與 `latest.json`、三平台聚合的 `releases.json`、圖示 |
| `michaelcheung0125-svg/GFlyer-Suite`（本機 `C:\Project\GFlyer-Suite`） | 私有 | 跨平台規格、golden fixture，以及產生上面三個更新檔的 `tools/release/release_manifest.py`（只在發佈的電腦上執行，CI 用不到） |

IPA 一律發佈到 `GFlyer-updates` 的 release：SideStore 與 App 內更新檢查都是
匿名 HTTPS 抓取，Actions artifact 即使在公開 repo 也要登入才能下載、而且會
過期；更新來源檔也在 `GFlyer-updates`，安裝檔和它放在一起。
Android 的 tag 是 `v<版本>`，iOS 一律用 **`ios-v<版本>`** 避免衝突。

## 逐步指令

以發佈 `0.4.5` 為例，換成實際版本號即可。

### 1. 升版本號

改 `GFlyerIOS/Info.plist` 的**兩個**欄位：

- `CFBundleShortVersionString`：`0.4.5`
- `CFBundleVersion`：`11`（每次發佈 +1；必須是整數字串）

沒有升版，App 內更新檢查不會提示（版本比較：先比行銷版本、再比 build）。
第 5 步的產生器另外強制先後規則：`CFBundleVersion` 必須比已發布的**嚴格變大**，
`CFBundleShortVersionString` 不可以變小；版本與 build 都和已發布的相同時是
**就地重新發布**，而且只能重新發布目前最新的那一版。

### 2. Commit、push、等 CI

```bash
git add -A && git commit -F <訊息檔> && git push origin main
gh run list --repo michaelcheung0125-svg/GFlyer_IOS --limit 1
gh run watch <run-id> --repo michaelcheung0125-svg/GFlyer_IOS --exit-status
```

CI 是唯一的編譯驗證。兩個 job：`Preview scheme tests`（Simulator 單元測試）
與 `Idevice unsigned archive`（arm64 IPA）。失敗時先修編譯錯誤，不要改測試
遷就。純文件改動在 commit 訊息加 `[skip ci]`（workflow 也設了 `paths-ignore`，
只動 `**/*.md`、`docs/**` 的 commit 會自動跳過）。

#### CI 成本（改任何觸發條件前先讀）

本 repo 是**公開**的：GitHub 的標準 runner（包括這兩個 job 用的 `macos-15`）在
公開 repo 不計費，不扣 included 額度。repo 還是私有的時候，macOS runner 以 10 倍
計費：實測每次 push 約 8.6 分鐘實際執行時間，會扣掉 60–80 分鐘的額度，2026-09
那個週期 21 次 push 就用掉 1,810 / 2,000 分鐘。下面的優化是那時做的，現在它們
省的是等結果的時間（每次 push 約 9 分鐘）；repo 若改回私有，這筆成本就回來了。

已做的優化：`libidevice_ffi.a` 依釘死的 commit 與 iOS SDK 版本快取（省掉每次
96 秒的 Rust 編譯）、`COMPILER_INDEX_STORE_ENABLE=NO`、文件改動不觸發。

刻意沒做的兩件事：

- **不快取 DerivedData。** 每次 push 的原始碼都不同，用精確的 key 必定 miss；
  用更粗的 key 則有拿到舊物的風險，而這個專案已經被「編譯成功但產物不完整」
  咬過一次（0.4.0 之前缺整個資產目錄）。
- **不合併兩個 job。** 加了快取之後 archive 只剩約 1.4 分鐘，合併省下的重複
  setup 剛好被小 job 的分鐘進位抵銷，卻要損失並行與較快的測試回饋。

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

### 5. 產生 manifest（GFlyer-Suite 的產生器）

`altstore.json` 與三平台共用的 `releases.json` 都由 GFlyer-Suite 的
`tools/release/release_manifest.py` 產生（DRIFT D8；完整說明在該 repo 的
`tools/release/README.md`），**不要手改**。在本 repo 根目錄執行，`<說明檔>` 用第 4 步
同一份：

```bash
python ../GFlyer-Suite/tools/release/release_manifest.py build ios \
  --ipa GFlyerIOS-0.4.5-unsigned.ipa \
  --notes-file <說明檔> \
  --out <暫存目錄>/release-manifest-ios-0.4.5.json
```

產生器從 IPA 讀出版本、build、bundle id 與最低 iOS 版本，計算大小與 SHA-256
（一律小寫），下載網址預設是 `ios-v<版本>` release 裡的 `GFlyerIOS-<版本>-unsigned.ipa`。
然後從公開網址把剛上傳的 IPA 下載回來，確認雜湊等於 manifest 的 `sha256`，
不相等就不要往下做。

和舊的 `scripts/update_altstore_source.py` 不同的地方：

- 更新說明必填（`--notes` 或 `--notes-file`），重新發布時不會沿用舊的說明。
- `--published-at` 要完整的 UTC 時間（例如 `2026-09-22T12:00:00Z`），不接受只有日期；
  省略時是現在。舊腳本的 `--date` 接受 `YYYY-MM-DD`。
- 強制第 1 步的先後規則；`versions[]` 必須由新到舊，扁平欄位取 `versions[0]`
  （舊腳本取最大的版本）。只能重新發布目前最新的那一版。
- `altstore.json` 必須是產生器寫出來的格式；被人手動重新排版過會被拒絕，
  因為整份重寫會連帶改到歷史項目。
- IPA 檔名必須是 `GFlyerIOS-X.Y.Z-unsigned.ipa`（和 release 資產同名），
  否則要用 `--url` 明確給下載網址。

### 6. 投影到來源檔並推送（先同步）

`releases.json` 是 Android 和 iOS 共用的，所以**投影之前**先把 `GFlyer-updates`
同步到最新，再看 diff、寫檔：

```bash
git -C ../GFlyer-updates fetch origin
git -C ../GFlyer-updates rebase origin/main   # Android 也會推這個 repo
python ../GFlyer-Suite/tools/release/release_manifest.py project \
  <暫存目錄>/release-manifest-ios-0.4.5.json --updates-dir ../GFlyer-updates --dry-run
python ../GFlyer-Suite/tools/release/release_manifest.py project \
  <暫存目錄>/release-manifest-ios-0.4.5.json --updates-dir ../GFlyer-updates
cd ../GFlyer-updates
git add altstore.json releases.json
git commit -m "Publish GFlyer iOS 0.4.5 (11) in the AltStore source"
git push origin main
```

`--dry-run` 的 diff 應該只有：`altstore.json` 插入一個 `versions[0]` 區塊、
6 個扁平欄位改成新版本，以及 `releases.json` 的 `ios` 區塊與 `generatedAt`。
`project` 任何一步檢查失敗都不會寫任何檔案；它不 commit、不 push、不上傳 IPA。

### 7. 線上驗證（必做）

等 GitHub Pages 重建（約一分鐘），然後：

- 抓 `https://michaelcheung0125-svg.github.io/GFlyer-updates/altstore.json`，
  確認 App 物件的扁平 `version` 是新版本
- 對 `downloadURL` 發 HEAD，確認 HTTP 200 且 `Content-Length` 等於來源檔
  的 `size`
- 抓 `https://michaelcheung0125-svg.github.io/GFlyer-updates/releases.json`，
  確認 `releases.ios` 是這一版
- 在 `GFlyer-updates` `git pull` 之後跑一次一致性檢查：
  `python ../GFlyer-Suite/tools/release/release_manifest.py check --updates-dir ../GFlyer-updates`

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
   `StoreApp is not valid`。由 GFlyer-Suite `tools/release/release_manifest.py`
   自動維護（`contracts/release-manifest.schema.json` 的 `$defs/altstoreProjection`），
   不要手改格式。
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
