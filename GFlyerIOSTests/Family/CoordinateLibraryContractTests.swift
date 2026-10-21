import XCTest
@testable import GFlyerIOS

/// 座標圖鑑的共用規則（前往紀錄、檢查線上版、「NEW」），只在親友版。期望值照抄 GFlyer-Suite 的
/// golden fixture —— iOS 的 CI 拿不到那個 repo,所以改 fixture 時這裡要跟著改;Android 的測試直接讀同一份 JSON。
/// 從 `SharedContractTests` 搬出來(docs/APP_STORE_PLAN.md 第 9 項)。
final class CoordinateLibraryContractTests: XCTestCase {

    // MARK: - contracts/fixtures/coordinate-library/teleport-history.json

    /// fixture 的存放形狀 `{id: {"at": epoch 毫秒, "n": 次數}}`。
    private typealias TeleportTable = [String: (at: Int64, n: Int)]

    private enum TeleportOperation {
        case record(id: String, nowEpochMs: Int64)
        case clear(id: String)
    }

    private func teleportRecords(_ table: TeleportTable) -> [String: LibraryTeleportRecord] {
        table.mapValues { LibraryTeleportRecord(lastAtEpochMs: $0.at, count: $0.n) }
    }

    private func teleportDate(_ epochMs: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epochMs) / 1_000)
    }

    private func libraryCoordinate(_ id: String) -> LibraryCoordinate {
        LibraryCoordinate(
            id: id, categoryID: "postcard", subcategoryID: nil, name: id,
            latitude: 25.0339, longitude: 121.5645, note: "", period: "",
            remindDays: nil, thumbnailURL: nil, icon: nil, enabled: true, updatedAt: nil
        )
    }

    /// record 段:operations 依序套用在 initial 上。
    private let teleportRecordCases: [(name: String, initial: TeleportTable, operations: [TeleportOperation],
                                       expected: TeleportTable)] = [
        (
            "first-teleport-starts-count-at-one",
            [:],
            [.record(id: "pc-1", nowEpochMs: 1789799520123)],
            [
                "pc-1": (at: 1789799520123, n: 1),
            ]
        ),
        (
            "repeat-keeps-latest-time-and-increments-count",
            [:],
            [.record(id: "pc-1", nowEpochMs: 1789799520123), .record(id: "pc-1", nowEpochMs: 1789866300000), .record(id: "pc-1", nowEpochMs: 1789991250500)],
            [
                "pc-1": (at: 1789991250500, n: 3),
            ]
        ),
        (
            "time-is-stored-to-the-millisecond-not-rounded-to-the-hour",
            [:],
            [.record(id: "pure-3153", nowEpochMs: 1789799579999)],
            [
                "pure-3153": (at: 1789799579999, n: 1),
            ]
        ),
        (
            "other-coordinates-are-untouched",
            [
                "evt-001": (at: 2000, n: 3),
            ],
            [.record(id: "pc-1", nowEpochMs: 9000)],
            [
                "evt-001": (at: 2000, n: 3),
                "pc-1": (at: 9000, n: 1),
            ]
        ),
        (
            "earlier-clock-still-overwrites-the-time",
            [
                "pc-1": (at: 1789866300000, n: 2),
            ],
            [.record(id: "pc-1", nowEpochMs: 1789799520123)],
            [
                "pc-1": (at: 1789799520123, n: 3),
            ]
        ),
        (
            "count-continues-from-a-stored-record",
            [
                "pc-7": (at: 1700000000000, n: 41),
            ],
            [.record(id: "pc-7", nowEpochMs: 1789799520123)],
            [
                "pc-7": (at: 1789799520123, n: 42),
            ]
        ),
        (
            "clear-removes-only-that-coordinate",
            [
                "pc-1": (at: 1789799520123, n: 2),
                "pc-2": (at: 1789866300000, n: 1),
            ],
            [.clear(id: "pc-1")],
            [
                "pc-2": (at: 1789866300000, n: 1),
            ]
        ),
        (
            "clear-of-an-unrecorded-coordinate-changes-nothing",
            [
                "pc-2": (at: 1789866300000, n: 1),
            ],
            [.clear(id: "pc-9")],
            [
                "pc-2": (at: 1789866300000, n: 1),
            ]
        ),
        (
            "record-after-clear-starts-again-at-one",
            [
                "pc-1": (at: 5000, n: 4),
            ],
            [.clear(id: "pc-1"), .record(id: "pc-1", nowEpochMs: 6000)],
            [
                "pc-1": (at: 6000, n: 1),
            ]
        ),
    ]

    /// decode 段:raw 是存放的 JSON 文字,nil 表示從未存過。
    private let teleportDecodeCases: [(name: String, raw: String?, expected: TeleportTable)] = [
        (
            "never-stored-is-empty",
            nil,
            [:]
        ),
        (
            "empty-text-is-empty",
            "",
            [:]
        ),
        (
            "blank-text-is-empty",
            "   ",
            [:]
        ),
        (
            "not-json-is-empty",
            "{ not json",
            [:]
        ),
        (
            "top-level-array-is-empty",
            "[]",
            [:]
        ),
        (
            "empty-object-is-empty",
            "{}",
            [:]
        ),
        (
            "valid-entries",
            #"{"pc-1":{"at":1789799520123,"n":1},"pure-3153":{"at":1789991250500,"n":4}}"#,
            [
                "pc-1": (at: 1789799520123, n: 1),
                "pure-3153": (at: 1789991250500, n: 4),
            ]
        ),
        (
            "bad-entries-are-skipped-one-by-one",
            #"{"ok":{"at":5000,"n":2},"no-time":{"n":3},"zero-time":{"at":0,"n":1},"negative-time":{"at":-1,"n":1},"text-time":{"at":"abc","n":1},"number-value":12,"string-value":"x","null-value":null,"array-value":[1,2],"smallest-valid-time":{"at":1,"n":1}}"#,
            [
                "ok": (at: 5000, n: 2),
                "smallest-valid-time": (at: 1, n: 1),
            ]
        ),
        (
            "bad-count-means-at-least-once",
            #"{"zero-count":{"at":7000,"n":0},"negative-count":{"at":8000,"n":-3},"no-count":{"at":9000},"text-count":{"at":6000,"n":"abc"}}"#,
            [
                "zero-count": (at: 7000, n: 1),
                "negative-count": (at: 8000, n: 1),
                "no-count": (at: 9000, n: 1),
                "text-count": (at: 6000, n: 1),
            ]
        ),
    ]

    /// record:純函式與 `CoordinateMarkStore`(寫回 UserDefaults、換一個新的 store 讀回)都要得到同一份結果。
    /// clear 在 fixture 裡就是拿掉那個 id,和 `clearTeleport` 相同。
    func testTeleportRecordingMatchesTheSharedFixture() throws {
        XCTAssertEqual(teleportRecordCases.count, 9)
        for testCase in teleportRecordCases {
            var records = teleportRecords(testCase.initial)
            let suiteName = "gflyer.teleport-fixture.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(LibraryTeleportHistory.encode(records), forKey: "gflyer.coordinate-teleports.v1")
            let store = CoordinateMarkStore(defaults: defaults)
            XCTAssertEqual(store.teleports, records, "\(testCase.name) (initial)")

            for operation in testCase.operations {
                switch operation {
                case let .record(id, nowEpochMs):
                    records = LibraryTeleportHistory.record(records, id: id, nowEpochMs: nowEpochMs)
                    store.recordTeleport(id, now: teleportDate(nowEpochMs))
                case let .clear(id):
                    records.removeValue(forKey: id)
                    store.clearTeleport(id)
                }
            }

            let expected = teleportRecords(testCase.expected)
            XCTAssertEqual(records, expected, testCase.name)
            XCTAssertEqual(store.teleports, expected, "\(testCase.name) (store)")
            XCTAssertEqual(CoordinateMarkStore(defaults: defaults).teleports, expected, "\(testCase.name) (reloaded)")
        }
    }

    /// decode:整份讀不出來是空的、逐筆略過壞掉的、n 至少 1。
    func testTeleportDecodingMatchesTheSharedFixture() {
        XCTAssertEqual(teleportDecodeCases.count, 9)
        for testCase in teleportDecodeCases {
            XCTAssertEqual(
                LibraryTeleportHistory.decode(testCase.raw.map { Data($0.utf8) }),
                teleportRecords(testCase.expected),
                testCase.name
            )
        }
    }

    /// record 與 decode 每個 expected 都編碼成 storage 的形狀,再解回來得到同一份資料。
    func testEncodedTeleportsUseTheSharedStorageShapeAndDecodeBack() throws {
        let samples = teleportRecordCases.map { $0.expected } + teleportDecodeCases.map { $0.expected }
        for table in samples {
            let records = teleportRecords(table)
            let encoded = LibraryTeleportHistory.encode(records)
            let object = try JSONSerialization.jsonObject(with: encoded)
            let root = try XCTUnwrap(object as? [String: [String: NSNumber]])
            XCTAssertEqual(Set(root.keys), Set(table.keys))
            for (id, entry) in root {
                XCTAssertEqual(Set(entry.keys), ["at", "n"], id)
                XCTAssertEqual(entry["at"]?.int64Value, table[id]?.at, id)
                XCTAssertEqual(entry["n"]?.intValue, table[id]?.n, id)
            }
            XCTAssertEqual(LibraryTeleportHistory.decode(encoded), records)
        }
        // 毫秒整數,不是秒數的小數;和 fixture storage.example 同一種寫法
        let single = LibraryTeleportHistory.encode(["pc-1": LibraryTeleportRecord(lastAtEpochMs: 1789799520123, count: 1)])
        XCTAssertEqual(String(decoding: single, as: UTF8.self), #"{"pc-1":{"at":1789799520123,"n":1}}"#)
    }

    /// format:用 fixture 指定的時區,不是裝置時區。
    func testTeleportTimeTextMatchesTheSharedFixture() throws {
        let cases: [(name: String, epochMs: Int64, nowEpochMs: Int64, zone: String, short: String, full: String)] = [
            ("same-year-omits-the-year", 1789799520000, 1796083200000, "Asia/Taipei",
             "09/19 14:32", "2026/09/19 14:32"),
            ("earlier-year-shows-the-year", 1789799520000, 1799107200000, "Asia/Taipei",
             "2026/09/19 14:32", "2026/09/19 14:32"),
            ("later-year-shows-the-year", 1801454400000, 1798675200000, "Asia/Taipei",
             "2027/02/01 12:00", "2027/02/01 12:00"),
            ("seconds-are-dropped-not-rounded", 1789799579999, 1796083200000, "Asia/Taipei",
             "09/19 14:32", "2026/09/19 14:32"),
            ("twenty-four-hour-clock", 1772982300000, 1790553600000, "Asia/Taipei",
             "03/08 23:05", "2026/03/08 23:05"),
            ("midnight-is-00", 1772985600000, 1790553600000, "Asia/Taipei",
             "03/09 00:00", "2026/03/09 00:00"),
            ("year-is-compared-in-the-display-zone-taipei", 1798734600000, 1798761600000, "Asia/Taipei",
             "01/01 00:30", "2027/01/01 00:30"),
            ("year-is-compared-in-the-display-zone-utc", 1798734600000, 1798761600000, "UTC",
             "2026/12/31 16:30", "2026/12/31 16:30"),
            ("daylight-saving-offset-is-applied", 1783180800000, 1785542400000, "America/New_York",
             "07/04 12:00", "2026/07/04 12:00"),
            ("standard-time-offset-is-applied", 1768496400000, 1780272000000, "America/New_York",
             "01/15 12:00", "2026/01/15 12:00"),
        ]
        XCTAssertEqual(cases.count, 10)
        for testCase in cases {
            let zone = try XCTUnwrap(TimeZone(identifier: testCase.zone), testCase.zone)
            XCTAssertEqual(
                LibraryTeleportHistory.formatShort(epochMs: testCase.epochMs, nowEpochMs: testCase.nowEpochMs, timeZone: zone),
                testCase.short,
                "\(testCase.name) (short)"
            )
            XCTAssertEqual(
                LibraryTeleportHistory.formatFull(epochMs: testCase.epochMs, timeZone: zone),
                testCase.full,
                "\(testCase.name) (full)"
            )
        }
    }

    /// summary:列表用 short、選單用 full。
    func testTeleportSummaryMatchesTheSharedFixture() throws {
        let cases: [(name: String, at: Int64, n: Int, nowEpochMs: Int64, zone: String, row: String, detail: String)] = [
            ("once-has-no-count", 1789799520000, 1, 1790553600000, "Asia/Taipei",
             "➤ 已前往 09/19 14:32", "➤ 已前往 2026/09/19 14:32"),
            ("twice-shows-the-count", 1789799520000, 2, 1790553600000, "Asia/Taipei",
             "➤ 已前往 09/19 14:32 · 2 次", "➤ 已前往 2026/09/19 14:32 · 2 次"),
            ("two-digit-count", 1789799520000, 12, 1790553600000, "Asia/Taipei",
             "➤ 已前往 09/19 14:32 · 12 次", "➤ 已前往 2026/09/19 14:32 · 12 次"),
            ("last-year-shows-the-year-in-the-row-too", 1767196740000, 3, 1790553600000, "Asia/Taipei",
             "➤ 已前往 2025/12/31 23:59 · 3 次", "➤ 已前往 2025/12/31 23:59 · 3 次"),
        ]
        XCTAssertEqual(cases.count, 4)
        for testCase in cases {
            let zone = try XCTUnwrap(TimeZone(identifier: testCase.zone), testCase.zone)
            let record = LibraryTeleportRecord(lastAtEpochMs: testCase.at, count: testCase.n)
            let short = LibraryTeleportHistory.formatShort(epochMs: record.lastAtEpochMs, nowEpochMs: testCase.nowEpochMs, timeZone: zone)
            let full = LibraryTeleportHistory.formatFull(epochMs: record.lastAtEpochMs, timeZone: zone)
            XCTAssertEqual(LibraryTeleportHistory.summary(record, time: short), testCase.row, "\(testCase.name) (row)")
            XCTAssertEqual(LibraryTeleportHistory.summary(record, time: full), testCase.detail, "\(testCase.name) (detail)")
        }
    }

    /// filter:hideApplies 為 false 代表「⏲ 提醒中」分頁。markedIDs(造訪提醒標記)只是干擾項 ——
    /// `LibraryTeleportHistory.listing` 根本不看造訪標記;照抄只為了和 fixture 一一對得上。
    func testHideTeleportedListingMatchesTheSharedFixture() {
        let cases: [(name: String, coordinateIDs: [String], records: TeleportTable, markedIDs: [String],
                     hideTeleported: Bool, hideApplies: Bool, visibleIDs: [String], teleportedCount: Int,
                     total: Int, countLabel: String?, emptyMessage: String?)] = [
            (
                "hide-off-lists-everything-and-still-counts",
                ["pc-1", "pc-2", "pc-3"],
                [
                    "pc-2": (at: 1000, n: 1),
                ],
                [],
                false, true,
                ["pc-1", "pc-2", "pc-3"], 1, 3,
                "已前往 1 / 3",
                nil
            ),
            (
                "hide-on-removes-only-recorded-coordinates-keeping-order",
                ["fav-9", "pc-1", "pc-2", "pc-3", "pc-4"],
                [
                    "fav-9": (at: 1000, n: 1),
                    "pc-2": (at: 2000, n: 5),
                ],
                [],
                true, true,
                ["pc-1", "pc-3", "pc-4"], 2, 5,
                "已前往 2 / 5",
                nil
            ),
            (
                "count-is-taken-before-hiding",
                ["pc-1", "pc-2"],
                [
                    "pc-1": (at: 1000, n: 1),
                ],
                [],
                true, true,
                ["pc-2"], 1, 2,
                "已前往 1 / 2",
                nil
            ),
            (
                "records-outside-the-list-are-not-counted",
                ["pure-1", "pure-2"],
                [
                    "pure-2": (at: 1000, n: 1),
                    "pc-1": (at: 1000, n: 1),
                    "removed-7": (at: 1000, n: 9),
                ],
                [],
                true, true,
                ["pure-1"], 1, 2,
                "已前往 1 / 2",
                nil
            ),
            (
                "visit-marks-do-not-count-as-teleported",
                ["pc-1", "pc-2"],
                [:],
                ["pc-1", "pc-2"],
                true, true,
                ["pc-1", "pc-2"], 0, 2,
                "已前往 0 / 2",
                nil
            ),
            (
                "old-records-never-expire",
                ["pc-1", "pc-2"],
                [
                    "pc-1": (at: 1, n: 1),
                ],
                [],
                true, true,
                ["pc-2"], 1, 2,
                "已前往 1 / 2",
                nil
            ),
            (
                "everything-teleported-shows-the-hint",
                ["pc-1", "pc-2"],
                [
                    "pc-1": (at: 1000, n: 1),
                    "pc-2": (at: 2000, n: 2),
                ],
                [],
                true, true,
                [], 2, 2,
                "已前往 2 / 2",
                "這裡的點都前往過了；關閉「隱藏已前往」就會再列出來。"
            ),
            (
                "empty-list-with-hide-on-is-a-plain-no-match",
                [],
                [
                    "pc-1": (at: 1000, n: 1),
                ],
                [],
                true, true,
                [], 0, 0,
                "已前往 0 / 0",
                "沒有符合的座標"
            ),
            (
                "empty-list-with-hide-off-is-a-plain-no-match",
                [],
                [:],
                [],
                false, true,
                [], 0, 0,
                "已前往 0 / 0",
                "沒有符合的座標"
            ),
            (
                "reminders-tab-ignores-hide-and-has-no-filter-row",
                ["pc-1", "pc-2"],
                [
                    "pc-1": (at: 1000, n: 1),
                ],
                ["pc-1", "pc-2"],
                true, false,
                ["pc-1", "pc-2"], 1, 2,
                nil,
                nil
            ),
        ]
        XCTAssertEqual(cases.count, 10)
        for testCase in cases {
            let listing = LibraryTeleportHistory.listing(
                testCase.coordinateIDs.map { libraryCoordinate($0) },
                records: teleportRecords(testCase.records),
                hideTeleported: testCase.hideTeleported,
                hideApplies: testCase.hideApplies
            )
            XCTAssertEqual(listing.visible.map(\.id), testCase.visibleIDs, "\(testCase.name) visibleIds")
            XCTAssertEqual(listing.teleportedCount, testCase.teleportedCount, "\(testCase.name) teleportedCount")
            XCTAssertEqual(listing.total, testCase.total, "\(testCase.name) total")
            XCTAssertEqual(listing.countLabel, testCase.countLabel, "\(testCase.name) countLabel")
            XCTAssertEqual(listing.emptyMessage, testCase.emptyMessage, "\(testCase.name) emptyMessage")
        }
    }

    /// messages.texts。neverTeleported(「還沒從圖鑑前往過」)只在 Android 的詳情彈窗,clearedMessage
    /// (已清除前往紀錄)是 Android 清除後的提示;iOS 兩個都不顯示(規格第 7 節),所以沒有常數。
    func testTeleportTextsMatchTheSharedFixture() {
        XCTAssertEqual(LibraryTeleportHistory.hideToggleOff, "隱藏已前往")
        XCTAssertEqual(LibraryTeleportHistory.hideToggleOn, "✓ 隱藏已前往")
        XCTAssertEqual(LibraryTeleportHistory.countLabel(teleported: 3, total: 12), "已前往 3 / 12")
        let once = LibraryTeleportRecord(lastAtEpochMs: 1, count: 1)
        let many = LibraryTeleportRecord(lastAtEpochMs: 1, count: 7)
        XCTAssertEqual(LibraryTeleportHistory.summary(once, time: "T"), "➤ 已前往 T")
        XCTAssertEqual(LibraryTeleportHistory.summary(many, time: "T"), "➤ 已前往 T · 7 次")
        XCTAssertEqual(LibraryTeleportHistory.allTeleportedEmpty, "這裡的點都前往過了；關閉「隱藏已前往」就會再列出來。")
        XCTAssertEqual(LibraryTeleportHistory.noMatchEmpty, "沒有符合的座標")
        XCTAssertEqual(LibraryTeleportHistory.clearButton, "清除紀錄")
        // 容易打錯的字元:「✓」U+2713、「➤」U+27A4、「·」U+00B7、全形「；」U+FF1B
        XCTAssertEqual(LibraryTeleportHistory.hideToggleOn.unicodeScalars.first?.value, 0x2713)
        XCTAssertEqual(LibraryTeleportHistory.summary(many, time: "T").unicodeScalars.first?.value, 0x27A4)
        XCTAssertTrue(LibraryTeleportHistory.summary(many, time: "T").unicodeScalars.contains("\u{00B7}"))
        XCTAssertTrue(LibraryTeleportHistory.allTeleportedEmpty.unicodeScalars.contains("\u{FF1B}"))
    }

    /// contracts/fixtures/coordinate-library/refresh-interval.json(docs/features/coordinate-library-refresh.md 3.2)
    func testLibraryRefreshIntervalMatchesTheSharedFixture() {
        XCTAssertEqual(CoordinateLibraryRefreshPolicy.intervalMilliseconds, 86_400_000)
        let cases: [(name: String, lastSuccess: Int64?, now: Int64, stale: Bool)] = [
            ("never-succeeded", nil, 5_000, true),
            ("just-checked", 1_000_000, 1_000_000, false),
            ("one-millisecond-short-of-a-day", 1_000_000, 87_399_999, false),
            ("exactly-a-day", 1_000_000, 87_400_000, true),
            ("several-days", 1_000_000, 260_200_000, true),
            ("clock-went-backwards", 1_000_000, 999_999, true),
            ("beyond-32-bit-uptime-short-of-a-day", 9_000_000_000, 9_086_399_999, false),
            ("beyond-32-bit-uptime-a-day-later", 9_000_000_000, 9_086_400_000, true),
        ]
        for testCase in cases {
            XCTAssertEqual(
                CoordinateLibraryRefreshPolicy.isStale(
                    lastSuccessMilliseconds: testCase.lastSuccess,
                    nowMilliseconds: testCase.now
                ),
                testCase.stale,
                testCase.name
            )
        }
    }

    /// contracts/fixtures/coordinate-library/status-text.json(docs/features/coordinate-library-refresh.md 3.5)
    func testLibraryStatusTextMatchesTheSharedFixture() throws {
        let summaries: [(name: String, revision: Int64, updatedAt: String, count: Int, expected: String)] = [
            ("online-library", 5, "2026-10-08", 7207, "revision 5 · 更新 2026-10-08 · 共 7207 筆"),
            ("no-thousands-separator", 12, "2026-12-01", 12345, "revision 12 · 更新 2026-12-01 · 共 12345 筆"),
            ("empty-updated-at-is-left-out", 3, "", 0, "revision 3 · 共 0 筆"),
        ]
        for testCase in summaries {
            XCTAssertEqual(
                CoordinateLibraryStatusText.summary(
                    revision: testCase.revision,
                    updatedAt: testCase.updatedAt,
                    count: testCase.count
                ),
                testCase.expected,
                testCase.name
            )
        }
        let checked: [(name: String, epochMs: Int64?, timeZone: String, expected: String)] = [
            ("never-checked", nil, "Asia/Hong_Kong", "還沒有檢查過線上版"),
            ("hong-kong-drops-seconds", 1_791_592_245_000, "Asia/Hong_Kong", "最後檢查 2026/10/10 08:30"),
            ("hong-kong-just-after-midnight", 1_790_784_300_000, "Asia/Hong_Kong", "最後檢查 2026/10/01 00:05"),
            ("new-york-daylight-saving", 1_791_592_245_000, "America/New_York", "最後檢查 2026/10/09 20:30"),
            ("utc", 1_791_592_245_000, "UTC", "最後檢查 2026/10/10 00:30"),
            ("new-year-in-hong-kong", 1_798_732_800_000, "Asia/Hong_Kong", "最後檢查 2027/01/01 00:00"),
        ]
        for testCase in checked {
            let timeZone = try XCTUnwrap(TimeZone(identifier: testCase.timeZone), testCase.name)
            let date = testCase.epochMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
            XCTAssertEqual(
                CoordinateLibraryStatusText.checked(date, timeZone: timeZone),
                testCase.expected,
                testCase.name
            )
        }
    }

    /// contracts/fixtures/coordinate-library/new-badge.json(docs/features/coordinate-library-new-badge.md 3.1)
    func testLibraryNewBadgeMatchesTheSharedFixture() {
        XCTAssertEqual(CoordinateLibraryNewBadge.text, "NEW")
        let cases: [(name: String, unseen: Set<String>, previous: Set<String>?, current: Set<String>, expected: Set<String>)] = [
            ("first-download-is-not-new", [], nil, ["pc-1", "pure-2"], []),
            ("added-coordinates-are-new", [], ["pc-1", "pure-2"], ["pc-1", "pure-2", "pc-3", "pure-4"], ["pc-3", "pure-4"]),
            ("removals-only-are-not-new", [], ["pc-1", "pure-2", "pc-3"], ["pc-1", "pc-3"], []),
            ("same-ids-with-edits-are-not-new", [], ["pc-1", "pure-2"], ["pure-2", "pc-1"], []),
            ("keeps-unseen-from-an-earlier-revision", ["pc-3"], ["pc-1", "pc-3"], ["pc-1", "pc-3", "pc-5"], ["pc-3", "pc-5"]),
            ("drops-unseen-that-were-removed-again", ["pc-3", "pc-5"], ["pc-1", "pc-3", "pc-5"], ["pc-1", "pc-5"], ["pc-5"]),
            ("first-download-keeps-nothing-that-is-gone", ["pc-9"], nil, ["pc-1"], []),
            ("a-coordinate-that-comes-back-is-new-again", [], ["pc-1"], ["pc-1", "pc-2"], ["pc-2"]),
        ]
        for testCase in cases {
            XCTAssertEqual(
                CoordinateLibraryNewBadge.unseenAfterUpdate(
                    unseen: testCase.unseen,
                    previousIDs: testCase.previous,
                    currentIDs: testCase.current
                ),
                testCase.expected,
                testCase.name
            )
        }
    }
}
