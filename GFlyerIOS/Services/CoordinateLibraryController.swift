import Combine
import Foundation

enum LibraryTab: Equatable, Hashable {
    case favorites
    case reminders
    case category(String)
}

@MainActor
final class CoordinateLibraryController: ObservableObject {
    @Published private(set) var library: CoordinateLibrary?
    @Published private(set) var isLoading = false
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var marks: [String: Date] = [:]
    @Published var selectedTab: LibraryTab = .favorites
    @Published var selectedSubcategoryID: String?
    @Published var searchText = ""
    @Published var infoMessage: String?
    @Published var errorMessage: String?

    private let repository: CoordinateLibraryRepository
    private let markStore: CoordinateMarkStore
    private let apiClient: MessageBoardAPIClient
    private var hasLoaded = false

    init(
        repository: CoordinateLibraryRepository = CoordinateLibraryRepository(),
        markStore: CoordinateMarkStore = CoordinateMarkStore(),
        apiClient: MessageBoardAPIClient = MessageBoardAPIClient()
    ) {
        self.repository = repository
        self.markStore = markStore
        self.apiClient = apiClient
        favorites = markStore.favorites
        marks = markStore.marks
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

    private func refresh(showErrors: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await repository.refresh()
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

    var visibleCoordinates: [LibraryCoordinate] {
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
                infoMessage = "已送出回報，謝謝你！"
            } catch {
                errorMessage = "回報送出失敗：\(error.localizedDescription)"
            }
        }
    }
}
