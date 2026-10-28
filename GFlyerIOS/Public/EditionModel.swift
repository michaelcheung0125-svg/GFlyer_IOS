import Combine
import SwiftUI

/// 公開版專屬功能的狀態：只有首次設定的引導（docs/APP_STORE_PLAN.md 第 14 項），其他掛鈎什麼都不做。
/// 見 `EditionModelFeatures`。
@MainActor
final class EditionModel: ObservableObject, EditionModelFeatures {
    let firstSetup: FirstSetupGuide
    private var childChanges: [AnyCancellable] = []

    convenience init() {
        self.init(firstSetup: FirstSetupGuide())
    }

    /// 測試用自己的 `UserDefaults` 建立引導。
    init(firstSetup: FirstSetupGuide) {
        self.firstSetup = firstSetup
        // 主畫面看 `isPresentingAlert` 決定其他提示要不要等，引導關掉時要跟着通知
        let willChange = objectWillChange
        childChanges = [firstSetup.objectWillChange.sink { _ in willChange.send() }]
    }

    func mainScreenPresentations(simulation: SimulationController, feedback: MainScreenFeedback) -> some ViewModifier {
        FirstSetupMainScreen(guide: firstSetup, simulation: simulation)
    }

    var navigationBarButtons: EmptyView { EmptyView() }

    var isPresentingAlert: Bool { firstSetup.isPresentedOnMainScreen }

    func mapToolItems(feedback: MainScreenFeedback) -> [MapToolItem] { [] }

    func settingsPresentations(simulation: SimulationController) -> some ViewModifier {
        FirstSetupSettingsSheet(guide: firstSetup, simulation: simulation)
    }

    var firstSetupRows: some View { FirstSetupEntryRow(guide: firstSetup) }

    var settingsSections: EmptyView { EmptyView() }

    func handleOpenURL(_ url: URL) -> Bool { false }

    func appDidBecomeActive() {}
}
