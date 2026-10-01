import XCTest
@testable import GFlyerIOS

/// 造訪提醒「下次可去時間」的顯示文字（DRIFT D27）。期望值照抄 GFlyer-Suite
/// `contracts/fixtures/reminder/visit-reminder.json` 的 `format` —— iOS 的 CI 拿不到那個 repo，
/// 所以改 fixture 時這裡要跟著改。
final class VisitReminderFormatTests: XCTestCase {

    /// 格式化用 fixture 指定的時區，不是裝置時區。有標記的 case 先由 nextAvailableAt 算出時間點，
    /// 檢查等於 fixture 的 nextAvailableAtEpochMs，再格式化。
    func testVisitReminderDisplayTextMatchesTheSharedFixture() throws {
        let cases: [(
            name: String,
            markedAtEpochMs: Int64?,
            remindDays: Int?,
            nextAvailableAtEpochMs: Int64,
            zone: String,
            expected: String
        )] = [
            ("android-unit-test-value", 1787554800000, 7, 1788159600000, "Asia/Taipei",
             "2026/08/31 15:00"),
            ("minutes-are-not-shown-or-rounded", nil, nil, 1788163199999, "Asia/Taipei",
             "2026/08/31 15:00"),
            ("twenty-four-hour-clock", nil, nil, 1772982300000, "Asia/Taipei",
             "2026/03/08 23:00"),
            ("midnight-is-00", nil, nil, 1772985600000, "Asia/Taipei",
             "2026/03/09 00:00"),
            ("date-and-year-in-the-display-zone-taipei", nil, nil, 1798734600000, "Asia/Taipei",
             "2027/01/01 00:00"),
            ("date-and-year-in-the-display-zone-utc", nil, nil, 1798734600000, "UTC",
             "2026/12/31 16:00"),
            ("half-hour-zone-shows-the-hour-only", nil, nil, 1790413200000, "Asia/Kolkata",
             "2026/09/26 14:00"),
            ("fixed-24-hours-across-daylight-saving", 1772902800000, 7, 1773507600000, "America/New_York",
             "2026/03/14 13:00"),
        ]
        XCTAssertEqual(cases.count, 8)
        for testCase in cases {
            let zone = try XCTUnwrap(TimeZone(identifier: testCase.zone), testCase.zone)
            if let markedAtEpochMs = testCase.markedAtEpochMs, let remindDays = testCase.remindDays {
                // nextAvailableAt 不收時區，CI 的預設時區通常是沒有夏令時間的 UTC：
                // 暫時把預設時區換成 case 的時區，照日曆加天數的寫法才會在這裡失敗。
                let markedAt = Date(timeIntervalSince1970: TimeInterval(markedAtEpochMs) / 1_000)
                let computed = withDefaultTimeZone(zone) {
                    VisitReminder.nextAvailableAt(markedAt: markedAt, remindDays: remindDays)
                }
                XCTAssertEqual(
                    LibraryTeleportHistory.epochMs(computed),
                    testCase.nextAvailableAtEpochMs,
                    "\(testCase.name) (nextAvailableAt)"
                )
            } else {
                // fixture 的標記時間與天數一定成對出現。
                XCTAssertNil(testCase.markedAtEpochMs, testCase.name)
                XCTAssertNil(testCase.remindDays, testCase.name)
            }
            let nextAvailableAt = Date(timeIntervalSince1970: TimeInterval(testCase.nextAvailableAtEpochMs) / 1_000)
            XCTAssertEqual(VisitReminder.format(nextAvailableAt, timeZone: zone), testCase.expected, testCase.name)
        }
    }

    /// 不傳 timeZone 時每次呼叫都讀當下的 TimeZone.current（Android 每次用 ZoneId.systemDefault()）：
    /// 換了時區之後不能還沿用第一次快取的格式器。
    func testDefaultTimeZoneIsReadOnEachCall() throws {
        let instant = Date(timeIntervalSince1970: 1_798_734_600) // 2026-12-31T16:30Z
        let taipei = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }

        NSTimeZone.default = taipei
        try XCTSkipUnless(
            TimeZone.current.identifier == taipei.identifier,
            "TimeZone.current 沒有跟著 NSTimeZone.default，無法在單元測試裡換預設時區"
        )
        XCTAssertEqual(VisitReminder.format(instant), "2027/01/01 00:00")

        NSTimeZone.default = utc
        try XCTSkipUnless(
            TimeZone.current.identifier == utc.identifier,
            "TimeZone.current 沒有跟著 NSTimeZone.default，無法在單元測試裡換預設時區"
        )
        XCTAssertEqual(VisitReminder.format(instant), "2026/12/31 16:00")
    }

    /// 執行 body 期間把 App 的預設時區換成 zone，結束後還原。
    private func withDefaultTimeZone<T>(_ zone: TimeZone, _ body: () throws -> T) rethrows -> T {
        let original = NSTimeZone.default
        NSTimeZone.default = zone
        defer { NSTimeZone.default = original }
        return try body()
    }
}
