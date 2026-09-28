import XCTest
@testable import GFlyerIOS

/// 收藏清單的「國家 · 城市」標籤(GFlyer-Suite docs/features/region-labels.md)。
///
/// 「fixture」那幾段照抄 GFlyer-Suite `contracts/fixtures/region/nominatim-labels.json`(2026-09-28 抄寫)。
/// iOS 的 CI 拿不到那個 repo,fixture 改了這裡要跟著改;Android 的 `RegionLabelFixtureTest` 直接讀同一份 JSON。
/// address 與 body 是 fixture 裡的 JSON 原文,用 raw string 抄進來再解析;看不見的全形空白 U+3000 與不換行空白
/// U+00A0 寫成 JSON 的 `\u` 跳脫(tab、換行本來就是跳脫),解析後和 fixture 逐字相同。
///
/// 佇列、1.1 秒間隔、失敗不重試是有狀態的排程行為,不在 fixture 裡,用假的 transport 與時鐘測。
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

    // MARK: - fixture:labels

    func testLabelsMatchFixture() throws {
        let cases: [(name: String, address: String, expected: String?)] = [
            (
                "country-and-city",
                #"{"city":"臺北市","ISO3166-2-lvl4":"TW-TPE","country":"臺灣","country_code":"tw"}"#,
                "臺灣 · 臺北市"
            ),
            (
                "city-wins-over-every-other-field",
                #"{"state":"神奈川縣","county":"某郡","village":"某村","municipality":"某町","town":"某鎮","city":"橫濱市","state_district":"某區","country":"日本"}"#,
                "日本 · 橫濱市"
            ),
            (
                "town-when-there-is-no-city",
                #"{"town":"礁溪鄉","county":"宜蘭縣","country":"臺灣","country_code":"tw"}"#,
                "臺灣 · 礁溪鄉"
            ),
            (
                "municipality-when-there-is-no-town",
                #"{"municipality":"Kiruna kommun","county":"Norrbottens län","country":"瑞典"}"#,
                "瑞典 · Kiruna kommun"
            ),
            (
                "village-when-there-is-no-municipality",
                #"{"village":"Hallstatt","county":"Bezirk Gmunden","state":"上奧地利州","country":"奧地利"}"#,
                "奧地利 · Hallstatt"
            ),
            (
                "county-when-there-is-no-village",
                #"{"county":"新竹縣","country":"臺灣"}"#,
                "臺灣 · 新竹縣"
            ),
            (
                "state-district-when-there-is-no-county",
                #"{"state_district":"Kachchh","state":"Gujarat","country":"印度"}"#,
                "印度 · Kachchh"
            ),
            (
                "state-is-the-last-resort",
                #"{"state":"加利福尼亞州","country":"美國","country_code":"us"}"#,
                "美國 · 加利福尼亞州"
            ),
            (
                "province-is-not-a-city-field",
                #"{"province":"東京都","ISO3166-2-lvl4":"JP-13","country":"日本","country_code":"jp"}"#,
                "日本"
            ),
            (
                "other-fields-are-ignored",
                #"{"suburb":"信義區","city_district":"信義區","neighbourhood":"某里","hamlet":"某聚落","region":"北臺灣","island":"臺灣島","postcode":"110","road":"信義路五段","country":"臺灣"}"#,
                "臺灣"
            ),
            (
                "city-equal-to-country-is-dropped",
                #"{"city":"新加坡","country":"新加坡","country_code":"sg"}"#,
                "新加坡"
            ),
            (
                "no-further-fallback-after-dropping-the-city",
                #"{"city":"摩納哥","state":"Monaco-Ville","country":"摩納哥"}"#,
                "摩納哥"
            ),
            (
                "comparison-with-the-country-is-exact",
                #"{"city":"monaco","country":"Monaco"}"#,
                "Monaco · monaco"
            ),
            (
                "city-without-a-country",
                #"{"city":"某自由市"}"#,
                "某自由市"
            ),
            (
                "blank-country-counts-as-missing",
                #"{"country":"   ","city":"臺北市"}"#,
                "臺北市"
            ),
            (
                "blank-city-fields-fall-through",
                #"{"city":"","town":"   ","municipality":"\u3000","village":"\t\n","county":"\u00a0","state_district":"Kachchh","state":"Gujarat","country":"印度"}"#,
                "印度 · Kachchh"
            ),
            (
                "only-country",
                #"{"country":"南極洲"}"#,
                "南極洲"
            ),
            (
                "values-are-not-trimmed",
                #"{"country":" 日本","city":"大阪市 "}"#,
                " 日本 · 大阪市 "
            ),
            (
                "values-are-used-verbatim",
                #"{"city":"達卡;达卡","country":"孟加拉"}"#,
                "孟加拉 · 達卡;达卡"
            ),
            (
                "no-length-limit",
                #"{"village":"Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch","country":"英國"}"#,
                "英國 · Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch"
            ),
            (
                "everything-blank",
                #"{"country":"  ","city":"","state":"\u3000"}"#,
                nil
            ),
            (
                "empty-address",
                #"{}"#,
                nil
            ),
            (
                "only-ignored-fields",
                #"{"country_code":"xx","province":"某省","suburb":"某區","postcode":"000"}"#,
                nil
            ),
        ]
        XCTAssertEqual(cases.count, 23, "fixture 的 labels 全部抄進來")
        for testCase in cases {
            let object = try JSONSerialization.jsonObject(with: Data(testCase.address.utf8))
            let address = try XCTUnwrap(object as? [String: Any], testCase.name)
            XCTAssertEqual(RegionLabel.label(address: address), testCase.expected, testCase.name)
        }

        // 跳脫寫法解析回來是 fixture 裡的那幾個看不見的字元
        let blank = try XCTUnwrap(cases.first { $0.name == "blank-city-fields-fall-through" })
        let blankObject = try JSONSerialization.jsonObject(with: Data(blank.address.utf8))
        let blankAddress = try XCTUnwrap(blankObject as? [String: Any])
        XCTAssertEqual(blankAddress["municipality"] as? String, "\u{3000}")
        XCTAssertEqual(blankAddress["village"] as? String, "\t\n")
        XCTAssertEqual(blankAddress["county"] as? String, "\u{00A0}")
    }

    // MARK: - fixture:responses

    func testResponsesMatchFixture() {
        let cases: [(name: String, status: Int?, body: String?, expected: String?)] = [
            (
                "full-response-body", 200,
                #"{"place_id":1,"licence":"Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright","osm_type":"relation","osm_id":1,"lat":"25.0375","lon":"121.5637","category":"boundary","type":"administrative","place_rank":8,"importance":0.7,"addresstype":"city","name":"臺北市","display_name":"臺北市, 臺灣","address":{"city":"臺北市","ISO3166-2-lvl4":"TW-TPE","country":"臺灣","country_code":"tw"},"boundingbox":["24.96","25.21","121.45","121.67"]}"#,
                "臺灣 · 臺北市"
            ),
            (
                "any-2xx-is-success", 299,
                #"{"address":{"city":"臺中市","country":"臺灣"}}"#,
                "臺灣 · 臺中市"
            ),
            (
                "unable-to-geocode", 200,
                #"{"error":"Unable to geocode"}"#,
                nil
            ),
            (
                "address-is-null", 200,
                #"{"address":null}"#,
                nil
            ),
            (
                "address-is-not-an-object", 200,
                #"{"address":"臺北市"}"#,
                nil
            ),
            (
                "top-level-array", 200,
                #"[{"address":{"city":"臺北市","country":"臺灣"}}]"#,
                nil
            ),
            (
                "not-json", 200,
                #"<html><body>Bad Gateway</body></html>"#,
                nil
            ),
            (
                "empty-body", 200,
                #""#,
                nil
            ),
            (
                "rate-limited-body-is-not-read", 429,
                #"{"address":{"city":"臺北市","country":"臺灣"}}"#,
                nil
            ),
            (
                "forbidden", 403,
                #"Access blocked"#,
                nil
            ),
            (
                "server-error", 500,
                #"{"address":{"city":"臺北市","country":"臺灣"}}"#,
                nil
            ),
            (
                "connection-failed", nil,
                nil,
                nil
            ),
        ]
        XCTAssertEqual(cases.count, 12, "fixture 的 responses 全部抄進來")
        for testCase in cases {
            let body = testCase.body.map { Data($0.utf8) }
            XCTAssertEqual(RegionLabel.label(status: testCase.status, body: body), testCase.expected, testCase.name)
        }
    }

    // MARK: - fixture:request

    func testRequestMatchesFixture() throws {
        let coordinate = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
        let request = try XCTUnwrap(RegionLabel.request(for: coordinate, userAgent: "GFlyer/0.6.9 (iOS)"))
        XCTAssertEqual(request.httpMethod, "GET")
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "nominatim.openstreetmap.org")
        XCTAssertEqual(components.path, "/reverse")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.map(\.name).sorted(), ["accept-language", "format", "lat", "lon", "zoom"], "查詢參數就這五個")
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value }
        XCTAssertEqual(query, [
            "format": "jsonv2",
            "zoom": "10",
            "accept-language": "zh-TW",
            "lat": "25.0339",
            "lon": "121.5645",
        ])
        // 規格 §3.4 寫出的完整網址,也就是 Android 送出的那一個
        XCTAssertEqual(
            url.absoluteString,
            "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=zh-TW&lat=25.0339&lon=121.5645"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        // connectTimeoutMillis 與 readTimeoutMillis 都是 8000;URLRequest 只有一個逾時,兩段都受它限制
        XCTAssertEqual(request.timeoutInterval, 8)
        // fixture 不釘 User-Agent 的值,只要求一定要有;iOS 沿用 AppUpdateChecker 的寫法
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "GFlyer/0.6.9 (iOS)")
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(RegionLabel.userAgent(), "GFlyer/\(version) (iOS)")
    }

    // MARK: - 佇列與快取

    func testRequestsGoOneAtATimeInOrderWithAGapAfterEach() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let nominatim = FakeNominatim()
        await nominatim.respond(to: Place.taipei, status: 200, body: Self.body(city: "臺北市", country: "臺灣"))
        await nominatim.respond(to: Place.osaka, status: 200, body: Self.body(city: "大阪市", country: "日本"))
        let lookup = makeLookup(defaults, nominatim)

        lookup.request([Place.taipei, Place.pacific, Place.osaka])
        lookup.request([Place.sydney])
        await lookup.waitUntilIdle()

        // 第一筆不等;每次真的送出請求之後都等 1.1 秒,連線失敗(太平洋、雪梨沒有回應)也一樣
        var events = await nominatim.events
        XCTAssertEqual(events, [
            "GET 25.0339,121.5645", "sleep 1.1",
            "GET 10.0,-150.0", "sleep 1.1",
            "GET 34.6937,135.5023", "sleep 1.1",
            "GET -33.8688,151.2093", "sleep 1.1",
        ])
        let maxInFlight = await nominatim.maxInFlight
        XCTAssertEqual(maxInFlight, 1, "同一時間最多一個請求")
        XCTAssertEqual(lookup.labels, ["25.03,121.56": "臺灣 · 臺北市", "34.69,135.50": "日本 · 大阪市"])

        // 佇列清空之後再排:上一次請求之後的間隔已經等完,新的一筆直接送出,之後照樣等
        lookup.request([Place.newYork])
        await lookup.waitUntilIdle()
        events = await nominatim.events
        XCTAssertEqual(Array(events.dropFirst(8)), ["GET 40.7128,-74.006", "sleep 1.1"])
    }

    func testCachedQueuedAndFailedKeysAreNotSentAgain() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(["34.69,135.50": "日本 · 大阪市"]), forKey: RegionLookup.storageKey)
        let nominatim = FakeNominatim()
        await nominatim.respond(to: Place.taipei, status: 200, body: Self.body(city: "臺北市", country: "臺灣"))
        await nominatim.respond(to: Place.pacific, status: 200, body: #"{"error":"Unable to geocode"}"#)
        let lookup = makeLookup(defaults, nominatim)
        XCTAssertEqual(lookup.labels, ["34.69,135.50": "日本 · 大阪市"], "啟動時讀回快取")
        var published: [[String: String]] = []
        lookup.onLabelsChange = { published.append($0) }

        let list = [Place.taipei, Place.taipeiSameCell, Place.osaka, Place.pacific]
        lookup.request(list)
        lookup.request(list)
        await lookup.waitUntilIdle()

        // 同一格只送第一個排進來的座標;已經有快取的不送、也不等;排過隊的不重複排
        var events = await nominatim.events
        XCTAssertEqual(events, ["GET 25.0339,121.5645", "sleep 1.1", "GET 10.0,-150.0", "sleep 1.1"])
        XCTAssertEqual(published, [["34.69,135.50": "日本 · 大阪市", "25.03,121.56": "臺灣 · 臺北市"]])
        XCTAssertEqual(RegionLabel.label(in: lookup.labels, for: Place.taipeiSameCell), "臺灣 · 臺北市", "同一格共用")
        XCTAssertNil(RegionLabel.label(in: lookup.labels, for: Place.pacific), "查不到的沒有標籤")

        // 呼叫端很頻繁地送同一份清單:查到的與這次失敗過的都不再送
        lookup.request(list)
        await lookup.waitUntilIdle()
        events = await nominatim.events
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(published.count, 1)
    }

    func testFailuresAreNotCachedAndAreRetriedOnTheNextLaunch() async throws {
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let taipeiBody = Self.body(city: "臺北市", country: "臺灣")
        let first = FakeNominatim()
        await first.respond(to: Place.taipei, status: 200, body: taipeiBody)
        // 被限流時 body 不讀;太平洋沒有回應 = 連線失敗
        await first.respond(to: Place.osaka, status: 429, body: taipeiBody)
        let lookup = makeLookup(defaults, first)
        lookup.request([Place.taipei, Place.osaka, Place.pacific])
        await lookup.waitUntilIdle()
        XCTAssertEqual(try storedLabels(defaults), ["25.03,121.56": "臺灣 · 臺北市"], "失敗不寫進持久化快取")

        // 下次啟動:讀回快取,查到的不再送,失敗的各再試一次
        let second = FakeNominatim()
        await second.respond(to: Place.osaka, status: 200, body: Self.body(city: "大阪市", country: "日本"))
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
        XCTAssertEqual(makeLookup(defaults, FakeNominatim()).labels, [:])
        defaults.set(Data(#"{"25.03,121.56":1}"#.utf8), forKey: RegionLookup.storageKey)
        XCTAssertEqual(makeLookup(defaults, FakeNominatim()).labels, [:])
        defaults.set("臺灣 · 臺北市", forKey: RegionLookup.storageKey)
        XCTAssertEqual(makeLookup(defaults, FakeNominatim()).labels, [:])
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
        let nominatim = FakeNominatim()
        await nominatim.respond(to: Place.taipei, status: 200, body: Self.body(city: "臺北市", country: "臺灣"))
        await nominatim.respond(to: Place.newYork, status: 200, body: Self.body(city: "紐約", country: "美國"))
        let lookup = makeLookup(defaults, nominatim)

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
        var requested = await nominatim.requested
        XCTAssertEqual(requested, ["25.0339,121.5645", "34.6937,135.5023", "40.7128,-74.006", "-33.8688,151.2093"])
        XCTAssertEqual(controller.regionLabels, ["25.03,121.56": "臺灣 · 臺北市", "40.71,-74.01": "美國 · 紐約"])
        XCTAssertEqual(
            LibraryRowText.place(Place.taipei, labels: controller.regionLabels),
            "25.033900, 121.564500  ·  臺灣 · 臺北市"
        )
        XCTAssertEqual(
            LibraryRowText.route(controller.savedRoutes[0], labels: controller.regionLabels),
            "2 個點 · 循環 · 美國 · 紐約"
        )
        XCTAssertEqual(LibraryRowText.route(controller.savedRoutes[1], labels: controller.regionLabels), "2 個點 · 單程")
        // 歷史只在剛好和某個收藏落在同一格時顯示標籤
        XCTAssertEqual(
            LibraryRowText.place(Place.taipeiSameCell, labels: controller.regionLabels),
            "25.030100, 121.560100  ·  臺灣 · 臺北市"
        )
        XCTAssertEqual(LibraryRowText.place(Place.pacific, labels: controller.regionLabels), "10.000000, -150.000000")

        // 收藏變動時把新的座標排進來
        controller.select(Place.seoul)
        XCTAssertEqual(controller.addFavorite(name: "首爾"), SimulationController.favoriteAddedMessage)
        await lookup.waitUntilIdle()
        requested = await nominatim.requested
        XCTAssertEqual(requested.count, 5)
        XCTAssertEqual(requested.last, "37.5665,126.978")

        // 刪掉收藏不清快取,再加回同一點也不再送
        let taipeiID = try XCTUnwrap(controller.favorites.first { $0.name == "台北" }?.id)
        controller.removeFavorite(taipeiID)
        controller.select(Place.taipei)
        controller.addFavorite()
        await lookup.waitUntilIdle()
        requested = await nominatim.requested
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
        XCTAssertEqual(LibraryRowText.place(Place.taipei, labels: labels), "25.033900, 121.564500  ·  臺灣 · 臺北市")
        XCTAssertEqual(LibraryRowText.place(Place.osaka, labels: labels), "34.693700, 135.502300", "沒有標籤時連同分隔一起省略")

        let twelve = (0..<12).map { GeoCoordinate(latitude: 25.0339 + Double($0) * 0.001, longitude: 121.5645) }
        XCTAssertEqual(
            LibraryRowText.route(SavedRoute(name: "臺北", points: twelve, loop: true), labels: labels),
            "12 個點 · 循環 · 臺灣 · 臺北市"
        )
        XCTAssertEqual(LibraryRowText.route(SavedRoute(name: "臺北", points: twelve, loop: false), labels: [:]), "12 個點 · 單程")

        // 日期時間跟系統語言與時區(中等日期 + 短時間);前綴與後面的半形空白必須一字不差
        let date = Date(timeIntervalSince1970: 1_790_401_200)
        let dateTime = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.favoriteSavedPrefix, at: date), "收藏於 " + dateTime)
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.historySavedPrefix, at: date), "定位於 " + dateTime)
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.routeSavedPrefix, at: date), "儲存於 " + dateTime)
    }

    // MARK: - 輔助

    private func makeLookup(_ defaults: UserDefaults, _ nominatim: FakeNominatim) -> RegionLookup {
        RegionLookup(defaults: defaults, transport: nominatim, clock: nominatim, userAgent: "GFlyer/test (iOS)")
    }

    private func storedLabels(_ defaults: UserDefaults) throws -> [String: String] {
        let data = try XCTUnwrap(defaults.data(forKey: RegionLookup.storageKey))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static func body(city: String, country: String) -> String {
        #"{"address":{"city":"\#(city)","country":"\#(country)"}}"#
    }
}

/// 不連網的反查:每個請求都當作連線失敗,等待也不真的等。其他測試建 `SimulationController`、而且會有收藏或
/// 路線時用 `RegionLookup.offline(defaults:)`,單元測試才不會真的去查 Nominatim。
struct OfflineRegionLookup: RegionLookupTransport, RegionLookupClock {
    func response(for request: URLRequest) async -> RegionLookupResponse? { nil }
    func sleep(seconds: TimeInterval) async {}
}

extension RegionLookup {
    static func offline(defaults: UserDefaults) -> RegionLookup {
        RegionLookup(
            defaults: defaults,
            transport: OfflineRegionLookup(),
            clock: OfflineRegionLookup(),
            userAgent: "GFlyer/test (iOS)"
        )
    }
}

/// 假的 Nominatim,同時當 transport 與時鐘:依序記下每一次請求(「GET 緯度,經度」,寫法和送出的
/// lat / lon 相同)與等待(「sleep 秒數」),依座標回應;沒有設定回應的座標當作連線失敗。等待只記錄、不真的等。
private actor FakeNominatim: RegionLookupTransport, RegionLookupClock {
    private(set) var events: [String] = []
    private(set) var maxInFlight = 0
    private var inFlight = 0
    private var responses: [String: RegionLookupResponse] = [:]

    /// 送出請求的座標,依時間順序。
    var requested: [String] {
        events.filter { $0.hasPrefix("GET ") }.map { String($0.dropFirst(4)) }
    }

    func respond(to coordinate: GeoCoordinate, status: Int, body: String) {
        let key = "\(String(coordinate.latitude)),\(String(coordinate.longitude))"
        responses[key] = RegionLookupResponse(statusCode: status, body: Data(body.utf8))
    }

    func response(for request: URLRequest) async -> RegionLookupResponse? {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let latitude = items.first { $0.name == "lat" }?.value ?? "?"
        let longitude = items.first { $0.name == "lon" }?.value ?? "?"
        let key = "\(latitude),\(longitude)"
        events.append("GET \(key)")
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        // 讓出執行權:要是同時有第二個請求,它會在這裡插進來、把 maxInFlight 推到 2
        await Task.yield()
        inFlight -= 1
        return responses[key]
    }

    func sleep(seconds: TimeInterval) async {
        events.append("sleep \(seconds)")
    }
}

private enum Place {
    static let taipei = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
    static let taipeiSameCell = GeoCoordinate(latitude: 25.0301, longitude: 121.5601)
    static let osaka = GeoCoordinate(latitude: 34.6937, longitude: 135.5023)
    /// 海上,Nominatim 查不到。
    static let pacific = GeoCoordinate(latitude: 10.0, longitude: -150.0)
    static let sydney = GeoCoordinate(latitude: -33.8688, longitude: 151.2093)
    static let newYork = GeoCoordinate(latitude: 40.7128, longitude: -74.006)
    static let london = GeoCoordinate(latitude: 51.5072, longitude: -0.1276)
    static let seoul = GeoCoordinate(latitude: 37.5665, longitude: 126.978)
}
