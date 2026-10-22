# App Store 的加密出口申報（公開版）

`docs/APP_STORE_PLAN.md` 第 21 項。結論：

- 公開版 `GFlyerIOS/Public/Info.plist` 的 `ITSAppUsesNonExemptEncryption` 是 `NO`。這個鍵從原型就有，第 8 項分成兩個版本時兩個 `Info.plist` 各帶了一份；第 21 項核對了理由，CI 檢查建好的公開版 App 有這個鍵，而且是 `NO`。有了它，每次上傳 App Store Connect 都不用再回答加密的問題。
- `NO` 的前提有兩個：App 只用國際標準的加密；公開版**不在法國的 App Store 上架**（U9，使用者 2026-10-22 決定首版不上）。要在法國上架，先照第 4 節向法國申報。
- 這份是照 Apple 和美國法規的公開資料整理的（2026-10-22 讀），不是法律意見。Apple 寫明，誤解出口法規或錯誤聲稱豁免，責任在開發者。

親友版的 `Info.plist` 也有同一個鍵，但親友版不上 App Store，用不到，不改。Android 版沒有 idevice，Google Play 也沒有對應的申報。

## 1. App 用到的加密

除了最後三列，全部在連結進 App 執行檔的 idevice（Rust）裏，用途都是讓 GFlyer 連接**同一部 iPhone** 的開發者服務：配對、驗證 Pairing File，以及保護經本機通道的連線。GFlyer 不加密使用者的檔案，不和其他人或伺服器建立加密通訊，也沒有讓使用者自己加密資料的功能。通道 extension 只把封包對調位址後送回，不用加密。

| 用在哪裏 | 演算法 | 標準 |
|---|---|---|
| 連接開發者服務時驗證 Pairing File（`tunnel_create_rppairing`，idevice 的 `remote_pairing`） | X25519 金鑰交換、Ed25519 簽署、HKDF、ChaCha20-Poly1305 | IETF RFC 7748、8032、5869、8439 |
| 同一條連線之後的通道（idevice 自己實作的 `remote_pairing/tls_psk.rs`） | TLS 1.2 PSK：`TLS_PSK_WITH_AES_256_CBC_SHA384`、`TLS_PSK_WITH_AES_128_CBC_SHA` | RFC 5246、4279、5487 |
| 在這支 iPhone 上配對（`pairable_host_*`） | SRP-6a、Ed25519、X25519、HKDF、ChaCha20-Poly1305 | RFC 5054 等 |
| 一起連結進來的程式庫（`build_idevice.sh` 的 `ring` feature 帶進 rustls 和 ring；另有 `rsa`、`aes`、`sha1`、`sha2`、`md-5`） | TLS 1.2／1.3、RSA、AES、SHA 等 | IETF、NIST |
| DDI 下載（Swift） | `URLSession` 的 HTTPS | Apple 系統的加密 |
| DDI 核對（Swift） | CryptoKit 的 SHA-256 | Apple 系統的雜湊 |
| 掛載 DDI 時的 TSS 請求 | 經 HTTP，沒有加密 | — |

GFlyer 現在的連線流程不一定用到 rustls，但它編進了執行檔，申報時一併算進去。配對協定本身是 Apple 的，沒有公開規格；不過它的加密全部由上面的標準演算法組成，idevice 的原始碼也是公開的，沒有自創的演算法。

## 2. App Store Connect 的問題和答案

Apple 的 [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) 說，`ITSAppUsesNonExemptEncryption` 寫 `NO` 的意思是：App（包括它連結的第三方程式庫）沒有用加密，或者只用免交出口文件的加密。要交哪些文件，看 App Store Connect 說明的 [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption)：

| 用到的加密 | 要交的文件 |
|---|---|
| 只用 Apple 系統內的加密 | 不用 |
| 不是 Apple 系統提供的業界標準演算法 | 法國的加密申報，只限在法國上架 |
| 沒有被國際標準組織（IEEE、IETF、ITU 等）採用的自創演算法 | 美國的 CCATS 和法國的加密申報 |

GFlyer 屬於第二列。不在法國上架就不用交文件，所以算「免交文件的加密」，`Info.plist` 寫 `NO`。App Store Connect API 的加密申報（`AppEncryptionDeclaration`）也一樣：它的 `exempt` 欄位寫明是否豁免取決於「加密的用法和 App 的上架地區」。

如果 App Store Connect 還是要回答（例如將來拿走了這個鍵），按 API 的三個欄位這樣答：

| 問題 | 答案 |
|---|---|
| 有沒有自創或沒有被國際標準組織採用的加密（`containsProprietaryCryptography`） | 沒有 |
| 有沒有不經 Apple 系統、或在它之外另用標準加密（`containsThirdPartyCryptography`） | 有（idevice） |
| 會不會在法國的 App Store 上架（`availableOnFrenchStore`） | 不會（U9） |

## 3. 美國的出口規定

上傳 App Store Connect 等於把 App 送到美國的伺服器，再從美國發佈到其他地方，所以要照美國的出口管理規例（EAR）。

- GFlyer 經 App Store 公開提供給一般大眾，使用者改不到裏面的加密，安裝也不用開發者支援，符合 EAR 第 5 類第 2 部分 Note 3 的「大眾市場」條件，分類是 5D992.c。收費與否（U5）不影響這一點。
- 15 CFR 740.17(e)(3)（eCFR 2026-10-01 的條文）寫明，每年的自我分類報告只適用於大眾市場的「元件」和「executable software」，以及不屬大眾市場的項目。同一段把「executable software」定義為硬件元件的執行檔，不包括在終端產品上跑的完整軟件。GFlyer 是完整的 App，不在這個範圍，所以不用交報告，也不用申請 CCATS（BIS 2021-03-29 的修訂拿走了這類產品的報告）。Apple 的文件說用豁免加密的 App「可能」要交年終的自我分類報告；照現行條文，GFlyer 不用。
- 沒有自創的加密，所以也不用另外通知 BIS。

## 4. 法國

Apple 寫明，App 用了不是 Apple 系統提供的標準加密，又在法國上架，就要先向法國的 ANSSI 申報加密，再把申報文件上載到 App Store Connect。只有法國要這樣做，Apple 的對照表沒有列其他國家。

**首版不在法國上架（U9，使用者 2026-10-22 決定）。** App 只有中文介面，而申報要準備公司文件，最少等一個月。

### 申報要做甚麼

照 ANSSI 的申報頁（[demarche.numerique.gouv.fr](https://demarche.numerique.gouv.fr/commencer/declaration-relative-a-un-moyen-de-cryptologie)，2026-10-22 讀）和第 2007-663 號法令：

- 申報人是「提供者」，就是 JetPiggy。表格在上面那個法國政府網站，法文，網站估計填 28 分鐘，要先開那裏的帳戶。提供者申報了，經手發佈的中間人（App Store）就不用另外申報（法令第 6 條）。
- 要附的文件：
  - 公司簡介。
  - 三個月內的公司登記摘錄（法國的 K bis；外國公司交同等的文件）。
  - 這個加密產品的商業簡介和技術簡介。技術簡介可以從第 1 節改寫，要用法文或英文。
  - 使用手冊（有的話）。
- 最少在開始提供之前一個月申報，ANSSI 發出附登記編號的收據。文件不齊，ANSSI 在一個月內要求補交，一個月從補齊起重新計算（法令第 4、5 條）。
- 申報之後一年內，ANSSI 可以要求在兩個月內交出技術資料和原始碼，或者借兩份產品最多六個月（法令第 7 條）。idevice 和匯出後的公開版原始碼（第 28 項）本來就是公開的。
- 拿到收據之後，在 App Store Connect 的「App 資訊」>「App 加密文件」上載。Apple 說文件齊全的話，大約兩個工作天審核完，批核後給一個代碼。

### 上法國之後有甚麼不同

- `Info.plist` 改成 `ITSAppUsesNonExemptEncryption` 為 `YES`，加上 `ITSEncryptionExportComplianceCode`（Apple 給的代碼）；CI 的檢查和這份一起改。之後每次上傳照樣不用回答。
- 改了加密（例如 `build_idevice.sh` 的 features 帶進新的演算法），要重看申報是否還涵蓋，可能要重新申報、換代碼。
- 對其他國家沒有影響；法國帳戶的使用者就下載得到。

將來要在法國上架，次序是：

1. 向 ANSSI 申報，等收據。
2. 在 App Store Connect 上載收據，等 Apple 給代碼。
3. 改 `Info.plist`、CI 的檢查和這份。
4. 最後才在「價格與供應狀況」加上法國，而且離申報最少一個月。

## 5. 怎樣確認，和甚麼時候要重看

- CI：archive job 的「Check and summarize the public app」檢查建好的公開版 App 的 `Info.plist`，`ITSAppUsesNonExemptEncryption` 一定要是 `NO`。少了這個鍵或者改了值，CI 就失敗。
- 第 22 項建 App 時，「價格與供應狀況」不選法國。
- 第 23 項第一次上傳之後，TestFlight 的建置不顯示缺少出口合規資料（Missing Compliance），也不用回答加密的問題。
- 以下情況要先重看第 1 節，再決定這個鍵：
  - 改了 `scripts/build_idevice.sh` 的 features 或 revision。
  - 加了用到加密的程式庫，或 Swift 自己做加密。
  - 要在法國上架。
- 用了自創的加密，就不可以再寫 `NO`。

## 6. 使用者的決定

使用者 2026-10-22 決定 U9 照建議：首版不在法國上架，`Info.plist` 照舊寫 `NO`，不用交任何文件。之後要在法國上架，送審之前先照第 4 節申報。
