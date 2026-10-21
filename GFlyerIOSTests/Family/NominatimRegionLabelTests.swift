import XCTest
@testable import GFlyerIOS

/// 親友版的「國家 · 城市」反查送去 Nominatim(GFlyer-Suite docs/features/region-labels.md §3.4、§3.5)。
/// 公開版不連 Nominatim(DRIFT D33),所以這幾段 2026-10-22 從 `RegionLabelTests` 搬過來,只在親友版跑。
///
/// 「fixture」那幾段照抄 GFlyer-Suite `contracts/fixtures/region/nominatim-labels.json`(2026-09-28 抄寫)。
/// iOS 的 CI 拿不到那個 repo,fixture 改了這裡要跟著改;Android 親友版的 `RegionLabelFixtureTest` 直接讀同一份 JSON。
/// address 與 body 是 fixture 裡的 JSON 原文,用 raw string 抄進來再解析;看不見的全形空白 U+3000 與不換行空白
/// U+00A0 寫成 JSON 的 `\u` 跳脫(tab、換行本來就是跳脫),解析後和 fixture 逐字相同。
final class NominatimRegionLabelTests: XCTestCase {

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
        // fixture 不釘 User-Agent 的值,只要求一定要有;規格 §3.4 寫出 iOS 的寫法(附上聯絡電郵)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "GFlyer/0.6.9 (iOS)")
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(RegionLabel.userAgent(), "GFlyer/\(version) (iOS; +gflyer@jetpiggy.com)")
    }

    // MARK: - 反查服務

    /// `NominatimRegionLabelSource` 送出 fixture 的請求,回應照 §3.5 組成標籤;連線失敗是 nil。
    func testSourceSendsTheRequestAndReadsTheResponse() async {
        let transport = RecordingTransport(response: RegionLookupResponse(
            statusCode: 200,
            body: Data(#"{"address":{"city":"臺北市","country":"臺灣"}}"#.utf8)
        ))
        let source = NominatimRegionLabelSource(transport: transport, userAgent: "GFlyer/test (iOS)")
        let label = await source.label(for: GeoCoordinate(latitude: 25.0339, longitude: 121.5645))
        XCTAssertEqual(label, "臺灣 · 臺北市")
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=zh-TW&lat=25.0339&lon=121.5645",
        ])
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "User-Agent"), "GFlyer/test (iOS)")

        let offline = NominatimRegionLabelSource(transport: RecordingTransport(response: nil), userAgent: "GFlyer/test (iOS)")
        let failed = await offline.label(for: GeoCoordinate(latitude: 25.0339, longitude: 121.5645))
        XCTAssertNil(failed)
    }

    /// 親友版照舊用 Nominatim,也不先問(DRIFT D33)。
    @MainActor
    func testFamilyEditionUsesNominatimAndDoesNotAsk() throws {
        XCTAssertTrue(Edition.makeRegionLabelSource() is NominatimRegionLabelSource)
        XCTAssertNil(Edition.regionLookupConsentService)
        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lookup = RegionLookup(defaults: defaults)
        XCTAssertFalse(lookup.asksFirst)
        XCTAssertTrue(lookup.lookupsAllowed, "親友版不用問就可以查")
    }
}

private actor RecordingTransport: RegionLookupTransport {
    private(set) var requests: [URLRequest] = []
    private let response: RegionLookupResponse?

    init(response: RegionLookupResponse?) {
        self.response = response
    }

    func response(for request: URLRequest) async -> RegionLookupResponse? {
        requests.append(request)
        return response
    }
}
