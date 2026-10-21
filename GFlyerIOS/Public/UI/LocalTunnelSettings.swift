import SwiftUI

/// 設定頁「本機通道」section 裏開關通道的幾列，接在「目標 IP」前面。
struct LocalTunnelSettingsRows: View {
    @ObservedObject var controller: SimulationController
    @ObservedObject var tunnel: LocalTunnel

    var body: some View {
        LabeledContent("通道狀態", value: statusLabel)
        switchButton
        Text("本機通道是 GFlyer 內建的 VPN，只把送往目標 IP 的連線導回這部 iPhone，其他網絡流量不經過它。按開始時通道未開，GFlyer 會自動開啟。模擬進行中不能關閉通道，請先按停止。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var statusLabel: String {
        switch tunnel.switching {
        case .some(true): return "正在開啟…"
        case .some(false): return "正在關閉…"
        case .none: return tunnel.isTunnelUp ? "已連線" : "未連線"
        }
    }

    private var switchButton: some View {
        Button {
            controller.switchLocalTunnel(on: !tunnel.isTunnelUp)
        } label: {
            if tunnel.isTunnelUp {
                Label("關閉本機通道", systemImage: "bolt.horizontal.circle")
            } else {
                Label("開啟本機通道", systemImage: "bolt.horizontal.circle.fill")
            }
        }
        .disabled(tunnel.switching != nil || (tunnel.isTunnelUp && controller.isMotionActive))
    }
}

/// 設定頁「恢復」裏「完整清除模擬定位」下面的幾列。
struct LocalTunnelRecoveryRows: View {
    @ObservedObject var tunnel: LocalTunnel
    let isClearing: Bool

    var body: some View {
        Toggle("清除後同時關閉本機通道", isOn: $tunnel.disconnectAfterFullClear)
            .disabled(isClearing)
        Text("想讓其他 App 回到真實位置時使用：清除模擬、關閉模擬 session，並驗證目前回報的定位。iOS 可能要取得新的真實定位後才會更新；若驗證顯示仍是模擬座標，關閉本機通道並開關一次飛行模式通常可解決。")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("開啟上面的選項後，清除成功才會關閉本機通道；清除失敗時會保留通道，方便重試。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
