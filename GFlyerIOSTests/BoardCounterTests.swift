import XCTest
@testable import GFlyerIOS

/// 留言板輸入框下方的「N/300」(GFlyer-Suite docs/features/message-board-limits.md 第 3 節
/// 「計數器『N/300』」、第 5 節 I16、第 7 節驗收條件),以及分享路線選單每個選項的第二行
/// (docs/features/region-labels.md 第 3 節固定文字表)。
///
/// iOS 的 CI 看不到 Suite,案例照抄規格第 7 節(2026-10-01 抄寫),規格改了這裡要跟著改。
/// emoji 一律寫成 `\u{…}` 跳脫,避免編輯器把它們正規化或合併。
final class BoardCounterTests: XCTestCase {

    private let walker = "\u{1F6B6}"
    private let flag = "\u{1F1F9}\u{1F1FC}"
    private let combining = "e\u{0301}"
    private let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

    // MARK: - 「N/300」

    /// 規格第 7 節的案例:N 是 code point 數,不去前後空白,換行也算 1 個。
    func testBoardCounterLabelCountsCodePoints() {
        XCTAssertEqual(BoardTextLimits.remark, 300, "分享的留言或備註與公告的上限是 fixture 的 post.remark")
        XCTAssertEqual(BoardTextLimits.reply, 300, "回覆的上限是 fixture 的 reply.message")

        let cases: [(name: String, text: String, expected: String)] = [
            ("empty-shows-zero", "", "0/300"),
            ("cjk-is-one", "台", "1/300"),
            ("300-emoji-is-300-not-600-utf16-units", String(repeating: walker, count: 300), "300/300"),
            ("15-flags-are-30-code-points", String(repeating: flag, count: 15), "30/300"),
            ("150-combining-pairs-are-300-not-150-graphemes", String(repeating: combining, count: 150), "300/300"),
            ("zwj-family-is-5-code-points", family, "5/300"),
            ("surrounding-spaces-are-not-trimmed", "  台  ", "5/300"),
            ("newline-is-one-code-point", "a\nb", "3/300"),
        ]
        for testCase in cases {
            XCTAssertEqual(
                BoardTextLimits.counterLabel(testCase.text, limit: BoardTextLimits.remark),
                testCase.expected,
                testCase.name
            )
            XCTAssertEqual(
                BoardTextLimits.counterLabel(testCase.text, limit: BoardTextLimits.reply),
                testCase.expected,
                testCase.name
            )
        }
    }

    /// 數字、半形斜線、上限,中間沒有空白;上限照傳進來的值,不寫死 300。
    func testBoardCounterLabelFormat() {
        XCTAssertEqual(BoardTextLimits.counterLabel("12345678901", limit: BoardTextLimits.remark), "11/300")
        XCTAssertEqual(BoardTextLimits.counterLabel("abc", limit: 80), "3/80")
        XCTAssertFalse(BoardTextLimits.counterLabel("", limit: BoardTextLimits.reply).contains(" "))
    }

    /// 到上限之後再改:輸入框的 `.onChange` 寫回前 300 個 code point(`codePointsCapped(at:)`,
    /// 和 Android 的 `takeCodePoints` 相同),計數器停在「300/300」,不會超過。
    func testBoardCounterStaysAtTheLimitAfterTheFieldIsCapped() {
        let full = String(repeating: walker, count: 300)

        // 在結尾再打字:第 301 個字進不去,內容不變
        let typedAtEnd = (full + "台").codePointsCapped(at: BoardTextLimits.remark)
        XCTAssertEqual(typedAtEnd, full)
        XCTAssertEqual(BoardTextLimits.counterLabel(typedAtEnd ?? "", limit: BoardTextLimits.remark), "300/300")

        // 游標在最前面打「台」:插入的字留下,結尾少一個 🚶,仍是「300/300」
        let typedAtStart = ("台" + full).codePointsCapped(at: BoardTextLimits.reply)
        XCTAssertEqual(typedAtStart, "台" + String(repeating: walker, count: 299))
        XCTAssertEqual(BoardTextLimits.counterLabel(typedAtStart ?? "", limit: BoardTextLimits.reply), "300/300")

        // 沒超過時輸入框不改寫,計數器照實際的數
        XCTAssertNil(full.codePointsCapped(at: BoardTextLimits.remark))
        XCTAssertEqual(BoardTextLimits.counterLabel(full, limit: BoardTextLimits.remark), "300/300")
    }

    // MARK: - 分享路線選單的第二行

    /// region-labels.md 第 3 節:2 點單程 →「2 個座標點」;12 點循環 →「12 個座標點，循環」(全形逗號)。
    func testShareRouteSummaryMatchesAndroid() {
        XCTAssertEqual(BoardShareRouteText.summary(pointCount: 2, loop: false), "2 個座標點")
        XCTAssertEqual(BoardShareRouteText.summary(pointCount: 12, loop: true), "12 個座標點，循環")
        XCTAssertEqual(
            BoardShareRouteText.summary(pointCount: 12, loop: true),
            "12 個座標點\u{FF0C}循環",
            "逗號是全形的 U+FF0C,不是半形的「,」"
        )
        XCTAssertEqual(BoardShareRouteText.summary(pointCount: 12, loop: false), "12 個座標點", "單程不加字")

        let two = [
            GeoCoordinate(latitude: 25.0339, longitude: 121.5645),
            GeoCoordinate(latitude: 25.0349, longitude: 121.5655),
        ]
        XCTAssertEqual(BoardShareRouteText.summary(SavedRoute(name: "臺北", points: two, loop: false)), "2 個座標點")

        let twelve = (0..<12).map { GeoCoordinate(latitude: 25.0339 + Double($0) * 0.001, longitude: 121.5645) }
        let loopRoute = SavedRoute(name: "臺北一日遊", points: twelve, loop: true)
        XCTAssertEqual(BoardShareRouteText.summary(loopRoute), "12 個座標點，循環")
        XCTAssertFalse(BoardShareRouteText.summary(loopRoute).contains(loopRoute.name), "名稱在第一行,第二行不重複")
        XCTAssertNotEqual(BoardShareRouteText.summary(loopRoute), "12 個點 · 循環", "不是收藏路線清單的「N 個點 · 循環」")
    }
}
