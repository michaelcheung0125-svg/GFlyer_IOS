import Combine
import SwiftUI

/// 親友版專屬功能的狀態。見 `EditionModelFeatures`。
@MainActor
final class EditionModel: ObservableObject, EditionModelFeatures {
    let updateChecker = AppUpdateChecker()
    private var updateCheckerChanges: AnyCancellable?

    init() {
        // 主畫面和設定頁觀察的是這個物件。檢查器一變就跟着通知，畫面才會像以前直接觀察檢查器時
        // 一樣重畫，例如「有新版本」關掉之後，主畫面才知道可以顯示升級後的提示。
        let willChange = objectWillChange
        updateCheckerChanges = updateChecker.objectWillChange.sink { _ in willChange.send() }
    }

    var mainScreenAlerts: UpdatePromptAlert { UpdatePromptAlert(updateChecker: updateChecker) }

    var isPresentingAlert: Bool { updateChecker.showsPrompt }

    var settingsAlerts: UpdateErrorAlert { UpdateErrorAlert(updateChecker: updateChecker) }

    var settingsSections: some View {
        SoftwareUpdateSection(updateChecker: updateChecker)
    }

    func appDidBecomeActive() {
        updateChecker.checkIfDue()
    }
}
