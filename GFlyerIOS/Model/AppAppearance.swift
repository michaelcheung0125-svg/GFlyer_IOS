import SwiftUI

/// App 自己的深淺色偏好。
///
/// 系統設定是全機的，但這個 App 常常在戶外、在地圖上用，使用者想單獨把它固定
/// 成深色或淺色而不動到其他 App。預設是跟隨系統，也就是加這個設定之前的行為。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟隨系統"
        case .light: return "淺色"
        case .dark: return "深色"
        }
    }

    /// 交給 `preferredColorScheme`。`nil` 是「不要覆寫，讓系統決定」的意思，
    /// 不是「沒有設定」——所以 `.system` 一定要對應 `nil`。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "gflyer.appearance"

    /// 讀不出來就當作跟隨系統。舊版沒有寫過這個鍵，升上來時會走這條路；
    /// 值被改壞時也一樣，不要讓 App 因為一個設定值而顯示異常。
    static func stored(_ rawValue: String?) -> AppAppearance {
        guard let rawValue, let parsed = AppAppearance(rawValue: rawValue) else { return .system }
        return parsed
    }
}
