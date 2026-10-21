import XCTest
@testable import GFlyerIOS

/// 「開放原始碼授權」頁（docs/APP_STORE_PLAN.md 第 18 項）。清單和 idevice 實際連結的相不相符，由 CI 的
/// 「Open source licences」用 `scripts/open_source_licenses.py` 核對；這裏測 App 讀得到、讀得對。
final class OpenSourceLicensesTests: XCTestCase {
    private let sample = """
        {
          "idevice": {"revision": "abc", "package": "idevice-ffi", "target": "aarch64-apple-ios", "features": ["ring"]},
          "libraries": [
            {"name": "aead", "version": "0.5.2", "license": "MIT OR Apache-2.0",
             "texts": [{"title": "NOTICE", "text": "n1"}, {"title": "LICENSE-MIT", "text": "m1"}]},
            {"name": "Rust 標準程式庫", "version": "", "license": "Apache-2.0 OR MIT",
             "texts": [{"title": "Apache License 2.0", "text": "a1"}]}
          ],
          "texts": {"a1": "Apache", "m1": "MIT", "n1": "Notice"}
        }
        """

    func testParsesTheGeneratedFormat() throws {
        let licenses = try OpenSourceLicenses.parse(Data(sample.utf8))

        XCTAssertEqual(licenses.libraries.map(\.name), ["aead", "Rust 標準程式庫"])
        let aead = licenses.libraries[0]
        XCTAssertEqual(aead.id, "aead 0.5.2")
        XCTAssertEqual(aead.summary, "0.5.2\nMIT OR Apache-2.0")
        XCTAssertEqual(aead.texts.map(\.title), ["NOTICE", "LICENSE-MIT"])
        XCTAssertEqual(aead.texts.map { licenses.fullText($0) }, ["Notice", "MIT"])
        XCTAssertEqual(licenses.libraries[1].summary, "Apache-2.0 OR MIT", "沒有版本就只寫授權")
        XCTAssertNil(licenses.fullText(.init(title: "x", text: "missing")))
    }

    /// App 裏的清單讀得到，每一份全文都在，沒有用不到的全文。
    func testTheBundledListIsComplete() throws {
        let licenses = try OpenSourceLicenses.load()

        XCTAssertGreaterThan(licenses.libraries.count, 50)
        XCTAssertEqual(Set(licenses.libraries.map(\.id)).count, licenses.libraries.count, "同一個程式庫只列一次")
        let sortKeys = licenses.libraries.map { "\($0.name.lowercased()) \($0.version)" }
        XCTAssertEqual(sortKeys, sortKeys.sorted(), "按名稱排好")
        for library in licenses.libraries {
            XCTAssertFalse(library.license.isEmpty, library.id)
            XCTAssertFalse(library.texts.isEmpty, "\(library.id) 沒有全文")
            for reference in library.texts {
                let text = try XCTUnwrap(licenses.fullText(reference), "\(library.id) 的 \(reference.title)")
                XCTAssertFalse(OpenSourceLicenses.paragraphs(text).isEmpty, "\(library.id) 的 \(reference.title) 是空的")
            }
        }
        let used = Set(licenses.libraries.flatMap { $0.texts.map(\.text) })
        XCTAssertEqual(used, Set(licenses.texts.keys))

        let idevice = try XCTUnwrap(licenses.libraries.first { $0.name == "idevice" })
        XCTAssertEqual(idevice.license, "MIT")
        XCTAssertTrue(licenses.libraries.contains { $0.name == "idevice-ffi" })
        let std = try XCTUnwrap(licenses.libraries.first { $0.name == "Rust 標準程式庫" })
        XCTAssertEqual(std.version, "")
    }

    func testParagraphsSplitOnBlankLinesAndKeepLayoutInsideAParagraph() {
        // 和 Android 的 OpenSourceLicensesTest 同一個例子
        let text = "   Apache License\r\n   Version 2.0\r\n\r\n   1. Definitions.\n\n  \n      \"License\" shall mean\n      the terms.\n\n"
        XCTAssertEqual(OpenSourceLicenses.paragraphs(text), [
            "   Apache License\n   Version 2.0",
            "   1. Definitions.",
            "      \"License\" shall mean\n      the terms.",
        ])
    }

    func testEmptyTextHasNoParagraphs() {
        XCTAssertEqual(OpenSourceLicenses.paragraphs("\n \n"), [])
        XCTAssertEqual(OpenSourceLicenses.paragraphs(""), [])
    }

    /// 頁名和入口照 Android（`ui/OpenSourceLicensesPage.kt`、`ui/MainScreen.kt` 的設定「系統」）。
    func testPageNameMatchesAndroid() {
        XCTAssertEqual(OpenSourceLicensesText.title, "開放原始碼授權")
        XCTAssertEqual(OpenSourceLicensesText.librariesSection(count: 140), "程式庫（140）")
        XCTAssertEqual(OpenSourceLicensesText.loadFailed, "讀不到授權清單")
        XCTAssertEqual(OpenSourceLicensesText.textLoadFailed, "讀不到授權全文")
    }
}
