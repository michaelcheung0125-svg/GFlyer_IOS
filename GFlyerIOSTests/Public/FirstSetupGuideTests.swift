import Combine
import XCTest
@testable import GFlyerIOS

/// 公開版的首次設定引導（docs/APP_STORE_PLAN.md 第 14 項）：步驟的次序、記住到哪一步、什麼時候自己打開，
/// 以及說明裏引用的 GFlyer 按鈕和結論和畫面上的相同。
@MainActor
final class FirstSetupGuideTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "gflyer.first-setup-tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testStepsFollowThePlanOrder() {
        XCTAssertEqual(FirstSetupStep.allCases.map(\.number), Array(1...7))
        XCTAssertEqual(
            FirstSetupStep.allCases.map { FirstSetupText.title($0, pairsOnDevice: true) },
            ["顯示開發者模式", "開啟開發者模式並重新開機", "在這支 iPhone 上配對", "開啟本機通道", "下載 DDI", "傳送一次並確認", "清除並恢復真實位置"]
        )
        XCTAssertEqual(FirstSetupText.title(.pair, pairsOnDevice: false), "匯入 Pairing File", "iOS 26 以下改成匯入電腦產生的配對檔")
        XCTAssertEqual(FirstSetupText.progress(.tunnel), "第 4 步，共 7 步")
    }

    func testForwardAndBackStopAtTheEndsAndAreRemembered() {
        let defaults = makeDefaults()
        let guide = FirstSetupGuide(defaults: defaults)
        XCTAssertEqual(guide.step, .showDeveloperMode)
        guide.goBack()
        XCTAssertEqual(guide.step, .showDeveloperMode)
        for _ in 0..<10 { guide.goForward() }
        XCTAssertEqual(guide.step, .restore)
        guide.goBack()
        XCTAssertEqual(FirstSetupGuide(defaults: defaults).step, .teleport)
    }

    /// 第 2 步要重新開機，GFlyer 會被關掉；再打開時引導要自己出現，停在同一步。
    func testReopensAtTheSameStepAfterTheRestart() {
        let defaults = makeDefaults()
        let guide = FirstSetupGuide(defaults: defaults)
        guide.presentOnLaunchIfNeeded(canControlDevice: true)
        XCTAssertTrue(guide.isPresentedOnMainScreen)
        guide.goForward()

        let relaunched = FirstSetupGuide(defaults: defaults)
        relaunched.presentOnLaunchIfNeeded(canControlDevice: true)
        XCTAssertTrue(relaunched.isPresentedOnMainScreen)
        XCTAssertEqual(relaunched.step, .enableDeveloperMode)
    }

    func testClosingStopsItOpeningByItselfButSettingsStillOpensIt() {
        let defaults = makeDefaults()
        let guide = FirstSetupGuide(defaults: defaults)
        guide.presentOnLaunchIfNeeded(canControlDevice: true)
        guide.goForward()
        guide.close()
        XCTAssertFalse(guide.isPresented)

        let relaunched = FirstSetupGuide(defaults: defaults)
        relaunched.presentOnLaunchIfNeeded(canControlDevice: true)
        XCTAssertFalse(relaunched.isPresented)
        relaunched.presentFromSettings()
        XCTAssertTrue(relaunched.isPresentedInSettings)
        XCTAssertFalse(relaunched.isPresentedOnMainScreen)
        XCTAssertEqual(relaunched.step, .enableDeveloperMode, "關掉時停在哪一步，從設定頁打開就接着做")
    }

    func testPreviewModeDoesNotOpenItByItself() {
        let guide = FirstSetupGuide(defaults: makeDefaults())
        guide.presentOnLaunchIfNeeded(canControlDevice: false)
        XCTAssertFalse(guide.isPresented)
    }

    func testFinishingStartsOverNextTime() {
        let defaults = makeDefaults()
        let guide = FirstSetupGuide(defaults: defaults)
        guide.presentFromSettings()
        for _ in FirstSetupStep.allCases { guide.goForward() }
        guide.finish()
        XCTAssertFalse(guide.isPresented)
        XCTAssertEqual(guide.step, .showDeveloperMode)

        let relaunched = FirstSetupGuide(defaults: defaults)
        relaunched.presentOnLaunchIfNeeded(canControlDevice: true)
        XCTAssertFalse(relaunched.isPresented)
        XCTAssertEqual(relaunched.step, .showDeveloperMode)
    }

    /// 配對、通道和 DDI 查得到結果，做完才可以按「下一步」；其餘由使用者自己看。
    func testNextWaitsOnlyForTheStepsTheAppCanCheck() {
        let checked: Set<FirstSetupStep> = [.pair, .tunnel, .developerDiskImage]
        let nothingDone = FirstSetupReadiness(hasPairingFile: false, isTunnelUp: false, hasDeveloperDiskImage: false)
        let allDone = FirstSetupReadiness(hasPairingFile: true, isTunnelUp: true, hasDeveloperDiskImage: true)
        for step in FirstSetupStep.allCases {
            XCTAssertEqual(nothingDone.canGoForward(from: step), !checked.contains(step), "\(step)")
            XCTAssertTrue(allDone.canGoForward(from: step), "\(step)")
            XCTAssertEqual(FirstSetupText.waitingNote(step) != nil, checked.contains(step), "\(step)")
        }
        XCTAssertFalse(FirstSetupReadiness(hasPairingFile: true, isTunnelUp: false, hasDeveloperDiskImage: true).canGoForward(from: .tunnel))
    }

    /// 說明裏引號中的 GFlyer 按鈕、狀態和結論，用的是畫面上的同一個字。
    func testInstructionsQuoteTheLabelsOnScreen() {
        func text(_ step: FirstSetupStep, pairsOnDevice: Bool = true) -> String {
            FirstSetupText.instructions(step, pairsOnDevice: pairsOnDevice).joined(separator: "\n")
        }
        for step in FirstSetupStep.allCases {
            XCTAssertFalse(text(step).isEmpty, "\(step)")
            XCTAssertFalse(text(step, pairsOnDevice: false).isEmpty, "\(step)")
        }
        XCTAssertTrue(text(.showDeveloperMode).contains("「\(FirstSetupText.showDeveloperModeButton)」"))
        XCTAssertTrue(text(.showDeveloperMode).contains("「設定」>「私隱與保安」，在「保安」一組找「開發者模式」"))
        XCTAssertTrue(text(.showDeveloperMode).contains("\(OnDevicePairingController.timeoutSeconds / 60) 分鐘"))
        XCTAssertTrue(text(.enableDeveloperMode).contains("「設定」>「私隱與保安」>「開發者模式」"))
        XCTAssertTrue(text(.pair, pairsOnDevice: false).contains("「匯入 Pairing File」"))
        XCTAssertTrue(text(.tunnel).contains("「開啟本機通道」"))
        XCTAssertTrue(text(.developerDiskImage).contains("「\(Edition.developerDiskImageDownloadTitle)」"))
        XCTAssertTrue(text(.teleport).contains("「\(LocationCheckText.title)」"))
        XCTAssertTrue(text(.teleport).contains("「\(LocationCheckText.teleportButton)」"))
        XCTAssertTrue(text(.teleport).contains("「\(LocationCheckVerdict.matches.text)」"))
        XCTAssertTrue(text(.teleport).contains("「\(LocationCheckText.grantPermissionButton)」"))
        XCTAssertTrue(text(.restore).contains("「\(LocationCheckVerdict.realLocation.text)」"))
        XCTAssertTrue(text(.restore).contains("「完整清除模擬定位」"))
        XCTAssertTrue(FirstSetupText.reopenNote.contains("「首次設定」按「\(FirstSetupText.entryTitle)」"))
    }

    func testEditionModelHoldsOtherMainScreenPromptsWhileTheGuideIsOpen() {
        let guide = FirstSetupGuide(defaults: makeDefaults())
        let edition = EditionModel(firstSetup: guide)
        var changes = 0
        let subscription = edition.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        XCTAssertFalse(edition.isPresentingAlert)
        guide.presentOnLaunchIfNeeded(canControlDevice: true)
        XCTAssertTrue(edition.isPresentingAlert)
        XCTAssertGreaterThan(changes, 0, "主畫面觀察的是 EditionModel，引導開關時要跟着通知")
        guide.close()
        XCTAssertFalse(edition.isPresentingAlert)
        guide.presentFromSettings()
        XCTAssertFalse(edition.isPresentingAlert, "疊在設定頁上時，主畫面的提示本來就被設定頁擋着")
    }
}
