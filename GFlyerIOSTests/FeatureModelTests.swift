import XCTest
@testable import GFlyerIOS

final class FeatureModelTests: XCTestCase {
    func testCoordinateParserAcceptsValidPairAndRejectsOutOfRange() {
        XCTAssertEqual(GeoCoordinate.parse("22.3193, 114.1694"), GeoCoordinate(latitude: 22.3193, longitude: 114.1694))
        XCTAssertNil(GeoCoordinate.parse("91, 114"))
        XCTAssertNil(GeoCoordinate.parse("22, 181"))
        XCTAssertNil(GeoCoordinate.parse("not a coordinate"))
    }

    func testSpeedScaleRoundTripsSliderAndWarnsAboveFlowerLimit() {
        for speed in [SpeedScale.minimumKilometresPerHour, 5.0, 50.0, 900.0] {
            let roundTrip = SpeedScale.fromSliderPosition(SpeedScale.toSliderPosition(speed))
            XCTAssertEqual(roundTrip, speed, accuracy: 0.01)
        }
        XCTAssertFalse(SpeedScale.exceedsFlowerLimit(20))
        XCTAssertTrue(SpeedScale.exceedsFlowerLimit(20.1))
    }

    func testSpiralPreviewExpandsOutward() {
        let center = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        let points = SpiralPath.preview(center: center, current: center, state: SpiralState(), distanceMetres: 1_000, segmentLengthMetres: 100)
        XCTAssertGreaterThan(points.count, 2)
        XCTAssertGreaterThan(GeoMath.distanceMetres(from: center, to: points.last!), GeoMath.distanceMetres(from: center, to: points[1]))
    }

    func testTeleportLoopTransitionDoesNotAddWalkBackPoint() {
        let points = [
            GeoCoordinate(latitude: 22.3, longitude: 114.1),
            GeoCoordinate(latitude: 22.4, longitude: 114.2),
        ]
        XCTAssertEqual(RoutePlan.traversalPoints(points, loop: true, transitionMode: .teleportToStart), points)
    }

    @MainActor
    func testLocalDataStorePersistsFavoritesRoutesAndDraft() {
        let suiteName = "gflyer.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let place = GeoCoordinate(latitude: 22.3, longitude: 114.1)
        store.addFavorite(name: "起點", coordinate: place)
        store.addHistory(coordinate: place)
        store.saveDraft(points: [place, GeoCoordinate(latitude: 22.4, longitude: 114.2)], loop: true)
        XCTAssertEqual(store.snapshot.favorites.count, 1)
        XCTAssertEqual(store.snapshot.history.count, 1)
        XCTAssertEqual(store.snapshot.draft?.points.count, 2)

        let restored = LocalDataStore(defaults: defaults)
        XCTAssertEqual(restored.snapshot.favorites.first?.name, "起點")
        XCTAssertEqual(restored.snapshot.draft?.loop, true)
    }

    @MainActor
    func testControllerBuildsSingleAndMultiPointRoutesAndRestoresDraft() {
        let suiteName = "gflyer.controller-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let controller = SimulationController(backend: PreviewLocationSimulationBackend(), dataStore: store)
        let firstDestination = GeoCoordinate(latitude: 22.31, longitude: 114.17)
        let secondDestination = GeoCoordinate(latitude: 22.32, longitude: 114.18)

        controller.setMode(.singleRoute)
        controller.select(firstDestination)
        XCTAssertEqual(controller.routePoints.count, 2)
        XCTAssertEqual(controller.routePoints.last, firstDestination)

        controller.setMode(.multiRoute)
        controller.select(firstDestination)
        controller.select(secondDestination)
        XCTAssertEqual(controller.routePoints.count, 3)

        let restored = SimulationController(backend: PreviewLocationSimulationBackend(), dataStore: LocalDataStore(defaults: defaults))
        XCTAssertEqual(restored.mode, .multiRoute)
        XCTAssertEqual(restored.routePoints, controller.routePoints)
    }
}
