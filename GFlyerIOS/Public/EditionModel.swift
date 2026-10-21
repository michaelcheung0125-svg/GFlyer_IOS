import SwiftUI

/// 公開版沒有版本專屬的功能：掛鈎全部什麼都不做。見 `EditionModelFeatures`。
@MainActor
final class EditionModel: ObservableObject, EditionModelFeatures {
    func mainScreenPresentations(feedback: MainScreenFeedback) -> EmptyModifier { EmptyModifier() }

    var isPresentingAlert: Bool { false }

    func mapToolItems(feedback: MainScreenFeedback) -> [MapToolItem] { [] }

    var settingsPresentations: EmptyModifier { EmptyModifier() }

    var settingsSections: EmptyView { EmptyView() }

    func handleOpenURL(_ url: URL) -> Bool { false }

    func appDidBecomeActive() {}
}
