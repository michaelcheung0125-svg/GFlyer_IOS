import XCTest
@testable import GFlyerIOS

final class CoordinateLibraryTests: XCTestCase {
    private let fixture = """
    {
      "schemaVersion": 1,
      "revision": 12,
      "updatedAt": "2026-08-01",
      "source": "皮克敏純點明信片地圖 pikmin.talllkai.com",
      "categories": [
        {
          "id": "purespot",
          "name": "純點",
          "icon": "⚪",
          "subcategories": [
            {"id": "park", "name": "公園", "defaultRemindDays": 7}
          ]
        },
        {"id": "postcard", "name": "明信片", "icon": "📮"},
        {"id": "", "name": "無效分類"}
      ],
      "coordinates": [
        {
          "id": "p1", "categoryId": "purespot", "subcategoryId": "park",
          "name": "維多利亞公園", "lat": 22.2823, "lng": 114.1884,
          "note": "東角入口", "period": "全年", "remindDays": 7,
          "thumbnail": "https://example.com/a.jpg", "icon": "🌳",
          "enabled": true, "updatedAt": "2026-07-01"
        },
        {
          "id": "p2", "categoryId": "postcard",
          "name": "尖沙咀鐘樓", "lat": 22.2934, "lng": 114.1694,
          "thumbnail": "http://insecure.example.com/b.jpg",
          "enabled": false
        },
        {"id": "bad1", "categoryId": "unknown", "name": "孤兒", "lat": 1, "lng": 1},
        {"id": "bad2", "categoryId": "purespot", "name": "缺座標"}
      ]
    }
    """

    func testParseFixtureFiltersInvalidEntries() throws {
        let library = try CoordinateLibrary.parse(Data(fixture.utf8))
        XCTAssertEqual(library.revision, 12)
        XCTAssertEqual(library.categories.count, 2)
        XCTAssertEqual(library.categories[0].subcategories.first?.defaultRemindDays, 7)
        XCTAssertEqual(library.coordinates.count, 2)

        let first = try XCTUnwrap(library.coordinates.first)
        XCTAssertEqual(first.name, "維多利亞公園")
        XCTAssertEqual(first.remindDays, 7)
        XCTAssertNotNil(first.thumbnailURL)

        // 非 https 縮圖會被拒絕；停用的座標不出現在 enabledCoordinates
        let second = try XCTUnwrap(library.coordinates.last)
        XCTAssertNil(second.thumbnailURL)
        XCTAssertFalse(second.enabled)
        XCTAssertEqual(library.enabledCoordinates.count, 1)
    }

    func testParseRejectsBadVersionAndMissingRevision() {
        XCTAssertThrowsError(try CoordinateLibrary.parse(Data("{\"schemaVersion\":9}".utf8)))
        XCTAssertThrowsError(try CoordinateLibrary.parse(Data("{\"schemaVersion\":1}".utf8)))
        XCTAssertThrowsError(try CoordinateLibrary.parse(Data("not json".utf8)))
    }

    func testVisitReminderStates() {
        let markedAt = Date(timeIntervalSince1970: 1_788_134_400) // 2026-08-31T00:00Z
        let ready = VisitReminder.state(
            markedAt: markedAt,
            remindDays: 1,
            now: markedAt.addingTimeInterval(86_400)
        )
        XCTAssertEqual(ready, .ready(nextAvailableAt: markedAt.addingTimeInterval(86_400)))

        // 還剩 25 小時 30 分：無條件進位到 26 小時 = 1 天 2 小時
        let waiting = VisitReminder.state(
            markedAt: markedAt,
            remindDays: 2,
            now: markedAt.addingTimeInterval(2 * 86_400 - 25.5 * 3_600)
        )
        guard case let .waiting(_, daysLeft, hoursLeft) = waiting else {
            return XCTFail("預期 waiting 狀態")
        }
        XCTAssertEqual(daysLeft, 1)
        XCTAssertEqual(hoursLeft, 2)
    }

    func testMarkStorePersistsFavoritesAndHourPrecisionMarks() {
        let suiteName = "gflyer.marks-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CoordinateMarkStore(defaults: defaults)
        XCTAssertTrue(store.toggleFavorite("p1"))
        XCTAssertTrue(store.toggleFavorite("p2"))
        XCTAssertFalse(store.toggleFavorite("p2"))
        let now = Date(timeIntervalSince1970: 1_788_140_130) // 01:35:30Z
        let marked = store.markVisited("p1", now: now)
        XCTAssertEqual(marked.timeIntervalSince1970, 1_788_138_000) // 取整到 01:00Z

        let restored = CoordinateMarkStore(defaults: defaults)
        XCTAssertEqual(restored.favorites, ["p1"])
        XCTAssertEqual(restored.marks["p1"], marked)

        restored.clearMark("p1")
        XCTAssertNil(CoordinateMarkStore(defaults: defaults).marks["p1"])
    }

    /// GFlyer-Suite contracts/fixtures/coordinate-library/type-strictness.input.json 原樣照抄。
    /// iOS 的 CI 拿不到 Suite repo,改 fixture 時這裡與下面的期望值要跟著改。
    private let typeStrictnessInput = #"""
    {
      "schemaVersion": 1,
      "revision": 43,
      "updatedAt": 20260928,
      "source": 12345,
      "categories": [
        {
          "id": "event",
          "name": "活動",
          "icon": 5,
          "subcategories": [
            {
              "id": "sub-ok",
              "name": "型別都正確",
              "startDate": "2026-09-01",
              "endDate": "2026-09-30",
              "defaultRemindDays": 7,
              "defaultNote": "活動期間限定"
            },
            {
              "id": "sub-typed",
              "name": "選用欄位的型別都不對",
              "startDate": 20260901,
              "endDate": false,
              "defaultRemindDays": "7",
              "defaultNote": 123
            },
            { "id": "sub-bool-remind", "name": "布林不是天數", "defaultRemindDays": true },
            { "id": "sub-fraction-remind", "name": "有小數的天數無條件捨去", "defaultRemindDays": 3.9 },
            { "id": 7, "name": "數字 id,整筆略過" },
            { "id": "sub-number-name", "name": 8 },
            { "id": "sub-null-name", "name": null }
          ]
        },
        { "id": 42, "name": "數字 id 的分類,整筆略過" },
        { "id": true, "name": "布林 id 的分類,整筆略過" },
        { "id": "null-name", "name": null },
        {
          "id": "postcard",
          "name": "明信片",
          "icon": "  📮  ",
          "subcategories": "不是陣列"
        }
      ],
      "coordinates": [
        {
          "id": "c-ok",
          "categoryId": "event",
          "subcategoryId": "sub-ok",
          "name": "型別都正確",
          "lat": 25.033611,
          "lng": 121.565,
          "note": "備註",
          "period": "全年",
          "remindDays": 7,
          "thumbnail": "https://example.com/ok.jpg",
          "icon": "🌸",
          "enabled": false,
          "updatedAt": "2026-09-28"
        },
        { "id": "c-lat-true", "categoryId": "event", "name": "lat 是布林", "lat": true, "lng": 121.5 },
        { "id": "c-lng-false", "categoryId": "event", "name": "lng 是布林", "lat": 25.0, "lng": false },
        { "id": "c-lat-string", "categoryId": "event", "name": "lat 是字串", "lat": "25.0", "lng": 121.5 },
        { "id": 12345, "categoryId": "event", "name": "id 是數字", "lat": 25.0, "lng": 121.5 },
        { "id": "c-name-number", "categoryId": "event", "name": 101, "lat": 25.0, "lng": 121.5 },
        { "id": "c-name-null", "categoryId": "event", "name": null, "lat": 25.0, "lng": 121.5 },
        { "id": "c-category-number", "categoryId": 42, "name": "categoryId 是數字", "lat": 25.0, "lng": 121.5 },
        {
          "id": "c-in-numeric-category",
          "categoryId": "42",
          "name": "屬於數字 id 的分類,那個分類已被略過",
          "lat": 25.0,
          "lng": 121.5
        },
        {
          "id": "c-optional-wrong-types",
          "categoryId": "event",
          "subcategoryId": 5,
          "name": "選用欄位的型別都不對,座標本身保留",
          "lat": 25.1,
          "lng": 121.6,
          "note": 123,
          "period": false,
          "remindDays": "7",
          "thumbnail": true,
          "icon": 9,
          "enabled": "false",
          "updatedAt": 20260901
        },
        { "id": "c-remind-true", "categoryId": "event", "name": "remindDays 是布林", "lat": 25.2, "lng": 121.7, "remindDays": true },
        { "id": "c-remind-fraction", "categoryId": "event", "name": "remindDays 有小數", "lat": 25.3, "lng": 121.8, "remindDays": 7.9 },
        { "id": "c-enabled-zero", "categoryId": "postcard", "name": "enabled 是數字 0", "lat": 25.4, "lng": 121.9, "enabled": 0 },
        { "id": "c-enabled-null", "categoryId": "postcard", "name": "enabled 是 null", "lat": 25.5, "lng": 122.0, "enabled": null }
      ]
    }
    """#

    /// 布林不是數字、數字不是布林、字串不會被轉型;分類圖示、updatedAt、source 原樣保留
    /// (type-strictness.expected.json,DRIFT D12 的殘留)。
    func testTypeStrictnessMatchesTheSharedFixture() throws {
        let library = try CoordinateLibrary.parse(Data(typeStrictnessInput.utf8))

        XCTAssertEqual(library.schemaVersion, 1)
        XCTAssertEqual(library.revision, 43)
        XCTAssertEqual(library.updatedAt, "")
        XCTAssertEqual(library.source, "皮克敏純點明信片地圖 pikmin.talllkai.com")
        XCTAssertEqual(library.categories.map(\.id), ["event", "postcard"])
        XCTAssertEqual(library.categories.map(\.icon), ["", "  📮  "])

        let eventSubcategories = try XCTUnwrap(library.category(id: "event")).subcategories
        XCTAssertEqual(eventSubcategories, [
            LibrarySubcategory(
                id: "sub-ok", name: "型別都正確", startDate: "2026-09-01", endDate: "2026-09-30",
                defaultRemindDays: 7, defaultNote: "活動期間限定"
            ),
            LibrarySubcategory(
                id: "sub-typed", name: "選用欄位的型別都不對", startDate: nil, endDate: nil,
                defaultRemindDays: nil, defaultNote: nil
            ),
            LibrarySubcategory(
                id: "sub-bool-remind", name: "布林不是天數", startDate: nil, endDate: nil,
                defaultRemindDays: nil, defaultNote: nil
            ),
            LibrarySubcategory(
                id: "sub-fraction-remind", name: "有小數的天數無條件捨去", startDate: nil, endDate: nil,
                defaultRemindDays: 3, defaultNote: nil
            ),
        ])
        XCTAssertEqual(library.category(id: "postcard")?.subcategories, [])

        let coordinates = library.coordinates
        XCTAssertEqual(coordinates.map(\.id), [
            "c-ok", "c-optional-wrong-types", "c-remind-true", "c-remind-fraction", "c-enabled-zero", "c-enabled-null",
        ])
        XCTAssertEqual(coordinates.map(\.categoryID), ["event", "event", "event", "event", "postcard", "postcard"])
        XCTAssertEqual(coordinates.map(\.subcategoryID), ["sub-ok", nil, nil, nil, nil, nil])
        XCTAssertEqual(coordinates.map(\.name), [
            "型別都正確", "選用欄位的型別都不對,座標本身保留", "remindDays 是布林", "remindDays 有小數",
            "enabled 是數字 0", "enabled 是 null",
        ])
        let expectedPositions: [(Double, Double)] = [
            (25.033611, 121.565), (25.1, 121.6), (25.2, 121.7), (25.3, 121.8), (25.4, 121.9), (25.5, 122.0),
        ]
        for (coordinate, expected) in zip(coordinates, expectedPositions) {
            XCTAssertEqual(coordinate.latitude, expected.0, accuracy: 1e-9, coordinate.id)
            XCTAssertEqual(coordinate.longitude, expected.1, accuracy: 1e-9, coordinate.id)
        }
        XCTAssertEqual(coordinates.map(\.note), ["備註", "", "", "", "", ""])
        XCTAssertEqual(coordinates.map(\.period), ["全年", "", "", "", "", ""])
        XCTAssertEqual(coordinates.map(\.remindDays), [7, nil, nil, 7, nil, nil])
        XCTAssertEqual(coordinates.map(\.thumbnailURL), [URL(string: "https://example.com/ok.jpg"), nil, nil, nil, nil, nil])
        XCTAssertEqual(coordinates.map(\.icon), ["🌸", nil, nil, nil, nil, nil])
        XCTAssertEqual(coordinates.map(\.enabled), [false, true, true, true, true, true])
        XCTAssertEqual(coordinates.map(\.updatedAt), ["2026-09-28", nil, nil, nil, nil, nil])
        XCTAssertEqual(library.enabledCoordinates.count, 5)
    }

    /// type-strictness.expected.json 的 topLevelCases:各自是一份獨立的整份輸入。
    func testTopLevelTypeStrictnessCasesMatchTheSharedFixture() throws {
        let rejects: [(name: String, json: String, message: String)] = [
            ("schema-version-true", #"{"schemaVersion": true, "revision": 1}"#, "座標庫資料版本不支援（0）。"),
            ("schema-version-string", #"{"schemaVersion": "1", "revision": 1}"#, "座標庫資料版本不支援（0）。"),
            ("revision-true", #"{"schemaVersion": 1, "revision": true}"#, "座標庫資料缺少有效的 revision。"),
            ("revision-string", #"{"schemaVersion": 1, "revision": "42"}"#, "座標庫資料缺少有效的 revision。"),
            ("revision-null", #"{"schemaVersion": 1, "revision": null}"#, "座標庫資料缺少有效的 revision。"),
        ]
        for testCase in rejects {
            XCTAssertThrowsError(try CoordinateLibrary.parse(Data(testCase.json.utf8)), testCase.name) { error in
                XCTAssertEqual((error as? LibraryFormatError)?.message, testCase.message, testCase.name)
            }
        }

        let fractional = try CoordinateLibrary.parse(Data(#"{"schemaVersion": 1.0, "revision": 42.9}"#.utf8))
        XCTAssertEqual(fractional.schemaVersion, 1)
        XCTAssertEqual(fractional.revision, 42)
        XCTAssertEqual(fractional.categories.count, 0)
        XCTAssertEqual(fractional.coordinates.count, 0)

        let wrongCollections = try CoordinateLibrary.parse(Data(#"""
        {"schemaVersion": 1, "revision": 1, "categories": {"id": "x", "name": "物件不是陣列"}, "coordinates": "不是陣列"}
        """#.utf8))
        XCTAssertEqual(wrongCollections.categories.count, 0)
        XCTAssertEqual(wrongCollections.coordinates.count, 0)

        let defaultSource = "皮克敏純點明信片地圖 pikmin.talllkai.com"
        let texts: [(name: String, json: String, source: String, updatedAt: String)] = [
            ("null-source-and-blank-updated-at",
             #"{"schemaVersion": 1, "revision": 1, "source": null, "updatedAt": "   "}"#, defaultSource, "   "),
            ("blank-source", #"{"schemaVersion": 1, "revision": 1, "source": "  "}"#, "  ", ""),
            ("non-string-source-and-updated-at",
             #"{"schemaVersion": 1, "revision": 1, "source": 12345, "updatedAt": 20260928}"#, defaultSource, ""),
        ]
        for testCase in texts {
            let library = try CoordinateLibrary.parse(Data(testCase.json.utf8))
            XCTAssertEqual(library.source, testCase.source, testCase.name)
            XCTAssertEqual(library.updatedAt, testCase.updatedAt, testCase.name)
        }
    }

    /// 陣列裡混進非物件元素時只略過那一個,和 Android 相同(DRIFT D17)。
    func testParseSkipsNonObjectElementsInsteadOfDroppingTheList() throws {
        let json = """
        {
          "schemaVersion": 1, "revision": 3,
          "categories": [
            "不是物件",
            {"id": "purespot", "name": "純點", "subcategories": [42, {"id": "park", "name": "公園"}]}
          ],
          "coordinates": [
            null,
            {"id": "p1", "categoryId": "purespot", "name": "公園", "lat": 1, "lng": 2}
          ]
        }
        """
        let library = try CoordinateLibrary.parse(Data(json.utf8))

        XCTAssertEqual(library.categories.map(\.id), ["purespot"])
        XCTAssertEqual(library.categories.first?.subcategories.map(\.id), ["park"])
        XCTAssertEqual(library.coordinates.map(\.id), ["p1"])
    }
}
