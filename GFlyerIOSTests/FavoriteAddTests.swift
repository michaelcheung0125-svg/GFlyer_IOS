import XCTest
@testable import GFlyerIOS

/// 地圖工具列 ☆ 的收藏流程(GFlyer-Suite docs/features/favorite-add.md 第 6 節的單元測試):
/// 收藏目標座標、按 ☆ 的判斷、預填與 `addFavorite(name:coordinate:)`。
/// 既有的 `FeatureModelTests.testAddingAFavoriteTwiceKeepsTheFirstOne` 與 `RegionLabelTests` 涵蓋沒有模擬時的舊行為。
@MainActor
final class FavoriteAddTests: XCTestCase {
    // MARK: - 文字

    func testTextsMatchTheSpecWordForWord() {
        XCTAssertEqual(FavoriteAddTexts.dialogTitle, "收藏位置")
        XCTAssertEqual(FavoriteAddTexts.namePlaceholder, "留空就用座標當名稱")
        XCTAssertEqual(FavoriteAddTexts.confirmButton, "收藏")
        XCTAssertEqual(FavoriteAddTexts.cancelButton, "取消")
        XCTAssertEqual(FavoriteAddTexts.added, "收藏成功")
        XCTAssertEqual(FavoriteAddTexts.alreadyExists, "此座標已經收藏過")
        XCTAssertEqual(FavoriteAddTexts.toolbarButtonLabel, "收藏選擇位置")
        XCTAssertEqual(SimulationController.favoriteAddedMessage, "收藏成功")
        XCTAssertEqual(SimulationController.favoriteAlreadyExistsMessage, "此座標已經收藏過")

        XCTAssertEqual(FavoriteAddTexts.defaultName(for: FavoriteSpot.taipei), "收藏 25.033900, 121.564500")
        // 最長的預設名稱 26 個 code point,存的時候不會被 80 的上限截斷
        let longest = FavoriteAddTexts.defaultName(for: GeoCoordinate(latitude: -90, longitude: -180))
        XCTAssertEqual(longest, "收藏 -90.000000, -180.000000")
        XCTAssertEqual(longest.unicodeScalars.count, 26)
    }

    // MARK: - FavoriteTargetTracker(純值型別,規格第 5 節的狀態表)

    func testTrackerFollowsSuccessfulPushesAndForgetsThemOnFailureOrStop() {
        let selected = FavoriteSpot.mongKok
        let p = GeoCoordinate(latitude: 22.30, longitude: 114.17)
        let q = GeoCoordinate(latitude: 22.31, longitude: 114.18)
        let r = GeoCoordinate(latitude: 22.32, longitude: 114.19)
        var tracker = FavoriteTargetTracker()

        XCTAssertNil(tracker.simulated)
        XCTAssertEqual(tracker.target(selected: selected), selected, "沒有模擬:選取點")
        tracker.pushSucceeded(p)
        XCTAssertEqual(tracker.target(selected: selected), p, "模擬中:模擬位置")
        tracker.pushSucceeded(q)
        XCTAssertEqual(tracker.target(selected: selected), q, "每次推送成功都換成新的位置")

        tracker.pushFailed()
        XCTAssertEqual(tracker.target(selected: selected), selected, "推送失敗之後:選取點")
        // 推送失敗之後再開始路線:開始路線不寫座標,倒數中與第一次推送之前沒有任何事件
        XCTAssertEqual(tracker.target(selected: selected), selected, "失敗後再開始路線、第一次推送前:仍是選取點")
        tracker.pushSucceeded(r)
        XCTAssertEqual(tracker.target(selected: selected), r)

        tracker.stopRequested()
        XCTAssertEqual(tracker.target(selected: selected), selected, "按下停止:選取點")
        // 清除失敗不是事件:停下的位置 R 不會回來,選取點改了就跟著選取點
        XCTAssertNil(tracker.simulated)
        XCTAssertEqual(tracker.target(selected: p), p)
    }

    // MARK: - SimulationController 的收藏目標座標

    func testTargetIsTheSelectedPointWithoutSimulation() throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller

        controller.select(FavoriteSpot.taipei)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.taipei)
        controller.select(FavoriteSpot.osaka)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.osaka)
    }

    func testTargetIsTheSimulatedPositionAfterASuccessfulTeleport() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller

        await teleport(controller, to: FavoriteSpot.taipei)
        // 傳送之後在地圖上點別的地方:選取點變了,收藏目標座標仍是模擬位置
        controller.select(FavoriteSpot.osaka)
        XCTAssertEqual(controller.selectedCoordinate, FavoriteSpot.osaka)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.taipei)

        // 模擬中再傳送到別處:換成新的模擬位置
        await teleport(controller, to: FavoriteSpot.pacific)
        controller.select(FavoriteSpot.mongKok)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.pacific)
    }

    /// 推送失敗之後 `status.coordinate` 還在(地圖標記也還在),但收藏目標座標和 Android 一樣回到選取點。
    func testTargetFallsBackToTheSelectedPointAfterAFailedPush() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let harness = try makeHarness(defaults)
        let controller = harness.controller

        await teleport(controller, to: FavoriteSpot.taipei)
        await harness.backend.setFailsToSetLocation(true)
        controller.select(FavoriteSpot.osaka)
        controller.start(bypassCrossDateCheck: true)
        await waitUntil("傳送失敗") { controller.lastError != nil }

        XCTAssertFalse(controller.status.isActive)
        XCTAssertEqual(controller.status.coordinate, FavoriteSpot.taipei, "status 保留失敗前的位置")
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.osaka)
        controller.select(FavoriteSpot.pacific)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.pacific)
    }

    /// 按下停止就是選取點,不等清除;清除失敗時 `status` 一直停在模擬中、停下的位置,收藏目標座標仍是選取點。
    func testTargetIsTheSelectedPointOnceStopIsPressedEvenIfClearingFails() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let harness = try makeHarness(defaults)
        let controller = harness.controller

        await teleport(controller, to: FavoriteSpot.taipei)
        controller.select(FavoriteSpot.osaka)
        await harness.backend.setFailsToClear(true)
        controller.stop()
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.osaka, "按下停止那一刻,還在等清除")

        await waitUntil("清除失敗") { controller.lastError != nil }
        XCTAssertTrue(controller.status.isActive)
        XCTAssertEqual(controller.status.coordinate, FavoriteSpot.taipei)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.osaka)
    }

    func testTargetIsTheSelectedPointAfterAStopCompletes() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller

        await teleport(controller, to: FavoriteSpot.taipei)
        controller.select(FavoriteSpot.osaka)
        controller.stop()
        await waitUntil("清除完成") { !controller.status.isActive }
        XCTAssertNil(controller.status.coordinate)
        XCTAssertNil(controller.lastError)
        XCTAssertEqual(controller.favoriteTargetCoordinate, FavoriteSpot.osaka)
    }

    // MARK: - 按 ☆ 的判斷

    func testFavoriteButtonAsksForANameWithTheTargetCoordinate() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller

        controller.select(FavoriteSpot.pacific)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: FavoriteSpot.pacific, suggestedName: "")),
            "沒有模擬:座標是選取點"
        )

        await teleport(controller, to: FavoriteSpot.osaka)
        controller.select(FavoriteSpot.pacific)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: FavoriteSpot.osaka, suggestedName: "")),
            "模擬中:座標是模擬位置,不是選取點"
        )
        XCTAssertTrue(controller.favorites.isEmpty, "按 ☆ 本身不新增")
    }

    /// 重複檢查用收藏目標座標(待決事項 1),不是選取點;已收藏時不問名稱、清單不變。
    func testFavoriteButtonOnlyShowsTheMessageWhenTheTargetIsAlreadySaved() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller
        let alreadySaved = FavoriteAddPrompt.alreadySaved(message: "此座標已經收藏過")

        // 沒有模擬,選取點已收藏
        controller.select(FavoriteSpot.taipei)
        XCTAssertEqual(controller.addFavorite(), "收藏成功")
        let saved = controller.favorites
        XCTAssertEqual(controller.favoritePrompt(), alreadySaved)
        XCTAssertEqual(controller.favorites, saved)

        // 模擬中,選取點已收藏、模擬位置沒有:照樣問名稱,座標是模擬位置(Android 0.8.7 在這裡不問名稱)
        await teleport(controller, to: FavoriteSpot.osaka)
        controller.select(FavoriteSpot.taipei)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: FavoriteSpot.osaka, suggestedName: ""))
        )

        // 模擬中,模擬位置已收藏、選取點沒有:直接顯示訊息,不問名稱
        XCTAssertEqual(controller.addFavorite(name: "大阪", coordinate: FavoriteSpot.osaka), "收藏成功")
        controller.select(FavoriteSpot.pacific)
        let savedWhileSimulating = controller.favorites
        XCTAssertEqual(controller.favoritePrompt(), alreadySaved)
        XCTAssertEqual(controller.favorites, savedWhileSimulating)
    }

    // MARK: - 預填

    func testPrefillIsTheCachedLabelOfTheTargetCellAndNeverStartsALookup() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let harness = try makeHarness(defaults, labels: [
            "25.03,121.56": "臺灣 · 臺北市",
            "34.69,135.50": "日本 · 大阪市",
        ])
        let controller = harness.controller
        XCTAssertEqual(controller.regionLabels.count, 2)

        // 同一個快取格裡的另一個座標:標籤原文
        controller.select(FavoriteSpot.taipeiSameCell)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: FavoriteSpot.taipeiSameCell, suggestedName: "臺灣 · 臺北市"))
        )
        // 從來沒查過的格子:空字串
        controller.select(FavoriteSpot.pacific)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: FavoriteSpot.pacific, suggestedName: ""))
        )
        // 模擬中看模擬位置那一格,不是選取點那一格
        await teleport(controller, to: FavoriteSpot.osaka)
        controller.select(FavoriteSpot.taipei)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: FavoriteSpot.osaka, suggestedName: "日本 · 大阪市"))
        )

        await harness.lookup.waitUntilIdle()
        let requestsAfterPrompts = await harness.nominatim.requestCount
        XCTAssertEqual(requestsAfterPrompts, 0, "按 ☆ 與預填都不送出反查")
        XCTAssertEqual(harness.lookup.labels.count, 2)

        // 對照組:真的收藏之後,新的座標才排進反查佇列(region-labels.md §3.1)
        controller.select(FavoriteSpot.pacific)
        XCTAssertEqual(controller.addFavorite(name: "太平洋", coordinate: FavoriteSpot.pacific), "收藏成功")
        await harness.lookup.waitUntilIdle()
        let requestsAfterSaving = await harness.nominatim.requestCount
        XCTAssertEqual(requestsAfterSaving, 1)
    }

    // MARK: - addFavorite(name:coordinate:)

    func testAddFavoriteSavesTheGivenCoordinateWithTheUsualNameRules() throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller
        controller.select(FavoriteSpot.mongKok)
        let first = GeoCoordinate(latitude: 1, longitude: 1)
        let second = GeoCoordinate(latitude: 2, longitude: 2)
        let third = GeoCoordinate(latitude: 3, longitude: 3)
        let fourth = GeoCoordinate(latitude: 4, longitude: 4)

        XCTAssertEqual(controller.addFavorite(name: "", coordinate: first), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.coordinate, first)
        XCTAssertEqual(controller.favorites.first?.name, "收藏 1.000000, 1.000000")
        XCTAssertEqual(controller.addFavorite(name: "   ", coordinate: second), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.name, "收藏 2.000000, 2.000000", "只有空白也用預設名稱")
        XCTAssertEqual(controller.addFavorite(name: "  旺角  ", coordinate: third), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.name, "旺角")
        XCTAssertEqual(controller.addFavorite(name: String(repeating: "路", count: 81), coordinate: fourth), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.name, String(repeating: "路", count: 80))
        XCTAssertEqual(controller.favorites.map(\.coordinate), [fourth, third, second, first], "新的在最前面")
        XCTAssertFalse(controller.favorites.contains { $0.coordinate == FavoriteSpot.mongKok }, "存的是給的座標,不是選取點")

        // 同一個座標第二次:不新增,第一筆不變
        let firstID = controller.favorites.last?.id
        XCTAssertEqual(controller.addFavorite(name: "新名字", coordinate: first), "此座標已經收藏過")
        XCTAssertEqual(controller.favorites.count, 4)
        XCTAssertEqual(controller.favorites.last?.id, firstID)
        XCTAssertEqual(controller.favorites.last?.name, "收藏 1.000000, 1.000000")
    }

    /// 預填的標籤沒有改動就直接當名稱(不修剪、不截斷的原文,存的時候照一般規則正規化)。
    func testUnchangedPrefillBecomesTheName() throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults, labels: ["25.03,121.56": "臺灣 · 臺北市"]).controller

        controller.select(FavoriteSpot.taipei)
        guard case let .askName(request) = controller.favoritePrompt() else {
            return XCTFail("沒有收藏過的座標應該問名稱")
        }
        XCTAssertEqual(controller.addFavorite(name: request.suggestedName, coordinate: request.coordinate), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.name, "臺灣 · 臺北市")
        XCTAssertEqual(controller.favorites.first?.coordinate, FavoriteSpot.taipei)
        XCTAssertEqual(controller.favoritePrompt(), .alreadySaved(message: "此座標已經收藏過"))
    }

    /// 對話框記下的是按 ☆ 那一刻的座標(待決事項 2):之後模擬位置變了,存的仍是記下的座標;
    /// 沒給座標時用當下的收藏目標座標(模擬中是模擬位置)。
    func testSavesTheCoordinateCapturedWhenTheButtonWasPressed() async throws {
        let suiteName = "gflyer.favorite-add-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = try makeHarness(defaults).controller

        await teleport(controller, to: FavoriteSpot.taipei)
        controller.select(FavoriteSpot.mongKok)
        guard case let .askName(request) = controller.favoritePrompt() else {
            return XCTFail("沒有收藏過的座標應該問名稱")
        }
        XCTAssertEqual(request.coordinate, FavoriteSpot.taipei)

        // 對話框開著時傳送到別處,按「收藏」存的仍是對話框上的座標
        await teleport(controller, to: FavoriteSpot.osaka)
        XCTAssertEqual(controller.addFavorite(name: "台北", coordinate: request.coordinate), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.coordinate, FavoriteSpot.taipei)

        controller.select(FavoriteSpot.mongKok)
        XCTAssertEqual(controller.addFavorite(), "收藏成功")
        XCTAssertEqual(controller.favorites.first?.coordinate, FavoriteSpot.osaka)
        XCTAssertEqual(controller.favorites.first?.name, "收藏 34.693700, 135.502300")
        XCTAssertFalse(controller.favorites.contains { $0.coordinate == FavoriteSpot.mongKok })
    }

    // MARK: - 輔助

    private struct Harness {
        let controller: SimulationController
        let backend: FavoriteTestBackend
        let lookup: RegionLookup
        let nominatim: FavoriteTestNominatim
    }

    /// 資料、中斷快照與標籤快取都放在測試自己的 UserDefaults suite;反查不連網、只計數。
    /// - Parameter labels: 預先放進標籤快取的「快取鍵 → 國家 · 城市」。
    private func makeHarness(_ defaults: UserDefaults, labels: [String: String] = [:]) throws -> Harness {
        if !labels.isEmpty {
            defaults.set(try JSONEncoder().encode(labels), forKey: RegionLookup.storageKey)
        }
        let nominatim = FavoriteTestNominatim()
        let lookup = RegionLookup(defaults: defaults, transport: nominatim, clock: nominatim, userAgent: "GFlyer/test (iOS)")
        let backend = FavoriteTestBackend()
        let controller = SimulationController(
            backend: backend,
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults),
            regionLookup: lookup
        )
        return Harness(controller: controller, backend: backend, lookup: lookup, nominatim: nominatim)
    }

    /// 定點傳送到 `coordinate`,等推送成功。跨日提醒和這裡無關,直接略過(否則跑測試的時區可能讓它擋住傳送)。
    private func teleport(
        _ controller: SimulationController,
        to coordinate: GeoCoordinate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        controller.select(coordinate)
        controller.start(bypassCrossDateCheck: true)
        await waitUntil("傳送到 \(coordinate.display)", file: file, line: line) {
            controller.status.coordinate == coordinate && controller.favoriteTargetCoordinate == coordinate
        }
    }

    /// 推送與清除都要經過 backend 的 actor 再回到主執行緒,所以照時間等,不數 `Task.yield()`。
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("等不到:\(description)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private enum FavoriteSpot {
    static let taipei = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
    /// 和 `taipei` 同一個快取格(25.03,121.56),座標不同。
    static let taipeiSameCell = GeoCoordinate(latitude: 25.0301, longitude: 121.5601)
    static let osaka = GeoCoordinate(latitude: 34.6937, longitude: 135.5023)
    static let pacific = GeoCoordinate(latitude: 10.0, longitude: -150.0)
    static let mongKok = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
}

/// 可以讓傳送或清除失敗的假 backend。`canControlDeviceLocation` 是 false:不需要配對檔,也不會跳去 LocalDevVPN。
private actor FavoriteTestBackend: LocationSimulationBackend {
    nonisolated let name = "測試後端"
    nonisolated let canControlDeviceLocation = false

    private var failsToSetLocation = false
    private var failsToClear = false

    func setFailsToSetLocation(_ fails: Bool) { failsToSetLocation = fails }
    func setFailsToClear(_ fails: Bool) { failsToClear = fails }

    func testConnection(pairingFileURL _: URL, pairingFileRevision _: UUID, deviceIP _: String) async throws { }

    func setLocation(
        _ coordinate: GeoCoordinate,
        pairingFileURL _: URL,
        pairingFileRevision _: UUID,
        deviceIP _: String
    ) async throws {
        if failsToSetLocation { throw FavoriteTestBackendError.setLocation }
    }

    func clearLocation(
        pairingFileURL _: URL,
        pairingFileRevision _: UUID,
        deviceIP _: String,
        tearDownSession _: Bool
    ) async throws {
        if failsToClear { throw FavoriteTestBackendError.clear }
    }
}

private enum FavoriteTestBackendError: LocalizedError {
    case setLocation
    case clear

    var errorDescription: String? {
        switch self {
        case .setLocation: return "測試用:傳送失敗"
        case .clear: return "測試用:清除失敗"
        }
    }
}

/// 不連網的反查,只數送出了幾個請求(每個都當作連線失敗),等待也不真的等。
private actor FavoriteTestNominatim: RegionLookupTransport, RegionLookupClock {
    private(set) var requestCount = 0

    func response(for request: URLRequest) async -> RegionLookupResponse? {
        requestCount += 1
        return nil
    }

    func sleep(seconds: TimeInterval) async { }
}
