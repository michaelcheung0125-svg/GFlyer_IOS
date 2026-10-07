import XCTest
@testable import GFlyerIOS

/// 收藏位置與定位歷史清單每一列的第三行(GFlyer-Suite docs/features/region-labels.md §3.8,2026-10-08 的決定 B):
/// 時間後面接「  ·  」+「國家 · 城市」,不知道地區時只有時間。前三個測試照抄 Android `SavedPlaceRowTextTest` 的值。
/// 清單上第三行最多兩行、超出從結尾以 … 截斷(`.lineLimit(2)`)是畫面的事,要上機看。
final class SavedPlaceRowTextTests: XCTestCase {

    func testFavoriteTimeLineWithRegionLabel() {
        XCTAssertEqual(
            SavedPlaceRowText.timeLine(prefix: "收藏於", formattedTime: "2026年10月8日 下午1:40", regionLabel: "台灣 · 臺北市"),
            "收藏於 2026年10月8日 下午1:40  ·  台灣 · 臺北市"
        )
    }

    func testHistoryTimeLineWithoutRegionLabelHasOnlyTheTime() {
        XCTAssertEqual(
            SavedPlaceRowText.timeLine(prefix: "定位於", formattedTime: "2026年10月8日 下午1:40", regionLabel: nil),
            "定位於 2026年10月8日 下午1:40"
        )
    }

    func testBlankRegionLabelIsTreatedAsUnknown() {
        XCTAssertEqual(SavedPlaceRowText.timeLine(prefix: "收藏於", formattedTime: "昨天", regionLabel: " "), "收藏於 昨天")
    }

    /// 空字串與各種只有空白的標籤(和 Kotlin `isBlank()` 相同,含全形空白 U+3000 與不換行空白 U+00A0)都連同分隔一起省略。
    func testEmptyAndWhitespaceOnlyLabelsAreOmittedWithTheSeparator() {
        for label in ["", "  ", "\t", "\n", "\u{3000}", "\u{00A0}", " \t\u{3000}\n"] {
            XCTAssertEqual(
                SavedPlaceRowText.timeLine(prefix: "定位於", formattedTime: "2026年10月8日 下午1:40", regionLabel: label),
                "定位於 2026年10月8日 下午1:40",
                "label: \(label.unicodeScalars.map { String($0.value, radix: 16) })"
            )
        }
    }

    /// 不是空白的標籤原樣接上,不修剪(Android 是 `takeIf { it.isNotBlank() }`,也不修剪)。
    func testNonBlankLabelIsKeptAsIs() {
        XCTAssertEqual(
            SavedPlaceRowText.timeLine(prefix: "收藏於", formattedTime: "昨天", regionLabel: "新加坡"),
            "收藏於 昨天  ·  新加坡"
        )
        XCTAssertEqual(
            SavedPlaceRowText.timeLine(prefix: "收藏於", formattedTime: "昨天", regionLabel: " 日本 "),
            "收藏於 昨天  ·   日本 "
        )
    }

    /// 時間後面是兩個空白 + U+00B7 + 兩個空白;標籤內部與收藏路線列用的是一個空白的「 · 」。
    func testSeparatorIsTwoSpacesMiddleDotTwoSpaces() {
        XCTAssertEqual(SavedPlaceRowText.separator.unicodeScalars.map(\.value), [0x20, 0x20, 0xB7, 0x20, 0x20])
        XCTAssertNotEqual(SavedPlaceRowText.separator, RegionLabel.separator)
        XCTAssertEqual(RegionLabel.separator.unicodeScalars.map(\.value), [0x20, 0xB7, 0x20])
    }

    /// 清單實際用的 `LibraryRowText.saved(_:at:label:)`:系統語言與時區的中等日期 + 短時間,再交給 `timeLine`。
    func testLibraryRowTextUsesTheTimeLineWithTheMediumDateAndShortTime() {
        let date = Date(timeIntervalSince1970: 1_790_401_200)
        let dateTime = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        XCTAssertEqual(
            LibraryRowText.saved(LibraryRowText.favoriteSavedPrefix, at: date, label: "臺灣 · 臺北市"),
            "收藏於 " + dateTime + "  ·  臺灣 · 臺北市"
        )
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.historySavedPrefix, at: date, label: nil), "定位於 " + dateTime)
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.historySavedPrefix, at: date, label: " "), "定位於 " + dateTime)
        // 收藏路線的第三行不變,只有時間
        XCTAssertEqual(LibraryRowText.saved(LibraryRowText.routeSavedPrefix, at: date), "儲存於 " + dateTime)
    }
}
