import CoreLocation
import Foundation

struct GeoCoordinate: Codable, Equatable, Hashable, Identifiable, Sendable {
    let latitude: Double
    let longitude: Double

    var id: String { String(format: "%.8f,%.8f", latitude, longitude) }
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var display: String { String(format: "%.6f, %.6f", latitude, longitude) }

    /// 不信任來源（GPX、備份、下載資料）用的失敗式建構：
    /// 超出範圍回傳 nil，而不是觸發 `init` 的 precondition。
    static func validated(latitude: Double, longitude: Double) -> GeoCoordinate? {
        guard latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
            return nil
        }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    static func parse(_ text: String) -> GeoCoordinate? {
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count >= 2 else { return nil }
        return validated(latitude: parts[0], longitude: parts[1])
    }

    init(latitude: Double, longitude: Double) {
        precondition((-90.0...90.0).contains(latitude), "Latitude must be between -90 and 90")
        precondition((-180.0...180.0).contains(longitude), "Longitude must be between -180 and 180")
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

enum GeoMath {
    private static let earthRadiusMetres = 6_371_000.0

    static func distanceMetres(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let lat1 = from.latitude.degreesToRadians
        let lat2 = to.latitude.degreesToRadians
        let deltaLat = lat2 - lat1
        let deltaLon = (to.longitude - from.longitude).degreesToRadians
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadiusMetres * asin(sqrt(min(max(a, 0), 1)))
    }

    static func bearingDegrees(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let lat1 = from.latitude.degreesToRadians
        let lat2 = to.latitude.degreesToRadians
        let deltaLon = (to.longitude - from.longitude).degreesToRadians
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x).radiansToDegrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func interpolate(from: GeoCoordinate, to: GeoCoordinate, fraction: Double) -> GeoCoordinate {
        let clamped = min(max(fraction, 0), 1)
        return GeoCoordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * clamped,
            longitude: normalizeLongitude(
                from.longitude + shortestLongitudeDelta(from: from.longitude, to: to.longitude) * clamped
            )
        )
    }

    static func destination(from: GeoCoordinate, bearingDegrees: Double, distanceMetres: Double) -> GeoCoordinate {
        let angularDistance = distanceMetres / earthRadiusMetres
        let bearing = bearingDegrees.degreesToRadians
        let lat1 = from.latitude.degreesToRadians
        let lon1 = from.longitude.degreesToRadians

        let lat2 = asin(
            sin(lat1) * cos(angularDistance)
                + cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        return GeoCoordinate(latitude: lat2.radiansToDegrees, longitude: normalizeLongitude(lon2.radiansToDegrees))
    }

    /// Equirectangular offset in metres (positive east / north), used for
    /// small local motions such as orbiting a route point. Latitude is clamped
    /// so poles cannot produce an invalid coordinate.
    static func offset(from origin: GeoCoordinate, eastMetres: Double, northMetres: Double) -> GeoCoordinate {
        let metresPerDegree = 111_320.0
        let latitudeDelta = northMetres / metresPerDegree
        let cosLatitude = max(cos(origin.latitude.degreesToRadians), 1e-6)
        let longitudeDelta = eastMetres / (metresPerDegree * cosLatitude)
        return GeoCoordinate(
            latitude: min(max(origin.latitude + latitudeDelta, -90), 90),
            longitude: normalizeLongitude(origin.longitude + longitudeDelta)
        )
    }

    private static func shortestLongitudeDelta(from: Double, to: Double) -> Double {
        var delta = to - from
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private static func normalizeLongitude(_ longitude: Double) -> Double {
        (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
