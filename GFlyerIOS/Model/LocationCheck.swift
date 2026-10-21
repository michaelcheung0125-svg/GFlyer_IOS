import Foundation

/// 定位檢查頁：比對 iOS 交給 App 的位置（和其他 App 收到的相同）和本 App 推送的位置，給一句結論。
/// 規格 GFlyer-Suite `docs/features/location-check.md`，fixture `contracts/fixtures/location-check/verdict-and-text.json`；
/// 以 Android 的 `model/LocationCheck.kt` 為準。`LocationCheckTests` 驗。
enum LocationCheck {
    /// 收到的位置和推送的位置在這個距離以內，算是同一個位置。
    static let matchMetres = 10.0

    /// 移動中收到的位置會晚一點：再加上這麼多秒走的距離。
    static let movingLagSeconds = 3.0

    /// 結論（規格 3.3）。`pushed` 是本 App 正在推送的位置（沒有在模擬時是 nil），`movingMetresPerSecond` 是它
    /// 現在移動的速度（停在一個點、暫停時是 0），`received` 是 iOS 最近交給 App 的位置。
    static func verdict(
        hasPermission: Bool,
        pushed: GeoCoordinate?,
        movingMetresPerSecond: Double,
        received: ReceivedLocation?
    ) -> LocationCheckVerdict {
        guard hasPermission else { return .needsPermission }
        guard let received else { return .waiting }
        guard let pushed else { return received.isSimulated ? .mockFromElsewhere : .realLocation }
        let tolerance = matchMetres + max(movingMetresPerSecond, 0) * movingLagSeconds
        let distance = GeoMath.distanceMetres(from: received.coordinate, to: pushed)
        return received.isSimulated && distance <= tolerance ? .matches : .mismatch
    }

    /// 「和推送的位置相距」：未滿 1 公里寫公尺，其餘寫到小數一位的公里。
    static func distanceText(metres: Double) -> String {
        if metres < 1_000 { return "\(Int(metres.rounded())) 公尺" }
        // Android 照十進位四捨五入（1,250 公尺是 1.3 公里）；%.1f 照二進位的值會寫成 1.2，所以先四捨五入到 100 公尺
        return String(format: "%.1f 公里", (metres / 100).rounded() / 10)
    }

    /// 「精度」：iOS 沒有給精度（`horizontalAccuracy` 是負的）時傳 nil。
    static func accuracyText(metres: Double?) -> String {
        metres.map { "±\(Int($0.rounded())) 公尺" } ?? LocationCheckText.noValue
    }

    /// 「時間」括號裏的多久之前。
    static func ageText(seconds: Int) -> String {
        switch seconds {
        case ..<1: return "剛剛"
        case ..<60: return "\(seconds) 秒前"
        case ..<3_600: return "\(seconds / 60) 分鐘前"
        default: return "\(seconds / 3_600) 小時前"
        }
    }

    /// 「時間」的值，例如「14:05:09（3 秒前）」：手機時區、24 小時制，秒數捨去小數，定位的時間在未來時當 0。
    static func timeText(timestamp: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        let seconds = Int(max(now.timeIntervalSince(timestamp), 0))
        return "\(formatter.string(from: timestamp))（\(ageText(seconds: seconds))）"
    }
}

/// iOS 交給 App 的一個位置（定位檢查頁用）。
struct ReceivedLocation: Equatable {
    let coordinate: GeoCoordinate
    /// iOS 把它標成軟體模擬的位置（`CLLocation.sourceInformation?.isSimulatedBySoftware`）。
    let isSimulated: Bool
}

/// 規格 3.4。結論的文字和 Android 一字不差；說明是 iOS 的寫法（Android 的指向開發者選項，iOS 沒有）。
enum LocationCheckVerdict: Equatable {
    case needsPermission
    case waiting
    case matches
    case realLocation
    case mockFromElsewhere
    case mismatch

    var text: String {
        switch self {
        case .needsPermission: return "需要定位權限才能讀取其他 App 收到的位置"
        case .waiting: return "等待位置…"
        case .matches: return "其他 App 收到的就是本 App 推送的位置"
        case .realLocation: return "現在沒有模擬，收到的是手機的真實位置"
        case .mockFromElsewhere: return "本 App 沒有在模擬，但收到的位置仍標示為模擬位置"
        case .mismatch: return "模擬中，但其他 App 收到的不是本 App 推送的位置"
        }
    }

    /// 結論下方的說明；沒有就是 nil。
    var hint: String? {
        switch self {
        case .waiting: return "室內或剛打開時可能要等一下。"
        // iOS 停止之後常常沿用快取的模擬位置，要「完整清除」（docs/TROUBLESHOOTING_CASES.md 案例 4）
        case .mockFromElsewhere: return "剛停止時要等幾秒；一直這樣的話，請回到設定頁，按「恢復」的「完整清除模擬定位」。"
        case .mismatch: return "剛開始模擬時要等幾秒；一直這樣的話，請按「停止模擬」，再按「傳送到選取的位置」。"
        case .needsPermission, .matches, .realLocation: return nil
        }
    }
}

/// 定位檢查頁的字（規格 3.1、3.5、3.7）。和 Android 相同，只有說明裏的系統名稱和 iOS 專屬的幾句不同。
enum LocationCheckText {
    static let title = "定位檢查"
    static let entrySubtitle = "看其他 App 現在收到的位置，確認模擬有沒有生效"
    static let intro = "這一頁顯示 iOS 現在交給其他 App 的位置，用來確認模擬定位有沒有生效。只在這一頁開著時讀取，不儲存、不傳送。"
    static let settingsSection = "設定"
    static let pushingLabel = "本 App 正在推送"
    static let notPushing = "沒有（現在沒有模擬）"
    static let receivedSection = "其他 App 收到的位置"
    static let coordinateLabel = "座標"
    static let accuracyLabel = "精度"
    static let timeLabel = "時間"
    static let sourceLabel = "來源"
    static let distanceLabel = "和推送的位置相距"
    static let noValue = "—"
    static let sourceSimulated = "模擬位置"
    static let sourceReal = "手機的真實位置"
    static let grantPermissionButton = "允許定位權限"
    static let teleportButton = "傳送到選取的位置"
    static let stopButton = "停止模擬"
    /// `waiting` 而且 iOS 報告讀不到位置時，取代 `waiting` 的說明。
    static let updatesFailedHint = "iOS 沒有交出位置：可能暫時收不到定位，請到收訊較好的位置再試。"
    /// 地圖不是「定點傳送」而且模擬中時按「傳送到選取的位置」（規格 3.7）。
    static let teleportWhileMoving = "請先停止目前的定位模擬，再傳送到選取的位置。"

    static func selected(_ coordinate: GeoCoordinate) -> String {
        "選取的位置：\(coordinate.display)"
    }
}
