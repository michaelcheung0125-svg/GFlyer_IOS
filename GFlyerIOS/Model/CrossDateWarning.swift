import Foundation

struct CrossDateWarning: Equatable {
    let destination: GeoCoordinate
    /// 2026年9月1日（月和日不補零）
    let deviceDateText: String
    let destinationDateText: String
    /// 手機時區的 IANA 名稱，例如 Asia/Taipei
    let deviceTimeZoneIdentifier: String
    let destinationUTCOffsetMinutes: Int
}

/// 跨日時區提醒的文字，三平台一字不差（GFlyer-Suite docs/features/cross-date-warning.md，
/// fixture `contracts/fixtures/cross-date/warning-text.json`）。以 Android 為準。
enum CrossDateWarningText {
    static let title = "跨日時區提醒"
    static let summary = "目的地日期以經度估算，與手機目前日期不同，可能會跨日。"
    static let confirmButton = "仍要傳送"
    static let cancelButton = "取消"
    static let settingTitle = "跨日時區提示"
    static let settingDescription = "傳送前比較手機與目的地的當地日期"

    /// 對話框內文的四行。Android 分開排，iOS 的 alert 只有一段內文，用 `message(for:)` 串起來。
    static func lines(for warning: CrossDateWarning) -> [String] {
        [
            summary,
            "手機：\(warning.deviceDateText) · \(warning.deviceTimeZoneIdentifier)",
            "目的地（估算）：\(warning.destinationDateText) · \(offsetText(minutes: warning.destinationUTCOffsetMinutes))",
            "目的地座標 \(warning.destination.display)",
        ]
    }

    static func message(for warning: CrossDateWarning) -> String {
        lines(for: warning).joined(separator: "\n")
    }

    /// GMT+08:00、GMT-10:00；時差是 0 時寫 GMT+00:00。
    static func offsetText(minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : "+"
        let absolute = abs(minutes)
        return "GMT" + sign + String(format: "%02d:%02d", absolute / 60, absolute % 60)
    }
}

/// Offline UTC-offset estimate from longitude (15 degrees per hour), matching
/// the Android implementation: a bounded, deterministic estimate instead of an
/// IANA polygon lookup, because the feature only needs to warn about a
/// possible civil-date change.
enum LongitudeTimeZoneEstimator {
    private static let degreesPerHour = 15.0
    private static let minUTCOffsetHours = -12
    private static let maxUTCOffsetHours = 14
    private static let dateLineEastLongitude = 172.5
    private static let dateLineWestLongitude = -172.5

    static func offsetMinutes(longitude: Double) -> Int {
        let hours: Int
        if longitude >= dateLineEastLongitude {
            hours = maxUTCOffsetHours
        } else if longitude <= dateLineWestLongitude {
            hours = minUTCOffsetHours
        } else {
            let rounded = Int((longitude / degreesPerHour + 0.5).rounded(.down))
            hours = min(max(rounded, minUTCOffsetHours), maxUTCOffsetHours)
        }
        return hours * 60
    }
}

enum CrossDateChecker {
    static func warning(
        destination: GeoCoordinate,
        now: Date = Date(),
        deviceTimeZone: TimeZone = .current
    ) -> CrossDateWarning? {
        let offsetMinutes = LongitudeTimeZoneEstimator.offsetMinutes(longitude: destination.longitude)
        guard let destinationTimeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) else { return nil }
        let deviceDate = localDate(of: now, in: deviceTimeZone)
        let destinationDate = localDate(of: now, in: destinationTimeZone)
        guard deviceDate != destinationDate else { return nil }
        return CrossDateWarning(
            destination: destination,
            deviceDateText: text(deviceDate),
            destinationDateText: text(destinationDate),
            deviceTimeZoneIdentifier: deviceTimeZone.identifier,
            destinationUTCOffsetMinutes: offsetMinutes
        )
    }

    private static func localDate(of date: Date, in timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    private static func text(_ components: DateComponents) -> String {
        "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
    }
}
