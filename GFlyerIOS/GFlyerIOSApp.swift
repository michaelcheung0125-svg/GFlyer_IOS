import SwiftUI

@main
struct GFlyerIOSApp: App {
    @StateObject private var controller = SimulationController()
    /// 版本專屬功能（親友版的留言板、座標圖鑑、檢查新版、補錄步數等），見 `EditionModelFeatures`
    @StateObject private var edition = EditionModel()
    @StateObject private var airplaneAssist = AirplaneAssistController()
    /// 深淺色偏好。設在這一層而不是 MainView 上，sheet 才會跟著一起換——
    /// sheet 是另一個呈現層，套在 MainView 上時設定頁自己不會變色。
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            MainView(
                controller: controller,
                edition: edition,
                airplaneAssist: airplaneAssist
            )
            // 捷徑回呼先交給版本專屬的功能（親友版的補錄：steps/... 把補錄標成已寫入），
            // 再交給飛航模式輔助：airplane/... 回報飛行模式有沒有切換成功。scheme 是
            // Edition.callbackScheme。LocalDevVPN 開關 VPN 後打開的是沒有路徑的 scheme://，
            // 刻意不處理：結果由 LocalDevVPNBridge 在回到前景時查路由確認
            .onOpenURL { url in
                guard !edition.handleOpenURL(url) else { return }
                airplaneAssist.handleCallback(url)
            }
            .preferredColorScheme(AppAppearance.stored(appearanceRawValue).colorScheme)
        }
    }
}
