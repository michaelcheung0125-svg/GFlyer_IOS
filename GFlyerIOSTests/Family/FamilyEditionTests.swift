import XCTest
@testable import GFlyerIOS

/// 親友版 `Edition` 和公開版不同、又不屬於其他測試的值。
final class FamilyEditionTests: XCTestCase {
    /// 親友版照舊：第一次掛載時自己下載 DDI，不用先到設定頁按下載。
    func testTheDeveloperDiskImageStillDownloadsByItself() {
        XCTAssertNil(Edition.developerDiskImageMissingMessage)
    }

    /// 私隱政策只寫公開版，親友版的設定頁沒有「私隱政策」。
    func testHasNoPrivacyPolicy() {
        XCTAssertNil(Edition.privacyPolicyURL)
    }

    /// 設定頁「操作順序」改由 `Edition` 給（公開版第 14 項），親友版的四步一字不改。
    func testUsageStepsAreUnchanged() {
        XCTAssertEqual(Edition.usageSteps, [
            "1. 用電腦產生這部 iPhone 的 pairing file。",
            "2. 將檔案傳到 iPhone 並在此匯入。",
            "3. 確認已安裝 LocalDevVPN。",
            "4. 回到地圖選點並按開始；VPN 未開時 GFlyer 會自動切換到 LocalDevVPN 開啟，再自動回來。",
        ])
    }
}
