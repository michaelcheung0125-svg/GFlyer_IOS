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

    func testStartDelayKeepsPreferringTheSmallerOptionOnTie() {
        var settings = PlaybackSettings()
        settings.startDelaySeconds = 4
        XCTAssertEqual(settings.sanitized().startDelaySeconds, 3, "開始延遲不是跨平台設定,維持原本的規則")
    }
}
