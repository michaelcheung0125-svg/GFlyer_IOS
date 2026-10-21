import Combine

/// `DeveloperDiskImageDownload` 用到的 `DeveloperDiskImageStore` 功能，測試換成假的。
protocol DeveloperDiskImageDownloading: Sendable {
    func isDownloaded() async -> Bool
    func download() async throws
}

extension DeveloperDiskImageStore: DeveloperDiskImageDownloading {}

/// 公開版設定頁下載 DDI 的狀態（docs/APP_STORE_PLAN.md 第 15 項）。公開版不會自己下載 DDI：
/// 使用者在設定頁看過大小、按了下載才下載（`EditionFeatures.developerDiskImageMissingMessage`）。
/// 離開設定頁下載也繼續，回來時要看到「下載中…」，所以只有一個。
@MainActor
final class DeveloperDiskImageDownload: ObservableObject {
    enum State: Equatable {
        case checking
        case missing
        case downloading
        case downloaded
    }

    static let shared = DeveloperDiskImageDownload()

    @Published private(set) var state = State.checking

    private let store: DeveloperDiskImageDownloading

    init(store: DeveloperDiskImageDownloading = DeveloperDiskImageStore.shared) {
        self.store = store
    }

    /// 重新查本機有沒有三個驗證得過的檔案。
    func refresh() async {
        guard state != .downloading else { return }
        let downloaded = await store.isDownloaded()
        // 查的時候使用者可能按了下載
        guard state != .downloading else { return }
        state = downloaded ? .downloaded : .missing
    }

    /// 下載成功或已經在下載時回傳 nil；失敗回傳要顯示的錯誤。
    func download() async -> String? {
        guard state != .downloading else { return nil }
        state = .downloading
        do {
            try await store.download()
            state = .downloaded
            return nil
        } catch {
            state = .missing
            return "DDI 下載失敗：\(error.localizedDescription)"
        }
    }
}
