import Combine
import XCTest
@testable import GFlyerIOS

private let scheme = Edition.callbackScheme

/// 親友版的 `EditionModel`：主畫面靠它知道「有新版本」有沒有在顯示，捷徑回呼和地圖工具列的補錄經它進出。
@MainActor
final class EditionModelTests: XCTestCase {
    private func makeEdition() -> (EditionModel, UserDefaults, String) {
        let suite = "gflyer.edition-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (EditionModel(stepRecorder: StepRecorderController(defaults: defaults)), defaults, suite)
    }

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

    func testEditionForwardsStepRecorderChanges() {
        let (edition, defaults, suite) = makeEdition()
        defer { defaults.removePersistentDomain(forName: suite) }
        var changes = 0
        let subscription = edition.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        edition.stepRecorder.quickStepCount = 3_000
        XCTAssertGreaterThan(changes, 0, "地圖工具列的補錄按鈕顯示的步數要跟着變")
    }

    func testStepCallbacksGoToTheStepRecorderAndOtherURLsDoNot() throws {
        let (edition, defaults, suite) = makeEdition()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(edition.handleOpenURL(try XCTUnwrap(URL(string: "\(scheme)://steps/failed"))))
        XCTAssertNotNil(edition.stepRecorder.lastError)
        XCTAssertFalse(
            edition.handleOpenURL(try XCTUnwrap(URL(string: "\(scheme)://airplane/on"))),
            "飛航模式輔助是共用的，要交回 GFlyerIOSApp"
        )
    }

    func testStepRecordButtonOpensTheRecorderUntilTheShortcutIsVerified() throws {
        let (edition, defaults, suite) = makeEdition()
        defer { defaults.removePersistentDomain(forName: suite) }
        var announced: [String] = []
        let feedback = MainScreenFeedback(announce: { announced.append($0) }, reportError: { _ in })

        let items = edition.mapToolItems(feedback: feedback)
        XCTAssertEqual(items.map(\.id), ["step-record"])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.label, "設定補錄步數")

        item.action()
        XCTAssertTrue(edition.showsStepRecorderOnMap)
        XCTAssertFalse(edition.showsStepRecorderInSettings, "設定頁的補錄畫面是另一個")
        XCTAssertEqual(announced, [], "還沒設定好捷徑時不送出")
    }
}
