import Combine
import SwiftUI

/// 親友版專屬功能的狀態。見 `EditionModelFeatures`。
@MainActor
final class EditionModel: ObservableObject, EditionModelFeatures {
    let updateChecker = AppUpdateChecker()
    let stepRecorder: StepRecorderController
    /// 從地圖工具列打開的補錄畫面。
    @Published var showsStepRecorderOnMap = false
    /// 從設定頁「補錄步數」打開的補錄畫面，疊在設定頁上面。
    @Published var showsStepRecorderInSettings = false
    private var childChanges: [AnyCancellable] = []

    convenience init() {
        self.init(stepRecorder: StepRecorderController())
    }

    /// 測試用自己的 `UserDefaults` 建立補錄，見 `StepRecorderController.init(defaults:)`。
    init(stepRecorder: StepRecorderController) {
        self.stepRecorder = stepRecorder
        // 主畫面和設定頁觀察的是這個物件。檢查器和補錄一變就跟着通知，畫面才會像以前直接觀察它們時
        // 一樣重畫，例如「有新版本」關掉之後，主畫面才知道可以顯示升級後的提示。
        let willChange = objectWillChange
        childChanges = [
            updateChecker.objectWillChange.sink { _ in willChange.send() },
            stepRecorder.objectWillChange.sink { _ in willChange.send() },
        ]
    }

    func mainScreenPresentations(feedback: MainScreenFeedback) -> some ViewModifier {
        UpdatePromptAlert(updateChecker: updateChecker)
            .concat(StepRecorderMainScreen(edition: self, recorder: stepRecorder, feedback: feedback))
    }

    var isPresentingAlert: Bool { updateChecker.showsPrompt }

    func mapToolItems(feedback: MainScreenFeedback) -> [MapToolItem] {
        [.stepRecord(recorder: stepRecorder, feedback: feedback) { [weak self] in
            self?.showsStepRecorderOnMap = true
        }]
    }

    var settingsPresentations: some ViewModifier {
        UpdateErrorAlert(updateChecker: updateChecker)
            .concat(StepRecorderSettingsSheet(edition: self))
    }

    @ViewBuilder var settingsSections: some View {
        SoftwareUpdateSection(updateChecker: updateChecker)
        StepRecorderSection(recorder: stepRecorder) { [weak self] in
            self?.showsStepRecorderInSettings = true
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        stepRecorder.handleCallback(url)
    }

    func appDidBecomeActive() {
        updateChecker.checkIfDue()
    }
}
