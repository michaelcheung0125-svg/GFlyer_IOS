import Combine
import Foundation

enum LibraryTab: Equatable, Hashable {
    case favorites
    case reminders
    case category(String)
}

/// 座標圖鑑回到前景時要不要再檢查線上版（GFlyer-Suite docs/features/coordinate-library-refresh.md 3.2，
/// fixture contracts/fixtures/coordinate-library/refresh-interval.json；Android 的 CoordinateLibraryRefresh）。
/// 時間是單調時鐘的毫秒讀數（含休眠），不受使用者改裝置時間影響。
enum CoordinateLibraryRefreshPolicy {
    /// 線上版每天更新一次；距離上次成功檢查滿 24 小時才再抓。
    static let intervalMilliseconds: Int64 = 24 * 60 * 60 * 1_000

    /// 還沒成功過、已滿 24 小時（剛好 24 小時也算）或時鐘倒退時要再檢查。
    static func isStale(lastSuccessMilliseconds: Int64?, nowMilliseconds: Int64) -> Bool {
        guard let lastSuccessMilliseconds else { return true }
        let elapsed = nowMilliseconds - lastSuccessMilliseconds
        return elapsed < 0 || elapsed >= intervalMilliseconds
    }

    /// Darwin 的 CLOCK_MONOTONIC 在休眠時也會走（CLOCK_UPTIME_RAW 才不會）。
    static func systemMilliseconds() -> Int64 {
        Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000)
    }
}

@MainActor
final class CoordinateLibraryController: ObservableObject {
    @Published private(set) var library: CoordinateLibrary?
    @Published private(set) var isLoading = false
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var marks: [String: Date] = [:]
    @Published private(set) var teleports: [String: LibraryTeleportRecord] = [:]
    @Published private(set) var hideTeleported = false
    @Published var selectedTab: LibraryTab = .favorites
    @Published var selectedSubcategoryID: String?
    @Published var searchText = ""
    @Published var infoMessage: String?
    @Published var errorMessage: String?

    private let repository: CoordinateLibraryRepository
    private let markStore: CoordinateMarkStore
    private let apiClient: MessageBoardAPIClient
    private let monotonicMilliseconds: () -> Int64
    private var hasLoaded = false
    /// 這次啟動最後一次成功下載並解析線上版的單調時鐘讀數（毫秒）；只記在記憶體。
    private var lastSuccessfulCheckMilliseconds: Int64?

    init(
        repository: CoordinateLibraryRepository = CoordinateLibraryRepository(),
        markStore: CoordinateMarkStore = CoordinateMarkStore(),
        apiClient: MessageBoardAPIClient = MessageBoardAPIClient(),
        monotonicMilliseconds: @escaping () -> Int64 = CoordinateLibraryRefreshPolicy.systemMilliseconds
    ) {
        self.repository = repository
        self.markStore = markStore
        self.apiClient = apiClient
        self.monotonicMilliseconds = monotonicMilliseconds
        favorites = markStore.favorites
        marks = markStore.marks
        teleports = markStore.teleports
        hideTeleported = markStore.hideTeleported
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { [weak self] in
            guard let self else { return }
            if let cached = await repository.load() {
                apply(cached)
            }
            await refresh(showErrors: library == nil)
        }
    }

    func refreshManually() {
        Task { [weak self] in
            await self?.refresh(showErrors: true)
        }
    }

    /// App 回到前景時呼叫（MainView 的 scenePhase 變成 active）：距離上次成功檢查線上版滿 24 小時才在背景再抓，
    /// 成功失敗都不顯示訊息（GFlyer-Suite docs/features/coordinate-library-refresh.md）。
    /// 這次啟動還沒打開過圖鑑就不抓，保留「第一次打開圖鑑才下載」（D9）。回傳有沒有開始檢查。
    @discardableResult
    func refreshIfStale() -> Bool {
        guard hasLoaded, !isLoading,
              CoordinateLibraryRefreshPolicy.isStale(
                  lastSuccessMilliseconds: lastSuccessfulCheckMilliseconds,
                  nowMilliseconds: monotonicMilliseconds()
              )
        else { return false }
        Task { [weak self] in
            await self?.refresh(showErrors: false)
        }
        return true
    }

    private func refresh(showErrors: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await repository.refresh()
            // revision 沒有比較新也算成功；失敗不更新，下次回到前景再試
            lastSuccessfulCheckMilliseconds = monotonicMilliseconds()
            apply(refreshed)
        } catch {
            if showErrors {
                errorMessage = library == nil
                    ? "無法下載座標圖鑑資料：\(error.localizedDescription)"
                    : "更新座標圖鑑失敗：\(error.localizedDescription)"
            }
        }
    }

    private func apply(_ newLibrary: CoordinateLibrary) {
        library = newLibrary
        if case .category(let id) = selectedTab, newLibrary.category(id: id) == nil {
            selectedTab = .favorites
        }
        if selectedTab == .favorites, favorites.isEmpty,
           let firstCategory = newLibrary.categories.first {
            selectedTab = .category(firstCategory.id)
        }
    }

    // MARK: - 標記

    func toggleFavorite(_ id: String) {
        markStore.toggleFavorite(id)
        favorites = markStore.favorites
    }

    func markVisited(_ id: String) {
        markStore.markVisited(id)
        marks = markStore.marks
    }

    func clearMark(_ id: String) {
        markStore.clearMark(id)
        marks = markStore.marks
    }

    // MARK: - 前往紀錄

    /// 圖鑑列的「預覽」／「傳送」。回傳 true 表示已交給模擬、可以關閉圖鑑；失敗時訊息放在 `errorMessage`。
    /// 只有「傳送」、座標有效而且模擬接受這次傳送時才記錄前往（「預覽」、座標無效、模擬進行中被拒絕都不記錄）；
    /// 之後跨日警告被取消或連線失敗也不回滾，和 Android App 內圖鑑相同
    /// （GFlyer-Suite docs/features/library-teleport-history.md 3.3）。
    func use(_ coordinate: LibraryCoordinate, startImmediately: Bool, simulation: SimulationController) -> Bool {
        guard let geo = coordinate.geoCoordinate else {
            errorMessage = "這筆座標資料無效"
            return false
        }
        guard simulation.previewExternalCoordinate(geo, startImmediately: startImmediately, sourceLabel: "圖鑑") else {
            errorMessage = simulation.lastError
            simulation.lastError = nil
            return false
        }
        if startImmediately {
            recordTeleport(coordinate.id)
        }
        return true
    }

    func recordTeleport(_ id: String) {
        markStore.recordTeleport(id)
        teleports = markStore.teleports
    }

    func clearTeleport(_ id: String) {
        markStore.clearTeleport(id)
        teleports = markStore.teleports
    }

    func setHideTeleported(_ hide: Bool) {
        markStore.setHideTeleported(hide)
        hideTeleported = markStore.hideTeleported
    }

    func reminderState(for coordinate: LibraryCoordinate, now: Date = Date()) -> VisitReminderState? {
        guard let remindDays = coordinate.remindDays, let markedAt = marks[coordinate.id] else { return nil }
        return VisitReminder.state(markedAt: markedAt, remindDays: remindDays, now: now)
    }

    // MARK: - 篩選

    var tabs: [LibraryTab] {
        var result: [LibraryTab] = [.favorites, .reminders]
        result.append(contentsOf: (library?.categories ?? []).map { .category($0.id) })
        return result
    }

    func title(for tab: LibraryTab) -> String {
        switch tab {
        case .favorites: return "★ 最愛"
        case .reminders: return "⏲ 提醒中"
        case .category(let id):
            guard let category = library?.category(id: id) else { return id }
            return category.icon.isEmpty ? category.name : "\(category.icon) \(category.name)"
        }
    }

    var subcategories: [LibrarySubcategory] {
        guard case .category(let id) = selectedTab else { return [] }
        return library?.category(id: id)?.subcategories ?? []
    }

    /// 「⏲ 提醒中」列的本來就是去過的點，套用的話分頁幾乎永遠是空的：不隱藏，也不顯示開關列。
    /// 開關的值不變，切回其他分頁時照舊生效。
    var hideApplies: Bool { selectedTab != .reminders }

    /// 畫面要列出的座標與「已前往 N / 總數」。計數用隱藏之前的清單算；每次重繪只取一次。
    var listing: LibraryTeleportListing {
        LibraryTeleportHistory.listing(
            matchingCoordinates,
            records: teleports,
            hideTeleported: hideTeleported,
            hideApplies: hideApplies
        )
    }

    /// 分頁、子分類、搜尋與排序之後、「隱藏已前往」之前的清單。
    var matchingCoordinates: [LibraryCoordinate] {
        guard let library else { return [] }
        var coordinates = library.enabledCoordinates
        switch selectedTab {
        case .favorites:
            coordinates = coordinates.filter { favorites.contains($0.id) }
        case .reminders:
            coordinates = coordinates.filter { marks[$0.id] != nil && $0.remindDays != nil }
            coordinates.sort { first, second in
                nextAvailableDate(for: first) < nextAvailableDate(for: second)
            }
        case .category(let id):
            coordinates = coordinates.filter { $0.categoryID == id }
            if let subcategoryID = selectedSubcategoryID {
                coordinates = coordinates.filter { $0.subcategoryID == subcategoryID }
            }
            // 最愛排最前，其餘保持資料順序
            coordinates = coordinates.filter { favorites.contains($0.id) }
                + coordinates.filter { !favorites.contains($0.id) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            coordinates = coordinates.filter {
                $0.name.lowercased().contains(query) || $0.note.lowercased().contains(query)
            }
        }
        return coordinates
    }

    private func nextAvailableDate(for coordinate: LibraryCoordinate) -> Date {
        guard let remindDays = coordinate.remindDays, let markedAt = marks[coordinate.id] else {
            return .distantFuture
        }
        return VisitReminder.nextAvailableAt(markedAt: markedAt, remindDays: remindDays)
    }

    // MARK: - 回報

    /// 失敗一律顯示同一句,不附錯誤描述(伺服器的 429 / 409 原因也不顯示),和 Android 相同。
    func reportOutdated(_ coordinate: LibraryCoordinate, reason: String, message: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await apiClient.reportLibraryCoordinate(
                    coordinateID: coordinate.id,
                    coordinateName: coordinate.name,
                    reason: reason,
                    message: message
                )
                infoMessage = OutdatedReport.successMessage
            } catch {
                errorMessage = OutdatedReport.failureMessage
            }
        }
    }
}
