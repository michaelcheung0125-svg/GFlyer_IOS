# GFlyer iOS（公開版）

GFlyer（飛豬人）是 iOS 的位置測試 App（SwiftUI）。這個 repo 是它的公開版原始碼，以 Apache License 2.0 授權，品牌名稱和飛豬圖像除外（`NOTICE`）。公開版的 Bundle ID 是 `com.jetpiggy.gflyer`。

## 這個 repo 怎麼來

- 程式在維護者的開發 repo 寫，再匯出到這裏；每次同步是這個 repo 的一個新 commit。不要直接在這裏改程式：改動會在下一次同步時被蓋掉。`project.yml` 也是匯出時產生的。
- 外界的 issue 和 pull request：維護者看過後在開發 repo 改，下一次同步時一起出現。
- 程式註解提到的 `docs/…`、`HANDOFF.md` 和 GFlyer-Suite 是維護者的開發文件，不在這個 repo。

## 先讀甚麼

- `README.md`：功能、建置、私隱。
- `project.yml` 開頭的註解：有哪些 target 和 scheme。
- `GFlyerIOS/Edition/EditionFeatures.swift`：共用的程式怎樣經 `Edition` 和 `EditionModel` 碰公開版自己的東西（`GFlyerIOS/Public/`）。
- `NOTICE` 和 `THIRD_PARTY_NOTICES.md`：甚麼不在開源授權範圍內。

## 硬規則

- 這個 repo 是公開的：不可以加入個人姓名、私人電郵、個人帳戶名、本機路徑或秘密（金鑰、密碼、token）。聯絡一律用 gflyer@jetpiggy.com。
- 第三方程式庫和下載來源（idevice 的原始碼、DDI）的網址只放在程式和建置腳本裏；README、NOTICE 和其他說明不連去個人帳戶下的 repo。
- 不要提交 Pairing File、Apple 的私密金鑰、App Store Connect 的 API 金鑰、provisioning profile、DDI 檔案或 `libidevice_ffi.a`。`GFlyerIOS/Vendor/idevice/`、`.build/`、`build/` 和產生的 `.xcodeproj` 都不進版控。簽署和上傳用的秘密只放在 GitHub 的加密 secrets。
- 不要加入反偵測、不要修改其他 App，也不要繞過其他 App 的定位檢查。
- 語言模式是 Swift 5，CI 釘在 Xcode 26.6，最低 iOS 17.4：Swift 6.2 起的 approachable concurrency（`@concurrent`、`nonisolated(nonsending)`）和 iOS 26 才有的 API 不可以直接用，iOS 26 的 API 要加 `if #available`。
- 建置 archive 或 IPA、安裝到 iPhone、上傳 App Store Connect 和 push，都要等使用者明確要求；在模擬器編譯和跑單元測試可以直接做。
- force push、改寫歷史、刪除分支或 Release，都要先問使用者。
- 單元測試沒有覆蓋和 iPhone 開發者服務的實際連線、系統的 VPN 設定和畫面：改動這些地方，「編譯過、測試綠」不代表能用，要在 iPhone 上驗證。沒有 Mac 的環境只能做靜態檢查，不可以說成已經建置或驗證。
- CI 綠燈不等於產物正確：建好的 App 要有 `Assets.car`、App 圖示和正確的版本號，`scripts/ci.sh archive` 會核對。

## 建置和驗證

在裝了 Xcode 和 XcodeGen 的 Mac 上：

```bash
bash scripts/ci.sh test
```

iPhone 用的 `GFlyerPublic-Idevice` 要先有 `libidevice_ffi.a`（`bash scripts/ci.sh idevice`，要 Rust）。CI（`.github/workflows/ci.yml`）的每一步都是 `scripts/ci.sh` 的一個步驟。

## 發佈

- commit 和 push 由 JetPiggy 身分（`JetPiggy <gflyer@jetpiggy.com>`）做，都要等使用者明確要求。
- 公開之前，把會公開的改動逐項列給使用者確認。
