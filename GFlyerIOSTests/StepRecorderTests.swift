import XCTest
@testable import GFlyerIOS

@MainActor
final class StepRecorderTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "gflyer.steps-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: - 捷徑網址

    func testRunShortcutURLEncodesNestedCallbacks() throws {
        let id = UUID()
        let url = try XCTUnwrap(
            StepRecorderController.runShortcutURL(name: "GFlyer 補錄步數", steps: 3_000, entryID: id)
        )
        XCTAssertEqual(url.scheme, "shortcuts")
        XCTAssertEqual(url.host, "x-callback-url")
        XCTAssertEqual(url.path, "/run-shortcut")

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        XCTAssertEqual(value("name"), "GFlyer 補錄步數")
        XCTAssertEqual(value("input"), "text")
        XCTAssertEqual(value("text"), "3000")

        // 巢狀回呼網址必須完整保留：解析後仍要看得到 id 這個查詢參數
        let success = try XCTUnwrap(value("x-success"))
        XCTAssertEqual(success, "gflyer://steps/done?id=\(id.uuidString)")
        XCTAssertEqual(try XCTUnwrap(value("x-error")), "gflyer://steps/failed?id=\(id.uuidString)")

        // 未編碼的 & 或 ? 會讓外層網址被截斷，這裡確認沒有洩漏出去
        let raw = url.absoluteString
        XCTAssertTrue(raw.contains("x-success=gflyer%3A%2F%2Fsteps%2Fdone%3Fid%3D"))
        XCTAssertEqual(raw.components(separatedBy: "&").count, 5)
    }

    // MARK: - 回呼

    func testCallbackMarksEntryConfirmedOrFailed() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = StepRecorderController(defaults: defaults)

        // 走與 record 相同的路徑建立待確認紀錄，只是不開啟捷徑 App
        let entry = try XCTUnwrap(recorder.prepareRecord(steps: 1_000)).entry
        XCTAssertEqual(recorder.todaySteps, 0, "未確認的項目不應計入合計")

        let done = try XCTUnwrap(URL(string: "gflyer://steps/done?id=\(entry.id.uuidString)"))
        XCTAssertTrue(recorder.handleCallback(done))
        XCTAssertEqual(recorder.entries.first?.status, .confirmed)
        XCTAssertEqual(recorder.todaySteps, 1_000)

        let failedEntry = try XCTUnwrap(recorder.prepareRecord(steps: 500)).entry
        let failed = try XCTUnwrap(URL(string: "gflyer://steps/failed?id=\(failedEntry.id.uuidString)"))
        XCTAssertTrue(recorder.handleCallback(failed))
        XCTAssertEqual(recorder.entries.first?.status, .failed)
        XCTAssertEqual(recorder.todaySteps, 1_000, "失敗的 500 步不計入，先前確認的 1000 步仍保留")
    }

    func testCallbackIgnoresUnrelatedURLs() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = StepRecorderController(defaults: defaults)
        for text in [
            "https://example.com/steps/done",
            "gflyer://other/done",
            "gflyer://steps/unknown",
        ] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertFalse(recorder.handleCallback(url), text)
        }
    }

    // MARK: - 七天紀錄

    func testHistoryPrunesBeyondSevenDaysAndGroupsByDay() throws {
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now)!
        }
        let entries = [
            StepRecordEntry(steps: 100, requestedAt: now, status: .confirmed),
            StepRecordEntry(steps: 200, requestedAt: now.addingTimeInterval(-3_600), status: .confirmed),
            StepRecordEntry(steps: 300, requestedAt: daysAgo(6), status: .confirmed),
            StepRecordEntry(steps: 400, requestedAt: daysAgo(7), status: .confirmed),
            StepRecordEntry(steps: 500, requestedAt: daysAgo(30), status: .confirmed),
        ]
        let kept = StepRecordHistory.pruned(entries, now: now, calendar: calendar)
        XCTAssertEqual(kept.map(\.steps), [100, 200, 300], "只保留含今天在內的七天")

        let days = StepRecordHistory.groupedByDay(kept, calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.confirmedSteps, 300, "同一天的兩筆要加總")
        XCTAssertEqual(days.first?.entries.count, 2)
        XCTAssertFalse(days.first?.hasUnconfirmed ?? true)
    }

    func testDayTotalsCountOnlyConfirmedEntries() {
        let now = Date()
        let day = StepRecordDay(
            date: Calendar.current.startOfDay(for: now),
            entries: [
                StepRecordEntry(steps: 1_000, requestedAt: now, status: .confirmed),
                StepRecordEntry(steps: 2_000, requestedAt: now, status: .pending),
                StepRecordEntry(steps: 4_000, requestedAt: now, status: .failed),
            ]
        )
        XCTAssertEqual(day.confirmedSteps, 1_000)
        XCTAssertTrue(day.hasUnconfirmed)
    }

    func testStepClampingAndPresets() {
        XCTAssertEqual(StepRecordHistory.clampSteps(0), StepRecordHistory.minimumSteps)
        XCTAssertEqual(StepRecordHistory.clampSteps(999_999), StepRecordHistory.maximumSteps)
        XCTAssertEqual(StepRecordHistory.clampSteps(3_000), 3_000)
        XCTAssertEqual(StepRecordHistory.presetStepCounts, [1_000, 3_000, 5_000])
    }

    // MARK: - 一鍵補錄

    func testShortcutIsVerifiedOnlyAfterASuccessfulCallback() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = StepRecorderController(defaults: defaults)
        XCTAssertFalse(recorder.isShortcutVerified, "還沒跑過捷徑時工具列不該直接送出")

        let failedEntry = try XCTUnwrap(recorder.prepareRecord(steps: 1_000)).entry
        let failed = try XCTUnwrap(URL(string: "gflyer://steps/failed?id=\(failedEntry.id.uuidString)"))
        recorder.handleCallback(failed)
        XCTAssertFalse(recorder.isShortcutVerified, "捷徑回報失敗不算設定完成")

        let entry = try XCTUnwrap(recorder.prepareRecord(steps: 1_000)).entry
        let done = try XCTUnwrap(URL(string: "gflyer://steps/done?id=\(entry.id.uuidString)"))
        recorder.handleCallback(done)
        XCTAssertTrue(recorder.isShortcutVerified)

        // 紀錄只留七天，但驗證旗標不該跟著過期
        XCTAssertTrue(StepRecorderController(defaults: defaults).isShortcutVerified)
    }

    func testQuickStepCountDefaultsClampsAndPersists() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = StepRecorderController(defaults: defaults)
        XCTAssertEqual(recorder.quickStepCount, StepRecorderController.defaultQuickStepCount)

        recorder.quickStepCount = 999_999
        XCTAssertEqual(recorder.quickStepCount, StepRecordHistory.maximumSteps, "超出上限要夾住")

        recorder.quickStepCount = 2_500
        XCTAssertEqual(StepRecorderController(defaults: defaults).quickStepCount, 2_500)
    }

    // MARK: - 保存

    func testEntriesAndShortcutNameSurviveRelaunch() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let recorder = StepRecorderController(defaults: defaults)
        recorder.shortcutName = "我的補步數"
        let entry = try XCTUnwrap(recorder.prepareRecord(steps: 5_000)).entry
        let done = try XCTUnwrap(URL(string: "gflyer://steps/done?id=\(entry.id.uuidString)"))
        recorder.handleCallback(done)

        let restored = StepRecorderController(defaults: defaults)
        XCTAssertEqual(restored.shortcutName, "我的補步數")
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.status, .confirmed)
        XCTAssertEqual(restored.todaySteps, 5_000)
    }
}
