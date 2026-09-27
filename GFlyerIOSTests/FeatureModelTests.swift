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
        // 從汽車按 -1 三十次(Android 以 Float 累加)得到 20.000013 km/h,畫面顯示 20.0,不該警告
        XCTAssertFalse(SpeedScale.exceedsFlowerLimit(20.000013))
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

    /// GFlyer-Suite docs/features/name-limits.md 第 4 節的表:收藏新增與改名都是「去空白 →
    /// 截斷到 80 個 code point → 再去結尾空白」;改名成空白時名稱不變。
    @MainActor
    func testFavoriteNamesAreNormalizedWhenAddedAndRenamed() throws {
        let suiteName = "gflyer.favorite-name-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let road80 = String(repeating: "路", count: 80)
        let road81 = String(repeating: "路", count: 81)
        let road79 = String(repeating: "路", count: 79)

        store.addFavorite(name: road81, coordinate: GeoCoordinate(latitude: 1, longitude: 1))
        XCTAssertEqual(store.snapshot.favorites.first?.name, road80)
        store.addFavorite(name: road79 + " x", coordinate: GeoCoordinate(latitude: 2, longitude: 2))
        XCTAssertEqual(store.snapshot.favorites.first?.name, road79, "截斷後結尾是空白時再去掉")

        let id = try XCTUnwrap(store.snapshot.favorites.first?.id)
        store.renameFavorite(id, name: road81)
        XCTAssertEqual(store.snapshot.favorites.first?.name, road80)
        store.renameFavorite(id, name: road79 + " x")
        XCTAssertEqual(store.snapshot.favorites.first?.name, road79)
        store.renameFavorite(id, name: "  台北車站  ")
        XCTAssertEqual(store.snapshot.favorites.first?.name, "台北車站")
        store.renameFavorite(id, name: "   ")
        XCTAssertEqual(store.snapshot.favorites.first?.name, "台北車站", "空白名稱不改")
        store.renameFavorite(id, name: "")
        XCTAssertEqual(store.snapshot.favorites.first?.name, "台北車站", "空字串不改")
        XCTAssertEqual(LocalDataStore(defaults: defaults).snapshot.favorites.first?.name, "台北車站")
    }

    /// 和 Android 相同:沒有名稱時是「收藏 <座標>」,同一個座標已經收藏過就不新增。
    @MainActor
    func testAddingAFavoriteTwiceKeepsTheFirstOne() {
        let suiteName = "gflyer.favorite-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults)
        )
        let place = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        controller.select(place)

        XCTAssertEqual(controller.addFavorite(), "收藏成功")
        XCTAssertEqual(controller.favorites.map(\.name), ["收藏 22.319300, 114.169400"])
        let firstID = controller.favorites.first?.id

        XCTAssertEqual(controller.addFavorite(name: "新名字"), "此座標已經收藏過")
        XCTAssertEqual(controller.favorites.map(\.name), ["收藏 22.319300, 114.169400"])
        XCTAssertEqual(controller.favorites.first?.id, firstID)

        controller.select(GeoCoordinate(latitude: 22.32, longitude: 114.17))
        XCTAssertEqual(controller.addFavorite(name: "  旺角  "), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.name, "旺角")
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

        // 多點路線只包含使用者點的點，不會自動帶入上一次選取的位置
        controller.setMode(.multiRoute)
        XCTAssertTrue(controller.routePoints.isEmpty)
        controller.select(firstDestination)
        controller.select(secondDestination)
        XCTAssertEqual(controller.routePoints, [firstDestination, secondDestination])

        // 兩個點的多點草稿重開後仍是多點模式（不能再靠點數判斷）
        let restored = SimulationController(backend: PreviewLocationSimulationBackend(), dataStore: LocalDataStore(defaults: defaults))
        XCTAssertEqual(restored.mode, .multiRoute)
        XCTAssertEqual(restored.routePoints, controller.routePoints)
    }

    @MainActor
    func testMultiPointRouteCanBeEmptiedAndRestartedWithoutAnchor() {
        let suiteName = "gflyer.controller-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults)
        )
        let first = GeoCoordinate(latitude: 22.31, longitude: 114.17)
        let second = GeoCoordinate(latitude: 22.32, longitude: 114.18)
        let third = GeoCoordinate(latitude: 22.33, longitude: 114.19)

        controller.setMode(.multiRoute)
        controller.select(first)
        controller.select(second)
        controller.removeLastRoutePoint()
        controller.removeLastRoutePoint()
        XCTAssertTrue(controller.routePoints.isEmpty, "多點路線可以刪到一個點都不剩")

        controller.select(third)
        XCTAssertEqual(controller.routePoints, [third], "刪光後點的新點就是第一點，不會連上之前的選取位置")

        controller.clearRoute()
        controller.select(first)
        XCTAssertEqual(controller.routePoints, [first], "清除路線後同樣從新點開始")

        // 空的多點草稿也要記住模式
        controller.clearRoute()
        let restored = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults)
        )
        XCTAssertEqual(restored.mode, .multiRoute)
        XCTAssertTrue(restored.routePoints.isEmpty)
    }

    @MainActor
    func testSinglePointRouteKeepsItsOrigin() {
        let suiteName = "gflyer.controller-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults)
        )
        controller.setMode(.singleRoute)
        controller.select(GeoCoordinate(latitude: 22.31, longitude: 114.17))
        controller.removeLastRoutePoint()
        XCTAssertEqual(controller.routePoints.count, 1, "單點路線的起點不能被刪掉")
        controller.removeLastRoutePoint()
        XCTAssertEqual(controller.routePoints.count, 1)
    }

    func testOldDraftWithoutModeFlagStillDecodes() throws {
        let point = GeoCoordinate(latitude: 22.31, longitude: 114.17)
        let legacyJSON = #"{"points":[{"latitude":22.31,"longitude":114.17},{"latitude":22.32,"longitude":114.18}],"loop":false}"#
        let draft = try JSONDecoder().decode(RouteDraft.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(draft.isMultiPoint)
        XCTAssertEqual(draft.points.first, point)
    }

    func testRealLocationFilter() {
        XCTAssertNotNil(DeviceLocationService.realCoordinate(
            latitude: 22.3, longitude: 114.1, horizontalAccuracy: 30, isSimulatedBySoftware: false
        ))
        XCTAssertNil(DeviceLocationService.realCoordinate(
            latitude: 22.3, longitude: 114.1, horizontalAccuracy: 30, isSimulatedBySoftware: true
        ), "模擬定位不能被當成真實位置記下")
        XCTAssertNil(DeviceLocationService.realCoordinate(
            latitude: 22.3, longitude: 114.1, horizontalAccuracy: -1, isSimulatedBySoftware: false
        ), "精確度為負值代表定位無效")
        XCTAssertNil(DeviceLocationService.realCoordinate(
            latitude: 123, longitude: 114.1, horizontalAccuracy: 30, isSimulatedBySoftware: false
        ))
    }
}
