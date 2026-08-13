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
