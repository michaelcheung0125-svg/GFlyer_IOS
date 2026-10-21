extension SimulationController {
    /// 設定頁的手動開關。模擬進行中不准關：之後的清除指令要靠這條通道送出。
    func switchLocalTunnel(on: Bool) {
        lastError = nil
        guard on || !status.isActive else {
            lastError = "請先按停止結束模擬，再關閉本機通道。"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if let failure = await vpn.perform(connect: on) {
                lastError = failure
            }
        }
    }
}
