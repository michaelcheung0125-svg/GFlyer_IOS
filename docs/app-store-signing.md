# 公開版的簽署和上傳

給維護者：公開版（`com.jetpiggy.gflyer`）怎樣由 GitHub Actions 簽署並上傳 App Store Connect（`docs/APP_STORE_PLAN.md` 第 23 項）。沒有 Mac 也做得到：簽署檔在自己的電腦上用 Git Bash 準備，建置、簽署和上傳都在 GitHub 的 macOS runner 上做。

- workflow：`.github/workflows/app-store.yml`（Actions 頁叫「App Store upload」）
- 工具：`tools/app-store/signing.py`（準備簽署檔、放 secrets、CI 安裝和核對）和 `tools/app-store/check_public_app.sh`（核對建好的 App）
- 上傳只在使用者明確要求時做（`AGENTS.md`）。

> **還沒有人看過 Apple 網站的實際畫面。** 下面第一部分的按鈕和欄位名稱，照 Apple 的英文說明頁（2026-10-29 讀的）寫，引號裏是英文原文。第 22 項有了帳戶之後，做的時候截圖，再照畫面改這一份。

## 第一部分：準備簽署檔（跟着做 · 第一次做一次，之後每年續期）

要先有：

- 付費的 Apple Developer Program 帳戶（第 22 項）。建憑證、描述檔和團隊的 API 金鑰，帳戶的角色都要是 Account Holder 或 Admin。
- App Store Connect 裏已經建好公開版的 App（第 22 項）：Bundle ID `com.jetpiggy.gflyer`，「價格與供應狀況」不選法國（第 21 項）。沒有建好，上傳會失敗。
- 電腦上有 Git Bash（Windows 的 Git 附帶 `openssl`）、Python，和登入了的 GitHub CLI（`gh auth login`）。
- 下面的指令都在 Git Bash 裏、這個 repo 的資料夾跑。

### 1. 登記兩個 App ID

App 和本機通道（Packet Tunnel extension）各要一個。在 Apple 開發者網站的「Certificates, Identifiers & Profiles」：

1. 側邊欄按「Identifiers」，再按左上的「+」。
2. 選「App IDs」，按「Continue」；類型選 App，按「Continue」。
3. 「Description」填下表的名稱，選「Explicit App ID」，「Bundle ID」填下表的 Bundle ID。
4. 在「Capabilities」勾「Network Extensions」。不要勾 App Groups，公開版不用（第 12 項）。
5. 按「Continue」，核對之後按「Register」。

| Description（只是給自己看的名稱） | Bundle ID |
|---|---|
| GFlyer | `com.jetpiggy.gflyer` |
| GFlyer Tunnel | `com.jetpiggy.gflyer.tunnel` |

### 2. 建 Apple Distribution 憑證

1. 產生私密金鑰和憑證簽署要求（CSR）：

   ```bash
   python -I tools/app-store/signing.py request
   ```

   它在 repo 以外的 `~/GFlyer-signing/` 放下 `distribution.key`（私密金鑰）和 `distribution.certSigningRequest`。私密金鑰不要給任何人，也不要放進任何 repo；工具不准把這個資料夾放在 repo 裏。
2. 在「Certificates, Identifiers & Profiles」按「Certificates」，再按「+」，選 Apple Distribution，按「Continue」。
3. 按「Choose File」，選 `~/GFlyer-signing/distribution.certSigningRequest`，按「Continue」，再按「Download」。
4. 把下載的 `.cer` 和私密金鑰合成 `.p12`：

   ```bash
   python -I tools/app-store/signing.py certificate ~/Downloads/distribution.cer
   ```

   它核對這張是 Apple Distribution 憑證、是用第 1 步的 CSR 申請的，再產生 `distribution.p12` 和隨機的密碼檔，並印出憑證的到期日。

### 3. 建兩個描述檔

App 和本機通道各一個，都用第 2 步的憑證：

1. 在「Certificates, Identifiers & Profiles」按「Profiles」，再按「+」。
2. 在「Distribution」下選「App Store Connect」，按「Continue」。
3. 在「App ID」選 `com.jetpiggy.gflyer`，按「Continue」。
4. 選第 2 步的 Apple Distribution 憑證，按「Continue」。
5. 填描述檔的名稱（例如 GFlyer App Store），按「Generate」，再按「Download」。
6. 用 `com.jetpiggy.gflyer.tunnel` 再做一次（例如 GFlyer Tunnel App Store）。

名稱隨意，workflow 從檔案讀出來用。

### 4. 建 App Store Connect API 金鑰

上傳用它登入 App Store Connect：

1. 在 App Store Connect 的「Users and Access」按「Integrations」，頁面打開時已經選了「App Store Connect API」。
2. 按「Team Keys」，再按「Generate API Key」（已經有金鑰的話按「+」）。
3. 名稱填 GFlyer CI；「Access」選 Developer，按「Generate」。Apple 的說明寫明 Developer 角色可以上傳建置，不用給更大的權限；金鑰建好之後不能改名稱和權限，要改只可以撤銷再建一個。
4. 下載金鑰檔 `AuthKey_<Key ID>.p8`。Apple 的說明寫明 API 金鑰只能下載一次。**不要改檔名**：工具從檔名讀 Key ID。
5. 記下 Issuer ID。Apple 的說明頁沒有寫它在哪裏，做的時候截圖補上。

### 5. 放進 GitHub

先只核對、不改 GitHub：

```bash
python -I tools/app-store/signing.py secrets \
  --profile ~/Downloads/GFlyer_App_Store.mobileprovision \
  --profile ~/Downloads/GFlyer_Tunnel_App_Store.mobileprovision \
  --api-key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
  --issuer 你的-Issuer-ID \
  --dry-run
```

描述檔的檔名照下載的寫。它核對：

- 憑證：是 Apple Distribution 憑證，沒有過期。
- 兩個描述檔：都是 App Store Connect 描述檔，一個給 App、一個給本機通道；團隊和憑證相同，都有 Network Extensions 的 Packet Tunnel，沒有過期。
- API 金鑰：檔名和內容的格式對，Issuer ID 的格式對。

有錯就停下，說明哪裏不對。全部通過之後，拿走 `--dry-run` 再跑一次。它在這個 repo 建 `app-store` environment，只准 `main` 用，再放進七個 secrets（見第三部分的表）。

做完之後：

- 把 `~/GFlyer-signing/` 和 `.p8` 備份到安全的地方（例如密碼管理工具），再從「下載」資料夾刪掉 `.p8` 和描述檔。
- 這些檔案丟了不要緊：撤銷舊的，再做一次第 2、3、5 步（API 金鑰是第 4 步）。

## 第二部分：每次上傳（跟着做 · 每個版本一次）

1. 改版本號：只改 `project.yml` 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`（`docs/RELEASE_PROCESS.md` 第 1 步）。App Store Connect 不收已經上傳過的版本號，所以每次上傳 `CURRENT_PROJECT_VERSION` 都要比上一次大；親友版用同一個號碼。
2. push 到 `main`，等「macOS Xcode validation」綠燈。
3. 在 GitHub 的 Actions 頁選「App Store upload」，按「Run workflow」，分支選 `main`。要上傳就勾「上傳到 App Store Connect」；不勾的話只簽署和核對，不上傳。也可以叫 Claude 用 `gh workflow run app-store.yml --ref main -f upload=true` 觸發，Claude 只在你明確要求時做。
4. workflow 綠燈之後，App Store Connect 處理建置要一段時間，處理好了會在 TestFlight 出現。核對兩樣（第 20、21 項做完的標準）：沒有收到 ITMS-91053 之類的電郵；TestFlight 不問加密的問題。

## 第三部分：參考（出問題或想確認時才看）

### secrets

都放在 `app-store` environment（只准 `main` 用），由 `signing.py secrets` 放進去。名稱要和 `signing.py` 的 `SECRETS` 相同。

| Secret | 內容 |
|---|---|
| `DISTRIBUTION_CERTIFICATE_P12` | Apple Distribution 憑證和私密金鑰（`.p12`，base64） |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | `.p12` 的密碼 |
| `APP_STORE_PROFILE_APP` | `com.jetpiggy.gflyer` 的 App Store Connect 描述檔（base64） |
| `APP_STORE_PROFILE_TUNNEL` | `com.jetpiggy.gflyer.tunnel` 的 App Store Connect 描述檔（base64） |
| `APP_STORE_CONNECT_KEY` | App Store Connect API 金鑰（`.p8`，base64） |
| `APP_STORE_CONNECT_KEY_ID` | API 金鑰的 Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API 金鑰的 Issuer ID |

### workflow 做甚麼

push 改到 `tools/app-store/` 或這個 workflow 時，只跑「Signing tool self-test」：用自己產生的假憑證和假描述檔，試一遍 `signing.py` 的每一步，連應該擋下的例子。它用 OpenSSL 3，和 Windows 的 Git Bash 用的同一類，所以也證明 macOS 讀得到 `signing.py certificate` 產生的 `.p12`。這個 job 不用秘密。

手動觸發時，self-test 通過之後跑「Sign the public app」：

1. 確認是 `main`，核對釘住的 Xcode（和 `macos-xcode.yml` 相同）。
2. 從釘住的原始碼重新建 `libidevice_ffi.a`，不用快取。
3. `signing.py install`：
   - 把憑證放進只給這次用的 keychain，核對 macOS 認為它有效；
   - 用 secrets 裏的描述檔再核對一次，裝好；
   - 放下 API 金鑰。
   - 秘密只在這一步之後才用得到。
4. 用 `GFlyerPublic-Idevice` 的 AppStore 設定 archive，改用手動簽署；描述檔的名稱經 `project.yml` 的 `GFLYER_APP_PROFILE` 和 `GFLYER_TUNNEL_PROFILE` 給。
5. `check_public_app.sh`：和每次 push 查未簽署 archive 的是同一份檢查：
   - 圖示、Bundle ID、版本號和 `project.yml` 相同；
   - 加密申報、本機通道；
   - 建好的 App 的掃描、私隱清單、dSYM，沒有建置機器的路徑。
6. 匯出 IPA，用 `signing.py check-ipa` 核對兩個 bundle：
   - 由這個團隊的 Apple Distribution 憑證簽；
   - entitlements 有 Packet Tunnel，沒有 `get-task-allow`，有 `beta-reports-active`；
   - 裏面的描述檔是裝好的那兩個。
7. 上傳內容摘要（artifact `GFlyerPublic-AppStore-summary`）。和 `macos-xcode.yml` 的 `GFlyerPublic-Idevice-summary` 比，就知道簽署之外有沒有不同。不上傳 IPA。
8. 勾了上傳的話，從同一個 archive、用同一組選項再匯出一次，由 Xcode 直接上傳。
9. 最後刪掉 keychain、描述檔和 API 金鑰。

### 為甚麼這樣做

- **手動簽署，不用 Xcode 的自動簽署。** GitHub 的 runner 每次都是新的；自動簽署每次會建一張新的開發憑證，又要帳戶裏登記了裝置。
- **用 `xcodebuild -exportArchive` 上傳，不用 `altool`。** Xcode 26 的 `altool` 上傳失敗時，不一定回傳失敗的結束碼。
- **版本號不讓 Xcode 改。** 匯出選項的 `manageAppVersionAndBuildNumber` 是 false，版本號照 `project.yml`。
- **秘密只准 `main` 用。** 秘密放在 environment，不放在 repo 的 secrets。repo 是公開的：從 fork 開的 PR 拿不到 secrets，這個 workflow 也不在 pull request 時跑。

### 續期

- Apple Distribution 憑證和描述檔會過期；`signing.py certificate` 和 `secrets` 都會印出到期日。
- 過期之前做一次第一部分的第 2、3、5 步。描述檔也要重新產生，因為它綁着憑證。
- API 金鑰不會過期；被撤銷或者遺失了才做第 4 步。

### 出問題時

- `signing.py` 的錯誤訊息會說明哪個檔案、哪一項不對，以及要回 Apple 網站重做哪一步。
- workflow 在「Install the signing certificate, profiles and API key」失敗：多數是 secrets 少了或放錯，訊息會列出名稱。重跑第 5 步就可以。
- 上傳失敗，說版本號已經用過：照第二部分第 1 步把 `CURRENT_PROJECT_VERSION` 加一。
- 上傳失敗，說權限不夠：撤銷 API 金鑰，用 App Manager 角色再建一個（第 4 步），再做第 5 步。
