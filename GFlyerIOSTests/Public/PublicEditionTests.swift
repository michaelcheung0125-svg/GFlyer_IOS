import XCTest
@testable import GFlyerIOS

/// 公開版 `Edition` 和親友版不同、又不屬於其他測試的值。
final class PublicEditionTests: XCTestCase {
    /// 設定頁「關於」的「私隱政策」連去 JetPiggy 網站的中文頁（docs/privacy-policy.md 開頭寫的網址）。
    func testPrivacyPolicyIsTheChinesePageOnTheGFlyerSite() {
        XCTAssertEqual(Edition.privacyPolicyURL?.absoluteString, "https://gflyer.jetpiggy.com/ios/privacy.html")
    }

    /// 設定頁「操作順序」不再叫人用電腦產生 Pairing File，先叫人做首次設定引導（第 14 項）。
    func testUsageStepsStartWithTheFirstSetupGuide() {
        XCTAssertEqual(Edition.usageSteps.map { $0.prefix(2) }, ["1.", "2."])
        XCTAssertTrue(Edition.usageSteps[0].contains("「首次設定」的「\(FirstSetupText.entryTitle)」"))
        XCTAssertFalse(Edition.usageSteps.joined().contains("電腦"))
    }
}
