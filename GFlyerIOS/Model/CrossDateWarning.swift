import Foundation

struct CrossDateWarning: Equatable {
    let destination: GeoCoordinate
    let deviceDateText: String
    let destinationDateText: String
    let destinationUTCOffsetMinutes: Int
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
            destinationUTCOffsetMinutes: offsetMinutes
        )
    }

    private static func localDate(of date: Date, in timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    private static func text(_ components: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
