import XCTest
@testable import GFlyerIOS

/// 親友版 `Edition` 和公開版不同、又不屬於其他測試的值。
final class FamilyEditionTests: XCTestCase {
    /// 親友版照舊：第一次掛載時自己下載 DDI，不用先到設定頁按下載。
    func testTheDeveloperDiskImageStillDownloadsByItself() {
        XCTAssertNil(Edition.developerDiskImageMissingMessage)
    }
}
