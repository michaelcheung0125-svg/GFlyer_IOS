import XCTest
@testable import GFlyerIOS

/// 收藏清單的「國家 · 城市」標籤(GFlyer-Suite docs/features/region-labels.md),兩個版本都跑。
///
/// 快取鍵那一段照抄 GFlyer-Suite `contracts/fixtures/region/nominatim-labels.json` 的 `cacheKeys`(2026-09-28 抄寫);
/// iOS 的 CI 拿不到那個 repo,fixture 改了這裡要跟著改。標籤的組法每個版本不同:親友版的 Nominatim 在
/// `Family/NominatimRegionLabelTests`,公開版的 Apple 地點服務在 `Public/AppleGeocoderRegionLabelTests`。
///
/// 佇列、1.1 秒間隔、失敗不重試是有狀態的排程行為,不在 fixture 裡,用假的反查服務與時鐘測。
@MainActor
final class RegionLabelTests: XCTestCase {

    // MARK: - fixture:cacheKeys

    func testCacheKeysMatchFixture() {
        let cases: [(name: String, latitude: Double, longitude: Double, expected: String)] = [
            ("taipei-101", 25.0339, 121.5645, "25.03,121.56"),
            ("same-cell-as-taipei-101", 25.0301, 121.5601, "25.03,121.56"),
            ("rounds-up", 25.0351, 121.5649, "25.04,121.56"),
            ("southern-and-eastern", -33.8688, 151.2093, "-33.87,151.21"),
            ("western", 40.7128, -74.006, "40.71,-74.01"),
            ("origin", 0.0, 0.0, "0.00,0.00"),
            ("negative-values-that-round-to-zero-keep-the-sign", -0.001, -0.004, "-0.00,-0.00"),
            ("upper-bounds", 90.0, 180.0, "90.00,180.00"),
            ("lower-bounds", -90.0, -180.0, "-90.00,-180.00"),
        ]
        XCTAssertEqual(cases.count, 9, "fixture 的 cacheKeys 全部抄進來")
        for testCase in cases {
            let coordinate = GeoCoordinate(latitude: testCase.latitude, longitude: testCase.longitude)
            XCTAssertEqual(RegionLabel.key(for: coordinate), testCase.expected, testCase.name)
        }
    }

    // MARK: - 佇列與快取

    func testRequestsGoOneAtATimeInOrderWithAGapAfterEach() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeRegionLabelSource()
        await service.respond(to: Place.taipei, label: "臺灣 · 臺北市")
        await service.respond(to: Place.osaka, label: "日本 · 大阪市")
        let lookup = makeLookup(defaults, service)

        lookup.request([Place.taipei, Place.pacific, Place.osaka])
        lookup.request([Place.sydney])
        await lookup.waitUntilIdle()

        // 第一筆不等;每次真的送出請求之後都等 1.1 秒,連線失敗(太平洋、雪梨沒有回應)也一樣
        var events = await service.events
        XCTAssertEqual(events, [
            "GET 25.0339,121.5645", "sleep 1.1",
            "GET 10.0,-150.0", "sleep 1.1",
            "GET 34.6937,135.5023", "sleep 1.1",
            "GET -33.8688,151.2093", "sleep 1.1",
        ])
        let maxInFlight = await service.maxInFlight
        XCTAssertEqual(maxInFlight, 1, "同一時間最多一個請求")
        XCTAssertEqual(lookup.labels, ["25.03,121.56": "臺灣 · 臺北市", "34.69,135.50": "日本 · 大阪市"])

        // 佇列清空之後再排:上一次請求之後的間隔已經等完,新的一筆直接送出,之後照樣等
        lookup.request([Place.newYork])
        await lookup.waitUntilIdle()
        events = await service.events
        XCTAssertEqual(Array(events.dropFirst(8)), ["GET 40.7128,-74.006", "sleep 1.1"])
    }

    func testCachedQueuedAndFailedKeysAreNotSentAgain() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(["34.69,135.50": "日本 · 大阪市"]), forKey: RegionLookup.storageKey)
        let service = FakeRegionLabelSource()
        await service.respond(to: Place.taipei, label: "臺灣 · 臺北市")
        let lookup = makeLookup(defaults, service)
        XCTAssertEqual(lookup.labels, ["34.69,135.50": "日本 · 大阪市"], "啟動時讀回快取")
        var published: [[String: String]] = []
        lookup.onLabelsChange = { published.append($0) }

        let list = [Place.taipei, Place.taipeiSameCell, Place.osaka, Place.pacific]
        lookup.request(list)
        lookup.request(list)
        await lookup.waitUntilIdle()

        // 同一格只送第一個排進來的座標;已經有快取的不送、也不等;排過隊的不重複排
        var events = await service.events
        XCTAssertEqual(events, ["GET 25.0339,121.5645", "sleep 1.1", "GET 10.0,-150.0", "sleep 1.1"])
        XCTAssertEqual(published, [["34.69,135.50": "日本 · 大阪市", "25.03,121.56": "臺灣 · 臺北市"]])
        XCTAssertEqual(RegionLabel.label(in: lookup.labels, for: Place.taipeiSameCell), "臺灣 · 臺北市", "同一格共用")
        XCTAssertNil(RegionLabel.label(in: lookup.labels, for: Place.pacific), "查不到的沒有標籤")

        // 呼叫端很頻繁地送同一份清單:查到的與這次失敗過的都不再送
        lookup.request(list)
        await lookup.waitUntilIdle()
        events = await service.events
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(published.count, 1)
    }

    func testFailuresAreNotCachedAndAreRetriedOnTheNextLaunch() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = FakeRegionLabelSource()
        await first.respond(to: Place.taipei, label: "臺灣 · 臺北市")
        // 大阪(例如被限流)和太平洋都查不到
        let lookup = makeLookup(defaults, first)
        lookup.request([Place.taipei, Place.osaka, Place.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(try storedLabels(defaults), ["25.03,121.56": "臺灣 · 臺北市"], "失敗不寫進持久化快取")

        // 下次啟動:讀回快取,查到的不再送,失敗的各再試一次
        let second = FakeRegionLabelSource()
        await second.respond(to: Place.osaka, label: "日本 · 大阪市")
        let relaunched = makeLookup(defaults, second)
        XCTAssertEqual(relaunched.labels, ["25.03,121.56": "臺灣 · 臺北市"])
        relaunched.request([Place.taipei, Place.osaka, Place.pacific])
        await relaunched.waitUntilIdle()
        let events = await second.events
        XCTAssertEqual(events, ["GET 34.6937,135.5023", "sleep 1.1", "GET 10.0,-150.0", "sleep 1.1"])
        XCTAssertEqual(try storedLabels(defaults), [
            "25.03,121.56": "臺灣 · 臺北市",
            "34.69,135.50": "日本 · 大阪市",
        ])
    }

    func testUnreadableCacheIsEmptyAndLeavesOtherDataAlone() throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = Data(#"{"favorites":[]}"#.utf8)
        defaults.set(snapshot, forKey: "gflyer.local-data.v1")

        defaults.set(Data("不是 JSON".utf8), forKey: RegionLookup.storageKey)
        XCTAssertEqual(makeLookup(defaults, FakeRegionLabelSource()).labels, [:])
        defaults.set(Data(#"{"25.03,121.56":1}"#.utf8), forKey: RegionLookup.storageKey)
        XCTAssertEqual(makeLookup(defaults, FakeRegionLabelSource()).labels, [:])
        defaults.set("臺灣 · 臺北市", forKey: RegionLookup.storageKey)
        XCTAssertEqual(makeLookup(defaults, FakeRegionLabelSource()).labels, [:])
        XCTAssertEqual(defaults.data(forKey: "gflyer.local-data.v1"), snapshot, "其他資料不受影響")
    }

    // MARK: - SimulationController 與清單文字

    /// 收藏位置依清單順序、接著是收藏路線的第一點;定位歷史不查(§3.1)。之後收藏一變就把新的排進來。
    func testControllerRequestsFavoritesThenRouteStartsButNeverHistory() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        store.addFavorite(name: "大阪", coordinate: Place.osaka)
        store.addFavorite(name: "台北", coordinate: Place.taipei)
        store.saveRoute(name: "雪梨", points: [Place.sydney, Place.osaka], loop: false)
        store.saveRoute(name: "紐約", points: [Place.newYork, Place.london], loop: true)
        store.addHistory(coordinate: Place.london)
        store.addHistory(coordinate: Place.pacific)
        store.addHistory(coordinate: Place.taipeiSameCell)
        let service = FakeRegionLabelSource()
        await service.respond(to: Place.taipei, label: "臺灣 · 臺北市")
        await service.respond(to: Place.newYork, label: "美國 · 紐約")
        let lookup = makeLookup(defaults, service)

        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: store,
            sessionStore: ActiveSessionStore(defaults: defaults),
            regionLookup: lookup
        )
        XCTAssertEqual(controller.favorites.map(\.name), ["台北", "大阪"])
        XCTAssertEqual(controller.savedRoutes.map(\.name), ["紐約", "雪梨"])
        await lookup.waitUntilIdle()

        // 建立時就送出,不等清單打開
        var requested = await service.requested
        XCTAssertEqual(requested, ["25.0339,121.5645", "34.6937,135.5023", "40.7128,-74.006", "-33.8688,151.2093"])
        XCTAssertEqual(controller.regionLabels, ["25.03,121.56": "臺灣 · 臺北市", "40.71,-74.01": "美國 · 紐約"])
        // 收藏位置與歷史的標籤接在第三行的時間後面(2026-10-08 起,region-labels.md §3.8)
        let savedAt = Date(timeIntervalSince1970: 1_790_401_200)
        let dateTime = DateFormatter.localizedString(from: savedAt, dateStyle: .medium, timeStyle: .short)
        XCTAssertEqual(
            placeTimeLine(LibraryRowText.favoriteSavedPrefix, Place.taipei, at: savedAt, labels: controller.regionLabels),
            "收藏於 " + dateTime + "  ·  臺灣 · 臺北市"
        )
        XCTAssertEqual(
            LibraryRowText.route(controller.savedRoutes[0], labels: controller.regionLabels),
            "2 個點 · 循環 · 美國 · 紐約"
        )
        XCTAssertEqual(LibraryRowText.route(controller.savedRoutes[1], labels: controller.regionLabels), "2 個點 · 單程")
        // 歷史只在剛好和某個收藏落在同一格時顯示標籤
        XCTAssertEqual(
            placeTimeLine(LibraryRowText.historySavedPrefix, Place.taipeiSameCell, at: savedAt, labels: controller.regionLabels),
            "定位於 " + dateTime + "  ·  臺灣 · 臺北市"
        )
        XCTAssertEqual(
            placeTimeLine(LibraryRowText.historySavedPrefix, Place.pacific, at: savedAt, labels: controller.regionLabels),
            "定位於 " + dateTime
        )

        // 收藏變動時把新的座標排進來
        controller.select(Place.seoul)
        XCTAssertEqual(controller.addFavorite(name: "首爾"), SimulationController.favoriteAddedMessage)
        await lookup.waitUntilIdle()
        requested = await service.requested
        XCTAssertEqual(requested.count, 5)
        XCTAssertEqual(requested.last, "37.5665,126.978")

        // 刪掉收藏不清快取,再加回同一點也不再送
        let taipeiID = try XCTUnwrap(controller.favorites.first { $0.name == "台北" }?.id)
        controller.removeFavorite(taipeiID)
        controller.select(Place.taipei)
        controller.addFavorite()
        await lookup.waitUntilIdle()
        requested = await service.requested
        XCTAssertEqual(requested.count, 5)
        XCTAssertEqual(controller.regionLabels["25.03,121.56"], "臺灣 · 臺北市")

        // 標籤不進備份
        let backup = try XCTUnwrap(controller.exportBackupData())
        let text = try XCTUnwrap(String(data: backup, encoding: .utf8))
        XCTAssertFalse(text.contains("臺灣"), text)
        XCTAssertFalse(text.contains("美國"), text)
    }

    func testRowTextsMatchAndroid() {
        let labels = ["25.03,121.56": "臺灣 · 臺北市"]
        // 收藏位置與歷史的第二行只有座標(2026-10-08 起;標籤移到第三行,見下面與 SavedPlaceRowTextTests)
        XCTAssertEqual(Place.taipei.display, "25.033900, 121.564500")
        XCTAssertEqual(Place.osaka.display, "34.693700, 135.502300")

        let twelve = (0..<12).map { GeoCoordinate(latitude: 25.0339 + Double($0) * 0.001, longitude: 121.5645) }
        XCTAssertEqual(
            LibraryRowText.route(SavedRoute(name: "臺北", points: twelve, loop: true), labels: labels),
            "12 個點 · 循環 · 臺灣 · 臺北市"
        )
        XCTAssertEqual(LibraryRowText.route(SavedRoute(name: "臺北", points: twelve, loop: false), labels: [:]), "12 個點 · 單程")

        // 日期時間跟系統語言與時區(中等日期 + 短時間);前綴與後面的半形空白必須一字不差
        let date = Date(timeIntervalSince1970: 1_790_401_200)
        let dateTime = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        // 收藏位置與歷史:時間後面接「  ·  」+ 標籤,沒有標籤時連同分隔一起省略;收藏路線只有時間
        XCTAssertEqual(
            placeTimeLine(LibraryRowText.favoriteSavedPrefix, Place.taipei, at: date, labels: labels),
            "收藏於 " + dateTime + "  ·  臺灣 · 臺北市"
        )
        XCTAssertEqual(placeTimeLine(LibraryRowText.favoriteSavedPrefix, Place.osaka, at: date, labels: labels), "收藏於 " + dateTime)
        XCTAssertEqual(placeTimeLine(LibraryRowText.historySavedPrefix, Place.osaka, at: date, labels: labels), "定位於 " + dateTime)
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.routeSavedPrefix, at: date), "儲存於 " + dateTime)
    }

    // MARK: - 輔助

    /// 收藏位置與定位歷史的第三行,標籤照清單的查法(`SavedPlacesView.libraryRowLabel`)從快取表取。
    private func placeTimeLine(_ prefix: String, _ coordinate: GeoCoordinate, at date: Date, labels: [String: String]) -> String {
        LibraryRowText.saved(prefix, at: date, label: RegionLabel.label(in: labels, for: coordinate))
    }

    /// 不用先取得同意,兩個版本跑的都是親友版的行為;要先問的在 `RegionLookupConsentTests`。
    private func makeLookup(_ defaults: UserDefaults, _ service: FakeRegionLabelSource) -> RegionLookup {
        RegionLookup(defaults: defaults, source: service, clock: service, asksFirst: false)
    }

    private func storedLabels(_ defaults: UserDefaults) throws -> [String: String] {
        let data = try XCTUnwrap(defaults.data(forKey: RegionLookup.storageKey))
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}

/// 不連網的反查:每個請求都當作查不到,等待也不真的等。其他測試建 `SimulationController`、而且會有收藏或
/// 路線時用 `RegionLookup.offline(defaults:)`,單元測試才不會真的去查。不用先取得同意,兩個版本行為相同。
struct OfflineRegionLookup: RegionLabelSource, RegionLookupClock {
    func label(for coordinate: GeoCoordinate) async -> String? { nil }
    func sleep(seconds: TimeInterval) async {}
}

extension RegionLookup {
    static func offline(defaults: UserDefaults) -> RegionLookup {
        RegionLookup(defaults: defaults, source: OfflineRegionLookup(), clock: OfflineRegionLookup(), asksFirst: false)
    }
}

/// 假的反查服務,同時當時鐘:依序記下每一次請求(「GET 緯度,經度」,寫法和 Nominatim 送出的 lat / lon 相同)
/// 與等待(「sleep 秒數」),依座標回應;沒有設定標籤的座標當作查不到。等待只記錄、不真的等。
private actor FakeRegionLabelSource: RegionLabelSource, RegionLookupClock {
    private(set) var events: [String] = []
    private(set) var maxInFlight = 0
    private var inFlight = 0
    private var labels: [String: String] = [:]

    /// 送出請求的座標,依時間順序。
    var requested: [String] {
        events.filter { $0.hasPrefix("GET ") }.map { String($0.dropFirst(4)) }
    }

    func respond(to coordinate: GeoCoordinate, label: String) {
        labels[Self.key(coordinate)] = label
    }

    func label(for coordinate: GeoCoordinate) async -> String? {
        let key = Self.key(coordinate)
        events.append("GET \(key)")
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        // 讓出執行權:要是同時有第二個請求,它會在這裡插進來、把 maxInFlight 推到 2
        await Task.yield()
        inFlight -= 1
        return labels[key]
    }

    private static func key(_ coordinate: GeoCoordinate) -> String {
        "\(String(coordinate.latitude)),\(String(coordinate.longitude))"
    }

    func sleep(seconds: TimeInterval) async {
        events.append("sleep \(seconds)")
    }
}

private enum Place {
    static let taipei = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
    static let taipeiSameCell = GeoCoordinate(latitude: 25.0301, longitude: 121.5601)
    static let osaka = GeoCoordinate(latitude: 34.6937, longitude: 135.5023)
    /// 海上,查不到。
    static let pacific = GeoCoordinate(latitude: 10.0, longitude: -150.0)
    static let sydney = GeoCoordinate(latitude: -33.8688, longitude: 151.2093)
    static let newYork = GeoCoordinate(latitude: 40.7128, longitude: -74.006)
    static let london = GeoCoordinate(latitude: 51.5072, longitude: -0.1276)
    static let seoul = GeoCoordinate(latitude: 37.5665, longitude: 126.978)
}
