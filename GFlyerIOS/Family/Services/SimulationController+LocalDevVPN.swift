extension SimulationController {
    /// 設定頁的手動開關。模擬進行中不准關：之後的清除指令要靠這條通道送出。
    func switchLocalDevVPN(on: Bool) {
        lastError = nil
        guard on || !status.isActive else {
            lastError = "請先按停止結束模擬，再關閉 LocalDevVPN。"
            return
        }
        guard vpn.isInstalled else {
            lastError = "找不到 LocalDevVPN，請先從 App Store 安裝。"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let reached = await vpn.perform(on ? .connect : .disconnect)
            if !reached {
                lastError = on
                    ? LocalDevVPNBridge.connectFailureMessage
                    : LocalDevVPNBridge.disconnectFailureMessage
            }
        }
    }
}
