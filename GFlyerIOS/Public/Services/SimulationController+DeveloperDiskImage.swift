extension SimulationController {
    /// 設定頁的「下載 DDI」按鈕。下載不碰裝置，模擬進行中也可以按。
    func downloadDeveloperDiskImage(_ download: DeveloperDiskImageDownload) {
        lastError = nil
        Task { [weak self] in
            guard let failure = await download.download() else { return }
            self?.lastError = failure
        }
    }
}
