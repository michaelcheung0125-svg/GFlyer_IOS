import SwiftUI

/// 設定頁「LocalDevVPN」section 裏開關 VPN 的幾列，接在「目標 IP」前面。
struct LocalDevVPNSettingsRows: View {
    @ObservedObject var controller: SimulationController
    @ObservedObject var vpn: LocalDevVPNBridge

    var body: some View {
        LabeledContent("VPN 狀態", value: statusLabel)
        switchButton
        Toggle("按開始時自動開啟", isOn: $vpn.autoConnectOnStart)
        Text("VPN 未開時按開始，GFlyer 會切換到 LocalDevVPN 開啟 VPN，約 1 秒後自動回來繼續。模擬進行中不能關閉 VPN，請先按停止。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var statusLabel: String {
        if vpn.isSwitching { return "等待 LocalDevVPN…" }
        if vpn.isTunnelUp { return "已連線" }
        return vpn.isInstalled ? "未連線" : "未安裝 LocalDevVPN"
    }

    private var switchButton: some View {
        Button {
            controller.switchLocalDevVPN(on: !vpn.isTunnelUp)
        } label: {
            if vpn.isTunnelUp {
                Label("關閉 LocalDevVPN", systemImage: "bolt.horizontal.circle")
            } else {
                Label("開啟 LocalDevVPN", systemImage: "bolt.horizontal.circle.fill")
            }
        }
        .disabled(vpn.isSwitching || (vpn.isTunnelUp && controller.isMotionActive))
    }
}

/// 設定頁「恢復」裏「完整清除模擬定位」下面的幾列。
struct LocalDevVPNRecoveryRows: View {
    @ObservedObject var vpn: LocalDevVPNBridge
    let isClearing: Bool

    var body: some View {
        Toggle("清除後同時關閉 LocalDevVPN", isOn: $vpn.disconnectAfterFullClear)
            .disabled(isClearing)
        Text("想讓其他 App 回到真實位置時使用：清除模擬、關閉模擬 session，並驗證目前回報的定位。iOS 可能要取得新的真實定位後才會更新；若驗證顯示仍是模擬座標，關閉 LocalDevVPN 並開關一次飛行模式通常可解決。")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("開啟上面的選項後，清除成功才會切換到 LocalDevVPN 關閉 VPN，再自動回來；清除失敗時會保留 VPN，方便重試。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
