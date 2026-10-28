import SwiftUI

/// 公開版（App Store）。見 `EditionFeatures`。
enum Edition: EditionFeatures {
    static let callbackScheme = "jetpiggy-gflyer"

    static func speedHint(kilometresPerHour: Double) -> String? { nil }

    static let tunnelWording = TunnelWording(
        invalidDeviceIP: "目標 IP 無效。",
        tunnelFailed: "無法建立 CoreDevice 通道。",
        handshakeHint: "CoreDevice/RSD 交握失敗：請重新建立本機通道；若仍失敗，請保留完整錯誤文字。",
        reconnectHint: "通道已中斷或無法建立：使用行動網絡時，請先開啟飛行模式並重新建立通道，成功後再開回行動網絡；已連接 Wi-Fi 或個人熱點時無需開啟飛行模式，請重新建立本機通道。同時確認設定頁的目標 IP 正確。",
        verifiedStatus: "CoreDevice 通道已驗證"
    )

    /// 公開版沒有網上的使用教學：第一次設定由 App 裏的首次設定引導帶着做（docs/APP_STORE_PLAN.md 第 14 項）。
    static let userGuideURL: URL? = nil

    /// docs/APP_STORE_PLAN.md 第 19 項。內容的正本是 `docs/privacy-policy.md`；網站送審之前才放上去，
    /// 在那之前這個網址打不開。
    static let privacyPolicyURL = URL(string: "https://gflyer.jetpiggy.com/ios/privacy.html")

    static let restoreConfirmationMessage = "還原會以備份內容取代現有的收藏、歷史、資料夾、路線與速度預設。Pairing File 不受影響。"

    static let backupFormatNote =
        "備份檔為 GFlyer Backup v1 格式，包含收藏、歷史、資料夾、路線與速度預設，與 GFlyer Android 的備份/還原互通。Pairing File 不會包含在備份內。"

    /// 開發者模式、配對、通道和 DDI 都在首次設定引導裏一步一步做。
    static let usageSteps = [
        "1. 第一次使用時，按「首次設定」的「\(FirstSetupText.entryTitle)」，照着做完。",
        "2. 之後回到地圖選點並按開始；本機通道未開時 GFlyer 會自動開啟。",
    ]

    /// 設定頁下載 DDI 的按鈕，連大小。
    static let developerDiskImageDownloadTitle = "下載 DDI（約 \(DeveloperDiskImageStore.downloadSizeText)）"

    static let developerDiskImageMissingMessage: String? =
        "還沒有下載 DDI。請到設定頁的「Developer Disk Image」按「\(developerDiskImageDownloadTitle)」，完成後再試。"

    @MainActor
    static func developerDiskImageRows(controller: SimulationController) -> some View {
        DeveloperDiskImageDownloadRows(controller: controller, download: .shared)
    }

    /// 不連 Nominatim（docs/APP_STORE_PLAN.md 第 17 項）。
    static func makeRegionLabelSource() -> any RegionLabelSource { AppleGeocoderRegionLabelSource() }

    /// 照 Android 公開版先問（U7）。Android 寫「手機系統的地點服務」，因為背後的服務由手機決定；
    /// iOS 的 `CLGeocoder` 一定是 Apple 的。
    static let regionLookupConsentService: String? = "Apple 的地點服務"
}
