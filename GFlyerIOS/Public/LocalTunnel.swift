import SwiftUI

/// 公開版自己的本機通道要到 docs/APP_STORE_PLAN.md 第 12 項（App 內建的通道）才有。在那之前
/// 不代使用者開關通道：按開始時直接開始，沒有通道時由連線錯誤提示接手。見 `LocalTunnelFeatures`。
@MainActor
final class LocalTunnel: ObservableObject, LocalTunnelFeatures {
    var deviceIP = "10.7.0.1"

    func refreshStatus() {}

    func statusWhileConnectingBeforeStart() -> String? { nil }

    func connectBeforeStart() async -> TunnelFailure? { nil }

    func disconnectAfterFullClearIfWanted() async -> TunnelClosing? { nil }

    static let stillSimulatedWhileOpenMessage: String? = nil

    static let settingsTitle = "本機通道"

    func settingsRows(controller: SimulationController) -> EmptyView { EmptyView() }

    static let testButtonTitle = "測試本機通道"

    static let deviceIPHint = "目標 IP 預設為 10.7.0.1；Remote Pairing port 為 49152。"

    func recoveryRows(isClearing: Bool) -> some View {
        Text("想讓其他 App 回到真實位置時使用：清除模擬、關閉模擬 session，並驗證目前回報的定位。iOS 可能要取得新的真實定位後才會更新；若驗證顯示仍是模擬座標，開關一次飛行模式通常可解決。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    static let usageSteps = ["3. 回到地圖選點並按開始。"]
}
