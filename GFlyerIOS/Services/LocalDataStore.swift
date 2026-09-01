import Foundation

struct LocalDataSnapshot: Codable {
    var favorites: [SavedPlace] = []
    var history: [SavedPlace] = []
    var folders: [FavoriteFolder] = []
    var routes: [SavedRoute] = []
    var presets = SpeedScale.defaultPresets
    var draft: RouteDraft?
    var playback = PlaybackSettings()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case favorites, history, folders, routes, presets, draft, playback
    }

    // Tolerant decoding: a missing or malformed field falls back to its
    // default instead of failing the whole snapshot, so adding new fields
    // never wipes previously stored favorites/routes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? container.decode([SavedPlace].self, forKey: .favorites)) ?? []
        history = (try? container.decode([SavedPlace].self, forKey: .history)) ?? []
        folders = (try? container.decode([FavoriteFolder].self, forKey: .folders)) ?? []
        routes = (try? container.decode([SavedRoute].self, forKey: .routes)) ?? []
        presets = (try? container.decode([QuickSpeedPreset].self, forKey: .presets)) ?? SpeedScale.defaultPresets
        draft = (try? container.decodeIfPresent(RouteDraft.self, forKey: .draft)) ?? nil
        playback = (try? container.decode(PlaybackSettings.self, forKey: .playback)) ?? PlaybackSettings()
    }
}

final class LocalDataStore {
    private let defaults: UserDefaults
    private let key = "gflyer.local-data.v1"
    private(set) var snapshot: LocalDataSnapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(LocalDataSnapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = LocalDataSnapshot()
            persist()
        }
    }

    func addFavorite(name: String, coordinate: GeoCoordinate) {
        let place = SavedPlace(name: name.trimmingCharacters(in: .whitespacesAndNewlines), coordinate: coordinate)
        snapshot.favorites = [place] + Array(snapshot.favorites.filter { $0.coordinate != coordinate }.prefix(99))
        persist()
    }

    func removeFavorite(_ id: UUID) {
        snapshot.favorites.removeAll { $0.id == id }
        persist()
    }

    func renameFavorite(_ id: UUID, name: String) {
        guard let index = snapshot.favorites.firstIndex(where: { $0.id == id }) else { return }
        snapshot.favorites[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func moveFavorite(_ id: UUID, folderID: UUID?) {
        guard let index = snapshot.favorites.firstIndex(where: { $0.id == id }) else { return }
        snapshot.favorites[index].folderID = folderID
        persist()
    }

    func addHistory(coordinate: GeoCoordinate) {
        let place = SavedPlace(name: coordinate.display, coordinate: coordinate)
        snapshot.history = [place] + Array(snapshot.history.filter { $0.coordinate != coordinate }.prefix(29))
        persist()
    }

    func clearHistory() {
        snapshot.history.removeAll()
        persist()
    }

    @discardableResult
    func createFolder(name: String) -> FavoriteFolder? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !snapshot.folders.contains(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return nil
        }
        let folder = FavoriteFolder(name: String(normalized.prefix(40)))
        snapshot.folders.append(folder)
        persist()
        return folder
    }

    func removeFolder(_ id: UUID) {
        snapshot.folders.removeAll { $0.id == id }
        snapshot.favorites = snapshot.favorites.map { place in
            var copy = place
            if copy.folderID == id { copy.folderID = nil }
            return copy
        }
        snapshot.routes = snapshot.routes.map { route in
            var copy = route
            if copy.folderID == id { copy.folderID = nil }
            return copy
        }
        persist()
    }

    func saveRoute(name: String, points: [GeoCoordinate], loop: Bool) {
        insertRoute(name: name, points: points, loop: loop, clearDraft: true)
        persist()
    }

    /// 批次儲存多條路線（例如 GPX 匯入），整個快照只寫入一次，
    /// 且不清除使用者正在編輯的路線草稿。
    func saveRoutes(_ routes: [(name: String, points: [GeoCoordinate], loop: Bool)]) {
        guard !routes.isEmpty else { return }
        for route in routes {
            insertRoute(name: route.name, points: route.points, loop: route.loop, clearDraft: false)
        }
        persist()
    }

    private func insertRoute(name: String, points: [GeoCoordinate], loop: Bool, clearDraft: Bool) {
        guard points.count >= 2 else { return }
        let normalized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !normalized.isEmpty else { return }
        let old = snapshot.routes.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame })
        let route = SavedRoute(id: old?.id ?? UUID(), name: normalized, points: points, loop: loop, folderID: old?.folderID)
        snapshot.routes = [route] + Array(snapshot.routes.filter { $0.id != route.id }.prefix(49))
        if clearDraft { snapshot.draft = nil }
    }

    func removeRoute(_ id: UUID) {
        snapshot.routes.removeAll { $0.id == id }
        persist()
    }

    func moveRoute(_ id: UUID, folderID: UUID?) {
        guard let index = snapshot.routes.firstIndex(where: { $0.id == id }) else { return }
        snapshot.routes[index].folderID = folderID
        persist()
    }

    func saveDraft(points: [GeoCoordinate], loop: Bool) {
        snapshot.draft = RouteDraft(points: points, loop: loop)
        persist()
    }

    func clearDraft() {
        snapshot.draft = nil
        persist()
    }

    func savePresets(_ presets: [QuickSpeedPreset]) {
        snapshot.presets = Array(presets.prefix(12))
        persist()
    }

    func savePlaybackSettings(_ settings: PlaybackSettings) {
        snapshot.playback = settings.sanitized()
        persist()
    }

    @discardableResult
    func applyBackup(_ payload: BackupPayload) -> BackupImportResult {
        snapshot.folders = Array(payload.folders.prefix(30))
        let folderIDs = Set(snapshot.folders.map(\.id))
        snapshot.favorites = Array(payload.favorites.prefix(100)).map { place in
            var copy = place
            if let folderID = copy.folderID, !folderIDs.contains(folderID) { copy.folderID = nil }
            return copy
        }
        snapshot.history = Array(payload.history.prefix(30))
        snapshot.routes = Array(payload.routes.prefix(50)).map { route in
            var copy = route
            if let folderID = copy.folderID, !folderIDs.contains(folderID) { copy.folderID = nil }
            return copy
        }
        snapshot.presets = payload.presets.isEmpty
            ? SpeedScale.defaultPresets
            : Array(payload.presets.prefix(12))
        if let crossDate = payload.crossDateWarningEnabled {
            snapshot.playback.crossDateWarningEnabled = crossDate
        }
        if let autoStop = payload.autoStopMinutes {
            snapshot.playback.autoStopMinutes = autoStop
        }
        snapshot.playback = snapshot.playback.sanitized()
        persist()
        return BackupImportResult(
            favoriteCount: snapshot.favorites.count,
            routeCount: snapshot.routes.count,
            folderCount: snapshot.folders.count,
            presetCount: snapshot.presets.count
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
