import XCTest
@testable import GFlyerIOS

/// 三平台共用的規則。期望值照抄 GFlyer-Suite 的 golden fixture —— iOS 的 CI 拿不到那個 repo,
/// 所以改 fixture 時這裡要跟著改;Android 的測試直接讀同一份 JSON。
final class SharedContractTests: XCTestCase {

    /// contracts/fixtures/text/truncate-names.json(DRIFT D14)
    func testNameTruncationCountsCodePoints() {
        let walker = "\u{1F6B6}"
        let flag = "\u{1F1F9}\u{1F1FC}"
        let cases: [(name: String, input: String, limit: Int, expected: String)] = [
            ("ascii", "abcdefghij", 5, "abcde"),
            ("cjk", "台北一日遊路線", 4, "台北一日"),
            ("emoji-is-one-code-point", "走" + String(repeating: walker, count: 10), 6,
             "走" + String(repeating: walker, count: 5)),
            ("flag-is-two-code-points-and-may-be-split", flag + flag, 3, flag + "\u{1F1F9}"),
            ("combining-mark-is-its-own-code-point", "e\u{0301}e\u{0301}e\u{0301}", 3, "e\u{0301}e"),
            ("shorter-than-limit-is-unchanged", "短", 80, "短"),
            ("exactly-at-limit-is-unchanged", "五個字名稱", 5, "五個字名稱"),
        ]
        for testCase in cases {
            let actual = testCase.input.prefixCodePoints(testCase.limit)
            // String 的 == 用正規等價比較,"e\u{0301}" 和 "é" 會被當成相同;這裡要逐個 code point 比
            XCTAssertEqual(
                actual.unicodeScalars.map(\.value),
                testCase.expected.unicodeScalars.map(\.value),
                testCase.name
            )
        }
        XCTAssertEqual("abc".prefixCodePoints(0), "")
        XCTAssertEqual("abc".prefixCodePoints(-1), "")
    }

    /// contracts/fixtures/settings/auto-stop-minutes.json(DRIFT D15)
    func testAutoStopRoundsToNearestOptionPreferringTheLargerOne() {
        XCTAssertEqual(PlaybackSettings.autoStopOptions, [0, 30, 60, 120])
        let cases: [(minutes: Int, expected: Int)] = [
            (-5, 0), (0, 0), (10, 0), (15, 30), (29, 30), (30, 30), (45, 60),
            (60, 60), (89, 60), (90, 120), (120, 120), (200, 120), (1440, 120), (5000, 120),
        ]
        for testCase in cases {
            XCTAssertEqual(
                PlaybackSettings.nearestAutoStopOption(to: testCase.minutes),
                testCase.expected,
                "minutes=\(testCase.minutes)"
            )
        }
        // 極端值不可以在 abs 裡溢位
        XCTAssertEqual(PlaybackSettings.nearestAutoStopOption(to: .max), 120)
        XCTAssertEqual(PlaybackSettings.nearestAutoStopOption(to: .min), 0)
    }

    /// contracts/fixtures/settings/auto-stop-minutes.json 的 backupValues:備份裡的原始 JSON 值
    /// 還原之後存下來的分鐘數(DRIFT D12、D13、D15)。
    @MainActor
    func testAutoStopValuesInABackupRestoreToTheSharedExpectedMinutes() throws {
        let cases: [(json: String, expected: Int)] = [
            ("15", 30), ("15.0", 30), ("14.9", 0), ("45.5", 60), ("2147483648", 120),
            ("4294967326", 120), ("-2147483649", 0), ("1e20", 120), ("true", 0), ("\"30\"", 0), ("null", 0),
        ]
        for testCase in cases {
            let suiteName = "gflyer.auto-stop-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = LocalDataStore(defaults: defaults)
            var playback = PlaybackSettings()
            playback.autoStopMinutes = 60
            store.savePlaybackSettings(playback)

            let json = #"{"format": "GFlyer Backup", "version": 1, "settings": {"autoStopMinutes": \#(testCase.json)}}"#
            let payload = try AppBackupCodec.decode(Data(json.utf8))
            store.applyBackup(payload)

            XCTAssertEqual(store.snapshot.playback.autoStopMinutes, testCase.expected, "json=\(testCase.json)")
        }
    }

    /// contracts/fixtures/gpx/import-names.json(DRIFT D18)
    @MainActor
    func testGpxImportNamesMatchTheSharedFixture() {
        XCTAssertEqual(SimulationController.gpxImportFallbackName, "匯入路線")
        let road80 = String(repeating: "路", count: 80)
        let road85 = String(repeating: "路", count: 85)
        let road78Numbered = String(repeating: "路", count: 78) + " 2"
        let cases: [(name: String, existing: [String], gpxNames: [String?], expected: [String])] = [
            ("names-come-from-the-gpx", [], ["台北一日遊", "需要 & 跳脫的 <名稱>"], ["台北一日遊", "需要 & 跳脫的 <名稱>"]),
            ("missing-names-use-the-fallback", [], [nil, nil, nil], ["匯入路線", "匯入路線 2", "匯入路線 3"]),
            ("never-overwrites-an-existing-route", ["台北一日遊", "匯入路線"], ["台北一日遊", nil], ["台北一日遊 2", "匯入路線 2"]),
            ("same-name-twice-in-one-import", [], ["Loop", "Loop"], ["Loop", "Loop 2"]),
            ("comparison-ignores-case", ["harbour"], ["Harbour", "HARBOUR"], ["Harbour 2", "HARBOUR 3"]),
            ("long-name-is-truncated", [], [road85], [road80]),
            ("long-name-makes-room-for-the-number", [road80], [road85], [road78Numbered]),
        ]
        for testCase in cases {
            let names = SimulationController.importedRouteNames(
                for: testCase.gpxNames,
                existingLowercased: Set(testCase.existing.map { $0.lowercased() })
            )
            XCTAssertEqual(names, testCase.expected, testCase.name)
        }
    }

    func testStartDelayKeepsPreferringTheSmallerOptionOnTie() {
        var settings = PlaybackSettings()
        settings.startDelaySeconds = 4
        XCTAssertEqual(settings.sanitized().startDelaySeconds, 3, "開始延遲不是跨平台設定,維持原本的規則")
    }
}
