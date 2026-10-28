import SwiftUI

/// 親友版（經 SideStore 安裝）。見 `EditionFeatures`。
enum Edition: EditionFeatures {
    static let callbackScheme = "gflyer"

    static func speedHint(kilometresPerHour: Double) -> String? {
        FlowerSpeedLimit.exceeds(kilometresPerHour) ? "注意: 超過 20 km/h 將無法種花" : nil
    }

    static let tunnelWording = TunnelWording(
        invalidDeviceIP: "LocalDevVPN 目標 IP 無效。",
        tunnelFailed: "無法建立 LocalDevVPN/CoreDevice 通道。",
        handshakeHint: "CoreDevice/RSD 交握失敗：請重新連接 LocalDevVPN；若仍失敗，請保留完整錯誤文字。",
        reconnectHint: "通道已中斷或無法建立：使用行動網絡時，請先開啟飛行模式並重新建立通道，成功後再開回行動網絡；已連接 Wi-Fi 或個人熱點時無需開啟飛行模式，請重新連接 LocalDevVPN。同時確認 GFlyer 目標 IP 與 LocalDevVPN Device IP 相同。",
        verifiedStatus: "LocalDevVPN/CoreDevice 通道已驗證"
    )

    static let userGuideURL = URL(string: "https://michaelcheung0125-svg.github.io/GFlyer-updates/USER_GUIDE_ZH_HK.html")

    /// 私隱政策只寫公開版，親友版沒有（和 Android 親友版相同）。
    static let privacyPolicyURL: URL? = nil

    static let restoreConfirmationMessage = "還原會以備份內容取代現有的收藏、歷史、資料夾、路線與速度預設。留言板登入與 Pairing File 不受影響。"

    static let backupFormatNote =
        "備份檔為 GFlyer Backup v1 格式，包含收藏、歷史、資料夾、路線與速度預設，與 GFlyer Android 的備份/還原互通。留言板登入與 Pairing File 不會包含在備份內。"

    static let usageSteps = [
        "1. 用電腦產生這部 iPhone 的 pairing file。",
        "2. 將檔案傳到 iPhone 並在此匯入。",
        "3. 確認已安裝 LocalDevVPN。",
        "4. 回到地圖選點並按開始；VPN 未開時 GFlyer 會自動切換到 LocalDevVPN 開啟，再自動回來。",
    ]

    static let developerDiskImageMissingMessage: String? = nil

    @MainActor
    static func developerDiskImageRows(controller _: SimulationController) -> some View {
        Text("第一次使用裝置模式時，GFlyer 會下載約 16 MB、固定版本並經 SHA-256 驗證的 Personalized DDI，之後保留在本機使用。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    static func makeRegionLabelSource() -> any RegionLabelSource { NominatimRegionLabelSource() }

    /// 親友版不上 App Store，照舊不問（DRIFT D33）。
    static let regionLookupConsentService: String? = nil
}
