import XCTest
@testable import GFlyerIOS

/// ☆ 的命名 sheet 插隊反查(`RegionLookup.lookUpUrgently`;GFlyer-Suite docs/features/region-labels.md §3.3、§3.6,
/// favorite-add.md 第 6 節的 iOS 0.6.11 單元測試,對照 Android `RegionLookupQueueTest`):
/// 插隊的順序、和一般請求共用的 1.1 秒間隔、同一格在佇列裡最多一筆、緊急請求失敗不封鎖而一般請求失敗封鎖、
/// 等待者一定拿到結果、等待的一方不等了也不撤回請求。
///
/// 假的 Nominatim 可以讓請求停在半路(正在查),測試趁這時候插進緊急請求,再看佇列(`pendingCoordinates`)
/// 與事件的順序。「GET 緯度,經度」是送出的 lat / lon 原文,「sleep 1.1」是請求結束之後的等待。
@MainActor
final class RegionLookupUrgentTests: XCTestCase {

    // MARK: - 順序

    func testUrgentRequestsGoToTheFrontNewestFirstAndLaterNormalRequestsStayBehind() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        nominatim.respond(to: UrgentSpot.seoul, city: "首爾", country: "南韓")
        nominatim.respond(to: UrgentSpot.london, city: "倫敦", country: "英國")
        let lookup = makeLookup(defaults, nominatim)

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.taipei, UrgentSpot.osaka, UrgentSpot.sydney])
        await waitUntil("臺北正在查") { nominatim.isHoldingARequest }
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.osaka, UrgentSpot.sydney])

        let seoul = Task { await lookup.lookUpUrgently(UrgentSpot.seoul) }
        await waitUntil("首爾排進佇列") { lookup.pendingCoordinates.count == 3 }
        XCTAssertEqual(
            lookup.pendingCoordinates,
            [UrgentSpot.seoul, UrgentSpot.osaka, UrgentSpot.sydney],
            "緊急請求排在所有一般請求前面;正在查的那一筆不中斷"
        )
        let london = Task { await lookup.lookUpUrgently(UrgentSpot.london) }
        await waitUntil("倫敦排進佇列") { lookup.pendingCoordinates.count == 4 }
        XCTAssertEqual(
            lookup.pendingCoordinates,
            [UrgentSpot.london, UrgentSpot.seoul, UrgentSpot.osaka, UrgentSpot.sydney],
            "最新的緊急請求最先"
        )
        lookup.request([UrgentSpot.newYork])
        XCTAssertEqual(
            lookup.pendingCoordinates,
            [UrgentSpot.london, UrgentSpot.seoul, UrgentSpot.osaka, UrgentSpot.sydney, UrgentSpot.newYork],
            "之後才來的一般請求排在隊尾,不會超過緊急請求"
        )

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.events, [
            "GET 25.0339,121.5645", "sleep 1.1",
            "GET 51.5072,-0.1276", "sleep 1.1",
            "GET 37.5665,126.978", "sleep 1.1",
            "GET 34.6937,135.5023", "sleep 1.1",
            "GET -33.8688,151.2093", "sleep 1.1",
            "GET 40.7128,-74.006", "sleep 1.1",
        ])
        XCTAssertEqual(nominatim.maxInFlight, 1, "同一時間最多一個請求")
        let seoulLabel = await seoul.value
        let londonLabel = await london.value
        XCTAssertEqual(seoulLabel, "南韓 · 首爾")
        XCTAssertEqual(londonLabel, "英國 · 倫敦")
    }

    /// 同一格在佇列裡最多一筆:還沒送出的那一筆搬到最前面、換成這次按 ☆ 的那一點;連按也一樣只有一筆(最後按的那一點)。
    func testAnUrgentRequestForAQueuedCellMovesThatEntryToTheFrontWithTheNewPoint() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        nominatim.respond(to: UrgentSpot.taipei, city: "臺北市", country: "臺灣")
        let lookup = makeLookup(defaults, nominatim)

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.osaka, UrgentSpot.taipeiSameCell, UrgentSpot.sydney])
        await waitUntil("大阪正在查") { nominatim.isHoldingARequest }
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.taipeiSameCell, UrgentSpot.sydney])

        // 同一格的另一點(按 ☆ 的那一點)
        let first = Task { await lookup.lookUpUrgently(UrgentSpot.taipeiOtherPoint) }
        await waitUntil("搬到最前面") { lookup.pendingCoordinates.first == UrgentSpot.taipeiOtherPoint }
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.taipeiOtherPoint, UrgentSpot.sydney], "仍只有一筆,換成按 ☆ 的那一點")

        // 再按一次 ☆(同一格又一點):仍只有一筆,換成最後按的那一點
        let second = Task { await lookup.lookUpUrgently(UrgentSpot.taipei) }
        await waitUntil("換成最後按的那一點") { lookup.pendingCoordinates.first == UrgentSpot.taipei }
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.taipei, UrgentSpot.sydney])
        XCTAssertEqual(lookup.waiterCount(for: UrgentSpot.taipei), 2)
        // 一般請求再送同一格:已經在佇列裡,不重複排
        lookup.request([UrgentSpot.taipeiSameCell, UrgentSpot.taipeiOtherPoint])
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.taipei, UrgentSpot.sydney])

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        await lookup.waitUntilIdle()
        XCTAssertEqual(
            nominatim.requested,
            ["34.6937,135.5023", "25.0339,121.5645", "-33.8688,151.2093"],
            "臺北那一格只送一次,送的是最後按 ☆ 的原始座標"
        )
        let firstLabel = await first.value
        let secondLabel = await second.value
        XCTAssertEqual(firstLabel, "臺灣 · 臺北市")
        XCTAssertEqual(secondLabel, "臺灣 · 臺北市")
    }

    // MARK: - 已有快取、被封鎖、正在查

    func testCachedAndBlockedCellsAreNotSent() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(["25.03,121.56": "臺灣 · 臺北市"]), forKey: RegionLookup.storageKey)
        let nominatim = UrgentTestNominatim()
        let lookup = makeLookup(defaults, nominatim)

        // 已有快取(同一格的另一點):直接回傳標籤,不排、不送
        let cached = await lookup.lookUpUrgently(UrgentSpot.taipeiSameCell)
        XCTAssertEqual(cached, "臺灣 · 臺北市")
        XCTAssertEqual(lookup.pendingCoordinates, [])
        XCTAssertEqual(nominatim.events, [])

        // 一般請求查失敗(海上沒有回應 = 連線失敗)就封鎖到下次啟動
        lookup.request([UrgentSpot.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested, ["10.0,-150.0"])
        let blocked = await lookup.lookUpUrgently(UrgentSpot.pacific)
        XCTAssertNil(blocked, "被封鎖:馬上當作查不到")
        lookup.request([UrgentSpot.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested, ["10.0,-150.0"], "被封鎖的格子一般與緊急請求都不再送")
        XCTAssertEqual(lookup.pendingCoordinates, [])
    }

    func testAnUrgentRequestForACellInFlightWaitsForThatRequest() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        nominatim.respond(to: UrgentSpot.taipei, city: "臺北市", country: "臺灣")
        let lookup = makeLookup(defaults, nominatim)

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.taipei])
        await waitUntil("臺北正在查") { nominatim.isHoldingARequest }
        let waiting = Task { await lookup.lookUpUrgently(UrgentSpot.taipeiSameCell) }
        await waitUntil("等那一筆") { lookup.waiterCount(for: UrgentSpot.taipeiSameCell) == 1 }
        XCTAssertEqual(lookup.pendingCoordinates, [], "正在查的格子不再排")

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        let label = await waiting.value
        XCTAssertEqual(label, "臺灣 · 臺北市")
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested, ["25.0339,121.5645"], "沒有多送")
    }

    /// 緊急請求等的是正在查的一般請求時,那一筆仍算一般請求:查失敗照一般規則封鎖。
    func testAFailedNormalRequestThatAnUrgentRequestWaitedForStillBlocksTheCell() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        let lookup = makeLookup(defaults, nominatim)

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.pacific])
        await waitUntil("太平洋正在查") { nominatim.isHoldingARequest }
        let waiting = Task { await lookup.lookUpUrgently(UrgentSpot.pacific) }
        await waitUntil("等那一筆") { lookup.waiterCount(for: UrgentSpot.pacific) == 1 }

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        let label = await waiting.value
        XCTAssertNil(label)
        await lookup.waitUntilIdle()

        let again = await lookup.lookUpUrgently(UrgentSpot.pacific)
        XCTAssertNil(again)
        lookup.request([UrgentSpot.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested, ["10.0,-150.0"], "封鎖了:一般與緊急請求都不再送")
    }

    // MARK: - 失敗

    /// 緊急請求查失敗不封鎖:再按 ☆ 會再送;之後一次一般請求(收藏存下去)也還能再查,那一次也失敗才封鎖到下次啟動。
    /// 每次都照 1.1 秒的間隔,也不會自己重試。
    func testAFailedUrgentLookupDoesNotBlockTheCellButTheNextFailedNormalRequestDoes() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        let lookup = makeLookup(defaults, nominatim)

        let first = await lookup.lookUpUrgently(UrgentSpot.pacific)
        XCTAssertNil(first)
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested, ["10.0,-150.0"])
        XCTAssertEqual(lookup.pendingCoordinates, [], "不會自己重試")

        let pressedAgain = await lookup.lookUpUrgently(UrgentSpot.pacific)
        XCTAssertNil(pressedAgain)
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested.count, 2, "再按 ☆:再插隊送一次")

        lookup.request([UrgentSpot.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested.count, 3, "之後的一般請求還能再查一次")

        let blocked = await lookup.lookUpUrgently(UrgentSpot.pacific)
        XCTAssertNil(blocked)
        lookup.request([UrgentSpot.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.events, [
            "GET 10.0,-150.0", "sleep 1.1",
            "GET 10.0,-150.0", "sleep 1.1",
            "GET 10.0,-150.0", "sleep 1.1",
        ], "一般請求也失敗之後封鎖到下次啟動;失敗照樣佔用 1.1 秒的間隔")
        XCTAssertNil(RegionLabel.label(in: lookup.labels, for: UrgentSpot.pacific))
        XCTAssertNil(defaults.data(forKey: RegionLookup.storageKey), "失敗不寫進持久化快取")
    }

    /// 緊急請求查失敗後連按 ☆:每次都再排,但同一格在佇列裡仍只有一筆(最後按的那一點),照樣排隊、不連發。
    func testPressingAgainAfterAFailedUrgentLookupStillLeavesOneEntryPerCell() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        let lookup = makeLookup(defaults, nominatim)

        let failed = await lookup.lookUpUrgently(UrgentSpot.pacific)
        XCTAssertNil(failed)

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.osaka])
        await waitUntil("大阪正在查") { nominatim.isHoldingARequest }
        let again1 = Task { await lookup.lookUpUrgently(UrgentSpot.pacific) }
        await waitUntil("再排一次") { lookup.pendingCoordinates == [UrgentSpot.pacific] }
        let again2 = Task { await lookup.lookUpUrgently(UrgentSpot.pacificOtherPoint) }
        await waitUntil("換成最後按的那一點") { lookup.pendingCoordinates.first == UrgentSpot.pacificOtherPoint }
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.pacificOtherPoint], "同一格只有一筆")

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.events, [
            "GET 10.0,-150.0", "sleep 1.1",
            "GET 34.6937,135.5023", "sleep 1.1",
            "GET 10.001,-150.001", "sleep 1.1",
        ])
        let results = await [again1.value, again2.value]
        XCTAssertEqual(results, [nil, nil])
    }

    /// 緊急請求查失敗後一般請求再查,這次查到了:照樣寫進快取,之後在同一格按 ☆ 直接拿到標籤。
    func testAFailedUrgentLookupCanStillBeFoundByTheNextNormalRequest() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        let lookup = makeLookup(defaults, nominatim)

        let offline = await lookup.lookUpUrgently(UrgentSpot.osaka)
        XCTAssertNil(offline)
        nominatim.respond(to: UrgentSpot.osaka, city: "大阪市", country: "日本")
        lookup.request([UrgentSpot.osaka])
        await lookup.waitUntilIdle()
        XCTAssertEqual(lookup.labels, ["34.69,135.50": "日本 · 大阪市"])

        let cached = await lookup.lookUpUrgently(UrgentSpot.osaka)
        XCTAssertEqual(cached, "日本 · 大阪市")
        XCTAssertEqual(nominatim.requested, ["34.6937,135.5023", "34.6937,135.5023"])
    }

    // MARK: - 間隔

    func testUrgentRequestsKeepTheGapAndGoStraightOutWhenTheQueueIsIdle() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        nominatim.respond(to: UrgentSpot.taipei, city: "臺北市", country: "臺灣")
        nominatim.respond(to: UrgentSpot.osaka, city: "大阪市", country: "日本")
        nominatim.respond(to: UrgentSpot.seoul, city: "首爾", country: "南韓")
        nominatim.respond(to: UrgentSpot.london, city: "倫敦", country: "英國")
        let lookup = makeLookup(defaults, nominatim)

        // 一般請求進行中插進緊急請求:等那一筆結束、再等 1.1 秒才送,而且排在下一個一般請求前面
        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.taipei, UrgentSpot.osaka])
        await waitUntil("臺北正在查") { nominatim.isHoldingARequest }
        let seoul = Task { await lookup.lookUpUrgently(UrgentSpot.seoul) }
        await waitUntil("首爾排進佇列") { lookup.pendingCoordinates.first == UrgentSpot.seoul }
        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.events, [
            "GET 25.0339,121.5645", "sleep 1.1",
            "GET 37.5665,126.978", "sleep 1.1",
            "GET 34.6937,135.5023", "sleep 1.1",
        ])
        let seoulLabel = await seoul.value
        XCTAssertEqual(seoulLabel, "南韓 · 首爾")

        // 佇列閒著、上一次的間隔已經等完:緊急請求馬上送,之後照樣等
        let london = await lookup.lookUpUrgently(UrgentSpot.london)
        XCTAssertEqual(london, "英國 · 倫敦")
        await lookup.waitUntilIdle()
        XCTAssertEqual(Array(nominatim.events.dropFirst(6)), ["GET 51.5072,-0.1276", "sleep 1.1"])

        // 沒有失敗時,同一格整個過程只送一次
        let seoulAgain = await lookup.lookUpUrgently(UrgentSpot.seoul)
        XCTAssertEqual(seoulAgain, "南韓 · 首爾")
        lookup.request([UrgentSpot.taipei, UrgentSpot.osaka, UrgentSpot.seoul, UrgentSpot.london])
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested.count, 4)
        XCTAssertEqual(nominatim.maxInFlight, 1)
    }

    // MARK: - 等待者

    func testEveryWaiterOfACellGetsTheResult() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        nominatim.respond(to: UrgentSpot.taipeiSameCell, city: "臺北市", country: "臺灣")
        let lookup = makeLookup(defaults, nominatim)

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.osaka])
        await waitUntil("大阪正在查") { nominatim.isHoldingARequest }
        // sheet 關掉又在同一格打開:同一格有兩個等待者;查不到的格子也一樣
        let found1 = Task { await lookup.lookUpUrgently(UrgentSpot.taipei) }
        await waitUntil("臺北第一個等待者") { lookup.waiterCount(for: UrgentSpot.taipei) == 1 }
        let found2 = Task { await lookup.lookUpUrgently(UrgentSpot.taipeiSameCell) }
        await waitUntil("臺北第二個等待者") { lookup.waiterCount(for: UrgentSpot.taipei) == 2 }
        let lost1 = Task { await lookup.lookUpUrgently(UrgentSpot.pacific) }
        await waitUntil("太平洋第一個等待者") { lookup.waiterCount(for: UrgentSpot.pacific) == 1 }
        let lost2 = Task { await lookup.lookUpUrgently(UrgentSpot.pacific) }
        await waitUntil("太平洋第二個等待者") { lookup.waiterCount(for: UrgentSpot.pacific) == 2 }
        XCTAssertEqual(lookup.pendingCoordinates, [UrgentSpot.pacific, UrgentSpot.taipeiSameCell], "每一格仍只有一筆")

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        await lookup.waitUntilIdle()
        let labels = await [found1.value, found2.value, lost1.value, lost2.value]
        XCTAssertEqual(labels, ["臺灣 · 臺北市", "臺灣 · 臺北市", nil, nil])
        XCTAssertEqual(lookup.waiterCount(for: UrgentSpot.taipei), 0)
        XCTAssertEqual(lookup.waiterCount(for: UrgentSpot.pacific), 0)
    }

    /// sheet 關掉(等待的 Task 被取消)不撤回請求:照樣送出、照樣寫進快取,結果也照樣交回來。
    func testAWaiterThatStopsWaitingDoesNotWithdrawTheRequest() async throws {
        let suiteName = "gflyer.region-urgent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = UrgentTestNominatim()
        nominatim.respond(to: UrgentSpot.seoul, city: "首爾", country: "南韓")
        let lookup = makeLookup(defaults, nominatim)
        var published: [[String: String]] = []
        lookup.onLabelsChange = { published.append($0) }

        nominatim.holdsRequests = true
        lookup.request([UrgentSpot.osaka])
        await waitUntil("大阪正在查") { nominatim.isHoldingARequest }
        let waiting = Task { await lookup.lookUpUrgently(UrgentSpot.seoul) }
        await waitUntil("首爾排進佇列") { lookup.pendingCoordinates == [UrgentSpot.seoul] }
        waiting.cancel()

        nominatim.holdsRequests = false
        nominatim.finishHeldRequest()
        await lookup.waitUntilIdle()
        XCTAssertEqual(nominatim.requested, ["34.6937,135.5023", "37.5665,126.978"], "照樣送出")
        XCTAssertEqual(lookup.labels, ["37.57,126.98": "南韓 · 首爾"])
        XCTAssertEqual(published, [["37.57,126.98": "南韓 · 首爾"]], "清單照樣更新")
        let stored = try XCTUnwrap(defaults.data(forKey: RegionLookup.storageKey))
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: stored), ["37.57,126.98": "南韓 · 首爾"])
        let label = await waiting.value
        XCTAssertEqual(label, "南韓 · 首爾", "等待用的 continuation 不跟著取消")
    }

    // MARK: - 輔助

    private func makeLookup(_ defaults: UserDefaults, _ nominatim: UrgentTestNominatim) -> RegionLookup {
        RegionLookup(defaults: defaults, transport: nominatim, clock: nominatim, userAgent: "GFlyer/test (iOS)")
    }

    /// 佇列的工作與等待者都在主執行緒上排隊執行,所以照時間等、讓它們跑,不數 `Task.yield()`。
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

/// 假的 Nominatim,同時當 transport 與時鐘,和 `RegionLookup` 一樣在主執行緒上,測試可以直接讀它的狀態。
/// 依序記下每一次請求(「GET 緯度,經度」,寫法和送出的 lat / lon 相同)與等待(「sleep 秒數」),依座標回應;
/// 沒有設定回應的座標當作連線失敗。`holdsRequests` 打開時每個請求都停在半路(正在查),等 `finishHeldRequest()`
/// 才回應。等待只記錄、不真的等。
@MainActor
private final class UrgentTestNominatim: RegionLookupTransport, RegionLookupClock {
    private(set) var events: [String] = []
    private(set) var maxInFlight = 0
    var holdsRequests = false
    private var inFlight = 0
    private var responses: [String: RegionLookupResponse] = [:]
    private var held: [CheckedContinuation<Void, Never>] = []

    /// 送出請求的座標,依時間順序。
    var requested: [String] {
        events.filter { $0.hasPrefix("GET ") }.map { String($0.dropFirst(4)) }
    }

    var isHoldingARequest: Bool { !held.isEmpty }

    func respond(to coordinate: GeoCoordinate, city: String, country: String) {
        let key = "\(String(coordinate.latitude)),\(String(coordinate.longitude))"
        let body = #"{"address":{"city":"\#(city)","country":"\#(country)"}}"#
        responses[key] = RegionLookupResponse(statusCode: 200, body: Data(body.utf8))
    }

    /// 讓停在半路的第一個請求回應。
    func finishHeldRequest() {
        guard !held.isEmpty else { return }
        held.removeFirst().resume()
    }

    func response(for request: URLRequest) async -> RegionLookupResponse? {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let latitude = items.first { $0.name == "lat" }?.value ?? "?"
        let longitude = items.first { $0.name == "lon" }?.value ?? "?"
        let key = "\(latitude),\(longitude)"
        events.append("GET \(key)")
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if holdsRequests {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                held.append(continuation)
            }
        } else {
            // 讓出執行權:要是同時有第二個請求,它會在這裡插進來、把 maxInFlight 推到 2
            await Task.yield()
        }
        inFlight -= 1
        return responses[key]
    }

    func sleep(seconds: TimeInterval) async {
        events.append("sleep \(seconds)")
    }
}

private enum UrgentSpot {
    static let taipei = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
    /// 和 `taipei` 同一個快取格(25.03,121.56),座標不同。
    static let taipeiSameCell = GeoCoordinate(latitude: 25.0301, longitude: 121.5601)
    /// 也在 25.03,121.56 那一格。
    static let taipeiOtherPoint = GeoCoordinate(latitude: 25.0312, longitude: 121.5633)
    static let osaka = GeoCoordinate(latitude: 34.6937, longitude: 135.5023)
    static let sydney = GeoCoordinate(latitude: -33.8688, longitude: 151.2093)
    static let newYork = GeoCoordinate(latitude: 40.7128, longitude: -74.006)
    static let london = GeoCoordinate(latitude: 51.5072, longitude: -0.1276)
    static let seoul = GeoCoordinate(latitude: 37.5665, longitude: 126.978)
    /// 海上,假的 Nominatim 沒有回應(連線失敗)。
    static let pacific = GeoCoordinate(latitude: 10.0, longitude: -150.0)
    /// 也在 10.00,-150.00 那一格。
    static let pacificOtherPoint = GeoCoordinate(latitude: 10.001, longitude: -150.001)
}
