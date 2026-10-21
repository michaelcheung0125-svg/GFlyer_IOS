import XCTest
@testable import GFlyerIOS

/// 留言板的共用規則（文字上限），只在親友版。期望值照抄 GFlyer-Suite 的 golden fixture ——
/// iOS 的 CI 拿不到那個 repo,所以改 fixture 時這裡要跟著改;Android 的測試直接讀同一份 JSON。
/// 從 `SharedContractTests` 搬出來(docs/APP_STORE_PLAN.md 第 9 項)。
final class MessageBoardContractTests: XCTestCase {

    // MARK: - contracts/fixtures/text/message-board-limits.json

    /// fields[].maxLength 與 clientInputCaps[].maxLength,以 fixture 的 id 為鍵。
    func testBoardTextLimitsMatchTheSharedFixture() {
        let expected: [String: Int] = [
            "auth.inviteCode": 32,
            "auth.adminCode": 4,
            "auth.username": 30,
            "auth.deviceLabel": 80,
            "coordReport.clientRequestId": 80,
            "coordReport.coordinateId": 60,
            "coordReport.coordinateName": 80,
            "coordReport.reason": 40,
            "coordReport.message": 300,
            "post.clientRequestId": 80,
            "post.remark": 300,
            "post.tag": 20,
            "post.coordinate.name": 80,
            "post.route.name": 80,
            "reply.message": 300,
            "invite.code": 32,
            "ui.tagsInput": 120,
            "ui.boardSearch": 80,
        ]
        XCTAssertEqual(BoardTextLimits.maxLengthByFixtureID, expected)
        XCTAssertEqual(BoardTextLimits.inviteCodeMinimum, 4)
        XCTAssertEqual(BoardTextLimits.maxTags, 5)
    }

    /// boundaryCases:去掉前後空白之後的 code point / UTF-16 / 字素數量,和截斷後的結果。
    func testBoardBoundaryCasesCountCodePoints() {
        let walker = "\u{1F6B6}"
        let flag = "\u{1F1F9}\u{1F1FC}"
        let combining = "e\u{0301}"
        let cases: [(name: String, leading: String, text: String, repeatCount: Int, trailing: String,
                     codePoints: Int, utf16Units: Int, graphemes: Int)] = [
            ("username-30-emoji-passes", "", walker, 30, "", 30, 60, 30),
            ("username-31-emoji-fails", "", walker, 31, "", 31, 62, 31),
            ("username-15-flags-is-30-code-points-and-passes", "", flag, 15, "", 30, 60, 15),
            ("username-16-flags-fails-although-only-16-graphemes", "", flag, 16, "", 32, 64, 16),
            ("username-surrounding-spaces-are-trimmed-before-counting", "  ", "名", 30, "  ", 30, 30, 30),
            ("reply-300-emoji-passes", "", walker, 300, "", 300, 600, 300),
            ("reply-301-cjk-fails", "", "字", 301, "", 301, 301, 301),
            ("reply-whitespace-only-is-missing", "", " ", 3, "", 0, 0, 0),
            ("remark-150-combining-pairs-is-300-code-points-and-passes", "", combining, 150, "", 300, 300, 150),
            ("remark-151-combining-pairs-fails-although-only-151-graphemes", "", combining, 151, "", 302, 302, 151),
            ("tag-20-emoji-passes", "", walker, 20, "", 20, 40, 20),
            ("tag-hash-is-counted-before-it-is-stripped", "#", "a", 20, "", 21, 21, 21),
            ("tag-whitespace-only-is-missing", "", " ", 2, "", 0, 0, 0),
            ("coordinate-name-80-emoji-passes", "", walker, 80, "", 80, 160, 80),
            ("coordinate-name-81-emoji-fails", "", walker, 81, "", 81, 162, 81),
            ("route-name-80-emoji-passes", "", walker, 80, "", 80, 160, 80),
            ("invite-code-4-ascii-passes-length", "", "ab-1", 1, "", 4, 4, 4),
            ("invite-code-two-emoji-is-too-short", "", walker, 2, "", 2, 4, 2),
            ("admin-code-fullwidth-digits-fail-pattern", "", "\u{FF11}", 4, "", 4, 4, 4),
            ("report-message-300-emoji-passes", "", walker, 300, "", 300, 600, 300),
            ("report-message-empty-is-allowed", "", "", 0, "", 0, 0, 0),
        ]
        for testCase in cases {
            let input = testCase.leading + String(repeating: testCase.text, count: testCase.repeatCount) + testCase.trailing
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(trimmed.unicodeScalars.count, testCase.codePoints, testCase.name)
            XCTAssertEqual(trimmed.utf16.count, testCase.utf16Units, testCase.name)
            XCTAssertEqual(trimmed.count, testCase.graphemes, testCase.name)
        }

        // 截斷到上限:emoji 不被切成一半,國旗可能被切開(D14 已接受的取捨)
        let username = String(repeating: walker, count: 31).codePointsCapped(at: BoardTextLimits.username)
        XCTAssertEqual(username, String(repeating: walker, count: 30))
        XCTAssertEqual(
            String(repeating: flag, count: 16).codePointsCapped(at: BoardTextLimits.username),
            String(repeating: flag, count: 15)
        )
        let remark = String(repeating: combining, count: 151).codePointsCapped(at: BoardTextLimits.remark)
        XCTAssertEqual(remark?.unicodeScalars.map(\.value), String(repeating: combining, count: 150).unicodeScalars.map(\.value))
        XCTAssertNil(String(repeating: walker, count: 300).codePointsCapped(at: BoardTextLimits.reply), "沒超過時不改寫")
    }
}
