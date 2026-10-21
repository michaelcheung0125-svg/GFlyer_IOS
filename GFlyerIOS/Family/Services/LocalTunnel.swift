import SwiftUI

/// 親友版的本機通道交給 LocalDevVPN（`LocalDevVPNBridge`）。見 `LocalTunnelFeatures`。
typealias LocalTunnel = LocalDevVPNBridge

extension LocalDevVPNBridge: LocalTunnelFeatures {
    func statusWhileConnectingBeforeStart() -> String? {
        needsConnectBeforeStart() ? "正在開啟 LocalDevVPN…" : nil
    }

    func connectBeforeStart() async -> TunnelFailure? {
        if await perform(.connect) { return nil }
        return TunnelFailure(status: "LocalDevVPN 尚未連線", message: Self.connectFailureMessage)
    }

    /// 使用者開了「清除後同時關閉 LocalDevVPN」而且 VPN 目前開著才會動作。
    func disconnectAfterFullClearIfWanted() async -> TunnelClosing? {
        refreshStatus()
        guard disconnectAfterFullClear, isTunnelUp, isInstalled else { return nil }
        let closed = await perform(.disconnect)
        return TunnelClosing(closed: closed, message: closed ? "LocalDevVPN 已關閉。" : Self.disconnectFailureMessage)
    }

    static let stillSimulatedWhileOpenMessage: String? =
        "模擬 session 已關閉，但 iOS 仍回報模擬座標。請關閉 LocalDevVPN，開關一次飛行模式後再確認；必要時重新開機。"

    static let settingsTitle = "LocalDevVPN"

    func settingsRows(controller: SimulationController) -> some View {
        LocalDevVPNSettingsRows(controller: controller, vpn: self)
    }

    static let testButtonTitle = "測試 LocalDevVPN 通道"

    static let deviceIPHint = "目標 IP 預設為 10.7.0.1，須與 LocalDevVPN 設定內的「裝置IP」相同；Remote Pairing port 為 49152。"

    func recoveryRows(isClearing: Bool) -> some View {
        LocalDevVPNRecoveryRows(vpn: self, isClearing: isClearing)
    }

    static let usageSteps = [
        "3. 確認已安裝 LocalDevVPN。",
        "4. 回到地圖選點並按開始；VPN 未開時 GFlyer 會自動切換到 LocalDevVPN 開啟，再自動回來。",
    ]
}
