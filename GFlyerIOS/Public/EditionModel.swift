import SwiftUI

/// 公開版沒有版本專屬的功能：掛鈎全部什麼都不做。見 `EditionModelFeatures`。
@MainActor
final class EditionModel: ObservableObject, EditionModelFeatures {
    var mainScreenAlerts: EmptyModifier { EmptyModifier() }

    var isPresentingAlert: Bool { false }

    var settingsAlerts: EmptyModifier { EmptyModifier() }

    var settingsSections: EmptyView { EmptyView() }

    func appDidBecomeActive() {}
}
