import Combine
import XCTest
@testable import GFlyerIOS

/// 親友版的 `EditionModel`：主畫面靠它知道「有新版本」有沒有在顯示。
@MainActor
final class EditionModelTests: XCTestCase {
    func testEditionReportsTheUpdatePromptAndForwardsCheckerChanges() {
        let edition = EditionModel()
        var changes = 0
        let subscription = edition.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        XCTAssertFalse(edition.isPresentingAlert)
        edition.updateChecker.showsPrompt = true
        XCTAssertTrue(edition.isPresentingAlert)
        XCTAssertGreaterThan(changes, 0, "主畫面觀察的是 EditionModel，檢查器變了要跟着通知")

        edition.updateChecker.dismissPrompt()
        XCTAssertFalse(edition.isPresentingAlert)
    }
}
