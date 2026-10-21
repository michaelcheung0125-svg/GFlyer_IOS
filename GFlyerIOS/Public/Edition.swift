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

    /// 公開版的使用教學還沒有寫（docs/APP_STORE_PLAN.md 第 14 項的引導）。
    static let userGuideURL: URL? = nil

    static let restoreConfirmationMessage = "還原會以備份內容取代現有的收藏、歷史、資料夾、路線與速度預設。Pairing File 不受影響。"

    static let backupFormatNote =
        "備份檔為 GFlyer Backup v1 格式，包含收藏、歷史、資料夾、路線與速度預設，與 GFlyer Android 的備份/還原互通。Pairing File 不會包含在備份內。"
}
