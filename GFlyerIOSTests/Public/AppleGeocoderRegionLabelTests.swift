import XCTest
@testable import GFlyerIOS

/// 公開版的「國家 · 城市」反查用 Apple 的地點服務,不連 Nominatim(GFlyer-Suite docs/features/region-labels.md 3.5a,
/// DRIFT D33;docs/APP_STORE_PLAN.md 第 17 項),而且先取得同意(3.10)。
///
/// 「fixture」那一段照抄 GFlyer-Suite `contracts/fixtures/region/platform-geocoder-labels.json`(2026-10-22 抄寫)。
/// iOS 的 CI 拿不到那個 repo,fixture 改了這裡要跟著改;Android 公開版的 `PlatformGeocoderTextTest` 直接讀同一份 JSON。
/// fixture 的欄位名稱照 Android:`countryName`、`locality`、`subAdminArea`、`adminArea` 對應 `CLPlacemark` 的
/// `country`、`locality`、`subAdministrativeArea`、`administrativeArea`;沒有寫出的欄位是 nil。
final class AppleGeocoderRegionLabelTests: XCTestCase {
    private struct Address {
        var countryName: String?
        var locality: String?
        var subAdminArea: String?
        var adminArea: String?
    }

    // MARK: - fixture:labels

    func testLabelsMatchFixture() {
        let cases: [(name: String, address: Address, expected: String?)] = [
            (
                "country-and-locality",
                Address(countryName: "美國", locality: "舊金山", subAdminArea: "舊金山縣", adminArea: "加利福尼亞州"),
                "美國 · 舊金山"
            ),
            (
                "sub-admin-area-when-there-is-no-locality",
                Address(countryName: "臺灣", subAdminArea: "宜蘭縣", adminArea: "臺灣省"),
                "臺灣 · 宜蘭縣"
            ),
            ("admin-area-is-the-last-resort", Address(countryName: "臺灣", adminArea: "臺北市"), "臺灣 · 臺北市"),
            ("city-equal-to-country-is-dropped", Address(countryName: "新加坡", locality: "新加坡"), "新加坡"),
            (
                "no-further-fallback-after-dropping-the-city",
                Address(countryName: "新加坡", locality: "新加坡", adminArea: "中區"),
                "新加坡"
            ),
            ("comparison-with-the-country-is-exact", Address(countryName: "新加坡", locality: "新加坡市"), "新加坡 · 新加坡市"),
            ("city-without-a-country", Address(locality: "某自由市"), "某自由市"),
            ("blank-country-counts-as-missing", Address(countryName: "   ", locality: "臺北市"), "臺北市"),
            (
                "blank-city-fields-fall-through",
                Address(countryName: "日本", locality: "", subAdminArea: "\u{3000}", adminArea: "東京都"),
                "日本 · 東京都"
            ),
            ("only-country", Address(countryName: "日本"), "日本"),
            ("values-are-not-trimmed", Address(countryName: " 臺灣", locality: "臺北市 "), " 臺灣 · 臺北市 "),
            (
                "everything-blank",
                Address(countryName: " ", locality: "", subAdminArea: "\u{3000}", adminArea: ""),
                nil
            ),
            ("empty-address", Address(), nil),
        ]
        XCTAssertEqual(cases.count, 13, "fixture 的 labels 全部抄進來")
        for testCase in cases {
            let address = testCase.address
            XCTAssertEqual(
                RegionLabel.label(
                    country: address.countryName,
                    locality: address.locality,
                    subAdministrativeArea: address.subAdminArea,
                    administrativeArea: address.adminArea
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    // MARK: - 公開版

    /// 反查送去 Apple 的地點服務,語言固定繁體中文(台灣);先取得同意,說明和開關寫的是 Apple 的服務。
    @MainActor
    func testPublicEditionUsesAppleAndAsksFirst() throws {
        XCTAssertTrue(Edition.makeRegionLabelSource() is AppleGeocoderRegionLabelSource)
        XCTAssertEqual(AppleGeocoderRegionLabelSource.locale.identifier, "zh_TW")
        XCTAssertEqual(Edition.regionLookupConsentService, "Apple 的地點服務")

        let suiteName = "gflyer.region-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lookup = RegionLookup(defaults: defaults)
        XCTAssertTrue(lookup.asksFirst)
        XCTAssertFalse(lookup.lookupsAllowed, "新裝還沒問過,不查")

        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults),
            regionLookup: lookup
        )
        XCTAssertEqual(controller.regionConsentParagraphs, [
            "收藏清單可以在每個收藏旁邊顯示所在的國家與城市，例如「臺灣 · 臺北市」。要查出來，收藏位置與收藏路線第一點的座標會送往 Apple 的地點服務；之後按 ☆ 收藏新的地點時，那一點的座標也會立刻送出，用來預先填入名稱。",
            "查到的結果只存在本機，不會放進備份檔。不允許也可以照常收藏，只是不顯示國家與城市。之後可以在設定的「提示與地名」更改。",
        ])
        XCTAssertEqual(controller.regionConsentSettingDescription, "收藏的座標會送往 Apple 的地點服務查詢")
    }
}
