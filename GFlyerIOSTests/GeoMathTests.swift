import XCTest
@testable import GFlyerIOS

final class GeoMathTests: XCTestCase {
    func testDistanceBetweenHongKongPoints() {
        let central = GeoCoordinate(latitude: 22.2819, longitude: 114.1589)
        let tsimShaTsui = GeoCoordinate(latitude: 22.2976, longitude: 114.1722)

        let distance = GeoMath.distanceMetres(from: central, to: tsimShaTsui)

        XCTAssertEqual(distance, 2_217, accuracy: 80)
    }

    func testInterpolationCrossesDateLineUsingShortestPath() {
        let start = GeoCoordinate(latitude: 0, longitude: 179)
        let end = GeoCoordinate(latitude: 0, longitude: -179)

        let midpoint = GeoMath.interpolate(from: start, to: end, fraction: 0.5)

        XCTAssertEqual(abs(midpoint.longitude), 180, accuracy: 0.0001)
    }

    func testLoopRouteWalksBackToStart() {
        let points = [
            GeoCoordinate(latitude: 22.3, longitude: 114.1),
            GeoCoordinate(latitude: 22.4, longitude: 114.2),
        ]

        XCTAssertEqual(
            RoutePlan.traversalPoints(points, loop: true, transitionMode: .walkBack),
            points + [points[0]]
        )
    }
}
