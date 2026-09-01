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

## 安裝目前的版本

AltStore 與 SideStore 都接受未簽名的 IPA，會在安裝時用你的 Apple ID 重新
簽名。所以 CI 產出的 `GFlyerIOS-Idevice-unsigned.ipa` 可以直接使用：

1. 從 GitHub Actions 的 `GFlyerIOS-Idevice-unsigned` artifact 下載並解壓縮。
2. 把 `.ipa` 傳到 iPhone 的「檔案」App。
3. 在 AltStore / SideStore 選 **My Apps → +**，挑這個 IPA。

換用 AltStore 安裝前，先在 GFlyer 的**設定 → 資料匯入與匯出 → 匯出備份檔**
備份收藏與路線。簽名身分改變時 iOS 會視為不同的 App，舊資料不會保留；
pairing file 需要重新匯入，留言板也要用邀請碼重新加入。

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

1. 確認 `.github/workflows/macos-xcode.yml` 的兩個 job 都通過。
2. 下載該次 run 的 `GFlyerIOS-Idevice-unsigned` artifact 並解壓縮。
3. 把檔案改名成 `GFlyerIOS-<版本>-unsigned.ipa`，例如
   `GFlyerIOS-0.3.0-unsigned.ipa`。
4. 在 `GFlyer-updates` 建立 release，tag 用 `ios-v<版本>`，避開 Android 的
   `v<版本>` tag，並上傳這個 IPA：

   ```bash
   gh release create ios-v0.3.0 GFlyerIOS-0.3.0-unsigned.ipa \
     --repo michaelcheung0125-svg/GFlyer-updates \
     --title "GFlyer iOS v0.3.0" \
     --notes "更新內容"
   ```

5. 更新來源檔。腳本會自己從 IPA 讀出版本、build、bundle identifier 與最低
   iOS 版本，並計算大小與 SHA-256：

   ```bash
   python3 scripts/update_altstore_source.py \
     --ipa GFlyerIOS-0.3.0-unsigned.ipa \
     --source ../GFlyer-updates/altstore.json \
     --tag ios-v0.3.0 \
     --notes "更新內容"
   ```

6. 在 `GFlyer-updates` 提交並推送 `altstore.json`。GitHub Pages 更新後，
   AltStore / SideStore 就會看到新版。

同一個 `version` + `buildVersion` 重跑腳本會就地取代該筆記錄，方便修正
發佈錯誤；版本不同則會插到最前面。

## 注意事項

- 每次改動 Swift 程式碼都需要新的 IPA。座標圖鑑與留言板是 HTTPS 抓取的
  資料，改資料不需要重新發佈 App。
- 免費 Apple ID 同時只能側載 3 個 App，AltStore / SideStore 本身佔一個。
- 來源檔與 IPA 都是公開的。IPA 未經簽名，其他人仍然需要用自己的 Apple ID
  才能安裝，你的簽名身分不會包含在裡面。
- `altstore.json` 的 `sha256` 只是給人核對用，AltStore 不會強制驗證；真正
  的完整性保證來自 HTTPS 與 GitHub release。
