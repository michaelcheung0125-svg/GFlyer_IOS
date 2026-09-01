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
}
