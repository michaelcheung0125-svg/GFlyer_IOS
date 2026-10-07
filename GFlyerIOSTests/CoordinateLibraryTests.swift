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

    /// 只有明信片有「回報資料已過時」,文字和 Android 一字不差(coordinate-stale-report.md)。
    func testOnlyPostcardsCanBeReportedAsOutdated() throws {
        let library = try CoordinateLibrary.parse(Data(fixture.utf8))
        XCTAssertEqual(library.coordinates.map(\.canReportOutdated), [false, true])
        XCTAssertEqual(OutdatedReport.reasons, ["座標位置錯誤", "地點已消失", "資訊過時"])
        XCTAssertEqual(OutdatedReport.successMessage, "已送出回報，謝謝你！")
        XCTAssertEqual(OutdatedReport.failureMessage, "回報送出失敗，請稍後再試")
    }

    /// 任何失敗都顯示同一句,不附錯誤描述(這裡是留言板未設定)。
    @MainActor
    func testReportFailureShowsTheFixedMessage() async throws {
        let suiteName = "gflyer.report-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gflyer-report-tests-\(UUID().uuidString)", isDirectory: true)
        let library = CoordinateLibraryController(
            repository: CoordinateLibraryRepository(urlString: "", cacheDirectory: cacheDirectory),
            markStore: CoordinateMarkStore(defaults: defaults),
            apiClient: MessageBoardAPIClient(baseURLString: "")
        )
        let coordinate = try XCTUnwrap(CoordinateLibrary.parse(Data(fixture.utf8)).coordinates.last)

        library.reportOutdated(coordinate, reason: OutdatedReport.reasons[0], message: "")
        for _ in 0..<200 where library.errorMessage == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.errorMessage, "回報送出失敗，請稍後再試")
        XCTAssertNil(library.infoMessage)
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

    // MARK: - 前往紀錄與「隱藏已前往」(GFlyer-Suite docs/features/library-teleport-history.md 第 6 節)

    private let marksKey = "gflyer.coordinate-marks.v1"
    private let teleportsKey = "gflyer.coordinate-teleports.v1"
    private let hideTeleportedKey = "gflyer.coordinate-hide-teleported.v1"
    /// 0.6.8 寫出的 Snapshot:只有最愛與造訪標記(秒)。
    private let snapshotFrom068 = #"{"favorites":["p1"],"marks":{"p1":1788138000}}"#

    /// 從 0.6.8 升上來:兩個新鍵都不存在 → 沒有前往紀錄、開關關閉,最愛與造訪標記照舊。
    func testMarksSavedBy068ReadUnchangedWithoutTeleportHistory() throws {
        let suiteName = "gflyer.teleport-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(snapshotFrom068.utf8), forKey: marksKey)

        let store = CoordinateMarkStore(defaults: defaults)
        XCTAssertEqual(store.favorites, ["p1"])
        XCTAssertEqual(store.marks, ["p1": Date(timeIntervalSince1970: 1_788_138_000)])
        XCTAssertEqual(store.teleports, [:])
        XCTAssertFalse(store.hideTeleported)
    }

    /// 前往紀錄壞掉只影響它自己;下一次記錄蓋掉壞資料,最愛與造訪標記仍在。
    func testCorruptTeleportHistoryLeavesFavoritesAndMarksIntact() throws {
        let suiteName = "gflyer.teleport-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(snapshotFrom068.utf8), forKey: marksKey)
        defaults.set(Data("{ not json".utf8), forKey: teleportsKey)

        let store = CoordinateMarkStore(defaults: defaults)
        XCTAssertEqual(store.teleports, [:])
        XCTAssertEqual(store.favorites, ["p1"])
        XCTAssertEqual(store.marks, ["p1": Date(timeIntervalSince1970: 1_788_138_000)])

        store.recordTeleport("p2", now: Date(timeIntervalSince1970: 1_789_799_520.123))
        let restored = CoordinateMarkStore(defaults: defaults)
        XCTAssertEqual(restored.teleports, ["p2": LibraryTeleportRecord(lastAtEpochMs: 1_789_799_520_123, count: 1)])
        XCTAssertEqual(restored.favorites, ["p1"])
        XCTAssertEqual(restored.marks, ["p1": Date(timeIntervalSince1970: 1_788_138_000)])
    }

    /// 記錄、清除、開關都立刻寫回,換一個新的 store 讀回仍相同。前往不是造訪標記;
    /// 舊的 Snapshot 鍵仍然只有 0.6.8 認得的兩個欄位,降版也讀得到。
    func testTeleportHistoryAndHideTogglePersistAcrossStores() throws {
        let suiteName = "gflyer.teleport-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Date(timeIntervalSince1970: 1_789_799_520.123)
        let second = Date(timeIntervalSince1970: 1_789_866_300)

        let store = CoordinateMarkStore(defaults: defaults)
        XCTAssertTrue(store.toggleFavorite("p1"))
        store.recordTeleport("p1", now: first)
        store.recordTeleport("p1", now: second)
        store.recordTeleport("p2", now: first)
        store.setHideTeleported(true)

        var restored = CoordinateMarkStore(defaults: defaults)
        XCTAssertEqual(restored.teleports, [
            "p1": LibraryTeleportRecord(lastAtEpochMs: 1_789_866_300_000, count: 2),
            "p2": LibraryTeleportRecord(lastAtEpochMs: 1_789_799_520_123, count: 1),
        ])
        XCTAssertTrue(restored.hideTeleported)
        XCTAssertEqual(restored.favorites, ["p1"])
        XCTAssertEqual(restored.marks, [:])

        restored.clearTeleport("p1")
        restored.clearTeleport("never-recorded")
        restored.setHideTeleported(false)
        restored = CoordinateMarkStore(defaults: defaults)
        XCTAssertEqual(restored.teleports, ["p2": LibraryTeleportRecord(lastAtEpochMs: 1_789_799_520_123, count: 1)])
        XCTAssertFalse(restored.hideTeleported)

        let snapshotData = try XCTUnwrap(defaults.data(forKey: marksKey))
        let snapshot = try XCTUnwrap(try JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        XCTAssertEqual(Set(snapshot.keys), ["favorites", "marks"])
        XCTAssertNotNil(defaults.data(forKey: teleportsKey))
        XCTAssertFalse(defaults.bool(forKey: hideTeleportedKey))
    }

    /// 布林不算數字,和圖鑑解析、備份同一條規則:at 是布林略過那一筆,n 是布林當成 1。
    func testTeleportHistoryTreatsBooleansAsNotNumbers() {
        let decoded = LibraryTeleportHistory.decode(Data(#"{"a":{"at":true,"n":2},"b":{"at":5000,"n":true}}"#.utf8))
        XCTAssertEqual(decoded, ["b": LibraryTeleportRecord(lastAtEpochMs: 5000, count: 1)])
    }

    /// 「預覽」與無效座標都不記錄前往。被接受的「傳送」會真的開始模擬、模擬中被拒絕要先有進行中的模擬,
    /// 這兩條留給上機驗證(規格第 6 節)。
    @MainActor
    func testPreviewAndInvalidCoordinatesDoNotRecordATeleport() throws {
        let suiteName = "gflyer.teleport-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let simulation = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults)
        )
        let library = CoordinateLibraryController(
            repository: CoordinateLibraryRepository(
                urlString: "",
                cacheDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("gflyer-teleport-tests-\(UUID().uuidString)", isDirectory: true)
            ),
            markStore: CoordinateMarkStore(defaults: defaults),
            apiClient: MessageBoardAPIClient(baseURLString: "")
        )
        let valid = LibraryCoordinate(
            id: "p1", categoryID: "purespot", subcategoryID: nil, name: "維多利亞公園",
            latitude: 22.2823, longitude: 114.1884, note: "", period: "",
            remindDays: nil, thumbnailURL: nil, icon: nil, enabled: true, updatedAt: nil
        )
        let invalid = LibraryCoordinate(
            id: "p9", categoryID: "purespot", subcategoryID: nil, name: "超出範圍",
            latitude: 91, longitude: 114.1884, note: "", period: "",
            remindDays: nil, thumbnailURL: nil, icon: nil, enabled: true, updatedAt: nil
        )

        XCTAssertTrue(library.use(valid, startImmediately: false, simulation: simulation))
        XCTAssertEqual(simulation.selectedCoordinate, valid.geoCoordinate)
        XCTAssertEqual(library.teleports, [:])

        XCTAssertFalse(library.use(invalid, startImmediately: true, simulation: simulation))
        XCTAssertEqual(library.errorMessage, "這筆座標資料無效")
        XCTAssertEqual(library.teleports, [:])
        XCTAssertEqual(CoordinateMarkStore(defaults: defaults).teleports, [:])
    }

    /// 清單:計數在隱藏之前算(搜尋也在隱藏之前)、造訪標記不算前往、「⏲ 提醒中」不套用隱藏也沒有開關列、
    /// ★ 最愛照樣隱藏、全部前往過與搜尋不到是兩種空清單。
    @MainActor
    func testControllerHidesTeleportedCoordinatesExceptOnTheRemindersTab() async throws {
        let suiteName = "gflyer.teleport-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gflyer-teleport-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let json = """
        {
          "schemaVersion": 1, "revision": 5,
          "categories": [{"id": "purespot", "name": "純點"}],
          "coordinates": [
            {"id": "a1", "categoryId": "purespot", "name": "甲", "lat": 25.0, "lng": 121.5, "remindDays": 7},
            {"id": "a2", "categoryId": "purespot", "name": "乙", "lat": 25.1, "lng": 121.6, "remindDays": 7},
            {"id": "a3", "categoryId": "purespot", "name": "丙", "lat": 25.2, "lng": 121.7}
          ]
        }
        """
        try Data(json.utf8).write(to: cacheDirectory.appendingPathComponent("coordinate_library.json"))
        let library = CoordinateLibraryController(
            repository: CoordinateLibraryRepository(urlString: "", cacheDirectory: cacheDirectory),
            markStore: CoordinateMarkStore(defaults: defaults),
            apiClient: MessageBoardAPIClient(baseURLString: "")
        )
        library.loadIfNeeded()
        for _ in 0..<200 where library.library == nil || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(library.library)
        // 沒有最愛時,載入後切到第一個分類
        XCTAssertEqual(library.selectedTab, .category("purespot"))

        library.markVisited("a1")
        library.recordTeleport("a1")
        library.recordTeleport("a2")
        var listing = library.listing
        XCTAssertTrue(library.hideApplies)
        XCTAssertEqual(listing.visible.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(listing.countLabel, "已前往 2 / 3")

        library.setHideTeleported(true)
        listing = library.listing
        XCTAssertEqual(listing.visible.map(\.id), ["a3"])
        XCTAssertEqual(listing.countLabel, "已前往 2 / 3")
        XCTAssertNil(listing.emptyMessage)

        library.searchText = "乙"
        listing = library.listing
        XCTAssertEqual(listing.visible.map(\.id), [])
        XCTAssertEqual(listing.countLabel, "已前往 1 / 1")
        XCTAssertTrue(listing.isEmptyBecauseAllTeleported)
        XCTAssertEqual(listing.emptyMessage, "這裡的點都前往過了；關閉「隱藏已前往」就會再列出來。")

        library.searchText = "不存在"
        listing = library.listing
        XCTAssertEqual(listing.countLabel, "已前往 0 / 0")
        XCTAssertFalse(listing.isEmptyBecauseAllTeleported)
        XCTAssertEqual(listing.emptyMessage, "沒有符合的座標")
        library.searchText = ""

        // 只有 a1 有造訪標記與提醒天數;前往過也照列,開關的值不變
        library.selectedTab = .reminders
        listing = library.listing
        XCTAssertFalse(library.hideApplies)
        XCTAssertEqual(listing.visible.map(\.id), ["a1"])
        XCTAssertNil(listing.countLabel)
        XCTAssertNil(listing.emptyMessage)
        XCTAssertTrue(library.hideTeleported)

        library.toggleFavorite("a2")
        library.toggleFavorite("a3")
        library.selectedTab = .favorites
        listing = library.listing
        XCTAssertEqual(listing.visible.map(\.id), ["a3"])
        XCTAssertEqual(listing.countLabel, "已前往 1 / 2")

        // 清除後再列出;再傳送時次數從 1 開始
        library.clearTeleport("a2")
        XCTAssertEqual(library.listing.visible.map(\.id), ["a2", "a3"])
        library.recordTeleport("a2")
        XCTAssertEqual(library.teleports["a2"]?.count, 1)
        XCTAssertEqual(library.teleports["a1"]?.count, 1)
    }

    /// 回到前景時每天重新檢查(GFlyer-Suite docs/features/coordinate-library-refresh.md):還沒打開過圖鑑不抓、
    /// 未滿 24 小時不抓、滿 24 小時抓到新 revision;失敗不顯示訊息、也不算成功,下次回到前景再試。
    @MainActor
    func testRefreshIfStaleChecksTheOnlineLibraryAgainOnlyAfterADay() async throws {
        let suiteName = "gflyer.library-refresh-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gflyer-library-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubURLProtocol.self]
        LibraryStubURLProtocol.reset()
        defer { LibraryStubURLProtocol.reset() }
        LibraryStubURLProtocol.respond(statusCode: 200, body: Self.remoteLibrary(revision: 5))
        var now: Int64 = 1_000_000
        let library = CoordinateLibraryController(
            repository: CoordinateLibraryRepository(
                urlString: "https://example.com/coordinates/coordinates.json",
                session: URLSession(configuration: configuration),
                cacheDirectory: cacheDirectory
            ),
            markStore: CoordinateMarkStore(defaults: defaults),
            apiClient: MessageBoardAPIClient(baseURLString: ""),
            monotonicMilliseconds: { now }
        )

        // 還沒打開過圖鑑:回到前景不抓(第一次打開圖鑑才下載,D9)
        XCTAssertFalse(library.refreshIfStale())
        XCTAssertEqual(LibraryStubURLProtocol.requestCount, 0)

        library.loadIfNeeded()
        for _ in 0..<200 where library.library?.revision != 5 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.library?.revision, 5)
        XCTAssertEqual(LibraryStubURLProtocol.requestCount, 1)

        // 未滿 24 小時:不抓
        LibraryStubURLProtocol.respond(statusCode: 200, body: Self.remoteLibrary(revision: 6))
        now += CoordinateLibraryRefreshPolicy.intervalMilliseconds - 1
        XCTAssertFalse(library.refreshIfStale())

        // 剛好 24 小時:在背景抓到新的 revision,不顯示訊息
        now += 1
        XCTAssertTrue(library.refreshIfStale())
        for _ in 0..<200 where library.library?.revision != 6 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.library?.revision, 6)
        XCTAssertEqual(LibraryStubURLProtocol.requestCount, 2)
        XCTAssertNil(library.errorMessage)
        XCTAssertFalse(library.refreshIfStale(), "剛成功過")

        // 失敗:不顯示訊息、不算成功,下次回到前景再試
        LibraryStubURLProtocol.respond(statusCode: 500, body: Data())
        now += CoordinateLibraryRefreshPolicy.intervalMilliseconds
        XCTAssertTrue(library.refreshIfStale())
        for _ in 0..<200 where LibraryStubURLProtocol.requestCount < 3 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(LibraryStubURLProtocol.requestCount, 3)
        XCTAssertEqual(library.library?.revision, 6)
        XCTAssertNil(library.errorMessage)

        LibraryStubURLProtocol.respond(statusCode: 200, body: Self.remoteLibrary(revision: 6))
        XCTAssertTrue(library.refreshIfStale(), "失敗不算成功,馬上回到前景也再試")
        for _ in 0..<200 where LibraryStubURLProtocol.requestCount < 4 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(LibraryStubURLProtocol.requestCount, 4)
        XCTAssertFalse(library.refreshIfStale())
    }

    /// 入口旁的「NEW」(GFlyer-Suite docs/features/coordinate-library-new-badge.md):第一次下載不亮、線上版多了
    /// 座標才亮、打開圖鑑後不亮、重新開 App 仍記得、只有刪除的更新不亮。
    @MainActor
    func testNewBadgeLightsOnlyForAddedCoordinatesUntilTheLibraryIsOpened() async throws {
        let suiteName = "gflyer.library-new-badge-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gflyer-library-new-badge-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LibraryStubURLProtocol.reset()
        defer { LibraryStubURLProtocol.reset() }
        func makeController() -> CoordinateLibraryController {
            CoordinateLibraryController(
                repository: CoordinateLibraryRepository(
                    urlString: "https://example.com/coordinates/coordinates.json",
                    session: session,
                    cacheDirectory: cacheDirectory
                ),
                markStore: CoordinateMarkStore(defaults: defaults),
                apiClient: MessageBoardAPIClient(baseURLString: "")
            )
        }
        let library = makeController()

        // 第一次下載:之前手上沒有資料,不算新座標
        LibraryStubURLProtocol.respond(statusCode: 200, body: Self.remoteLibrary(revision: 5, ids: ["a1"]))
        library.loadIfNeeded()
        for _ in 0..<200 where library.library?.revision != 5 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.library?.revision, 5)
        XCTAssertFalse(library.hasNewCoordinates)

        // 線上版多了 a2:亮,重新開 App 也還亮
        LibraryStubURLProtocol.respond(statusCode: 200, body: Self.remoteLibrary(revision: 6, ids: ["a1", "a2"]))
        library.refreshManually()
        for _ in 0..<200 where library.library?.revision != 6 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.library?.revision, 6)
        XCTAssertTrue(library.hasNewCoordinates)
        XCTAssertTrue(makeController().hasNewCoordinates)

        // 打開圖鑑:不亮,重新開 App 也不亮
        library.markNewCoordinatesSeen()
        XCTAssertFalse(library.hasNewCoordinates)
        XCTAssertFalse(makeController().hasNewCoordinates)

        // 只有刪除的更新:不亮
        LibraryStubURLProtocol.respond(statusCode: 200, body: Self.remoteLibrary(revision: 7, ids: ["a2"]))
        library.refreshManually()
        for _ in 0..<200 where library.library?.revision != 7 || library.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(library.library?.revision, 7)
        XCTAssertFalse(library.hasNewCoordinates)
    }

    private static func remoteLibrary(revision: Int, ids: [String] = ["a1"]) -> Data {
        let coordinates = ids
            .map { #"{"id": "\#($0)", "categoryId": "purespot", "name": "\#($0)", "lat": 25.0, "lng": 121.5}"# }
            .joined(separator: ", ")
        return Data("""
        {
          "schemaVersion": 1, "revision": \(revision),
          "categories": [{"id": "purespot", "name": "純點"}],
          "coordinates": [\(coordinates)]
        }
        """.utf8)
    }
}

/// 座標圖鑑下載用的 URLProtocol:回傳設定好的狀態碼與內容並計算請求次數,不連網路。
private final class LibraryStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var response: (statusCode: Int, body: Data)?
    private static var count = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    static func respond(statusCode: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        response = (statusCode, body)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        response = nil
        count = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        let stub = Self.response
        Self.lock.unlock()
        guard let url = request.url,
              let stub,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
