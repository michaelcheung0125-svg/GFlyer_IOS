import Foundation

struct LocalDataSnapshot: Codable {
    var favorites: [SavedPlace] = []
    var history: [SavedPlace] = []
    var folders: [FavoriteFolder] = []
    var routes: [SavedRoute] = []
    var presets = SpeedScale.defaultPresets
    var draft: RouteDraft?
    var playback = PlaybackSettings()

    /// 備份檔裡不屬於本平台的 settings 鍵,序列化後原樣保存,下次匯出時寫回。
    /// 見 AppBackupCodec 與 GFlyer-Suite 的 docs/DRIFT.md D1。
    var foreignSettings: Data?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case favorites, history, folders, routes, presets, draft, playback, foreignSettings
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
        // 0.6.8 以前還原舊 Android 備份存下的「正常走路」5.04 km/h 在這裡換成 5.0,下一次存檔寫回。
        // 冪等,所以不需要新的資料版本(GFlyer-Suite contracts/fixtures/backup/legacy-walk-preset.json)。
        presets = ((try? container.decode([QuickSpeedPreset].self, forKey: .presets)) ?? SpeedScale.defaultPresets)
            .map { $0.replacingLegacyWalk() }
        draft = (try? container.decodeIfPresent(RouteDraft.self, forKey: .draft)) ?? nil
        playback = (try? container.decode(PlaybackSettings.self, forKey: .playback)) ?? PlaybackSettings()
        foreignSettings = (try? container.decodeIfPresent(Data.self, forKey: .foreignSettings)) ?? nil
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

    /// 同一個座標已經收藏過時取代那一筆(移到最前面)。使用者按「收藏」時,
    /// `SimulationController.addFavorite` 會先擋下重複的座標,和 Android 相同。
    func addFavorite(name: String, coordinate: GeoCoordinate) {
        let place = SavedPlace(name: SavedPlace.normalizedName(name), coordinate: coordinate)
        snapshot.favorites = [place] + Array(snapshot.favorites.filter { $0.coordinate != coordinate }.prefix(99))
        persist()
    }

    func removeFavorite(_ id: UUID) {
        snapshot.favorites.removeAll { $0.id == id }
        persist()
    }

    /// 空白名稱不改,保持原名(和 Android 相同;原本會存成空字串)。
    func renameFavorite(_ id: UUID, name: String) {
        let normalized = SavedPlace.normalizedName(name)
        guard !normalized.isEmpty,
              let index = snapshot.favorites.firstIndex(where: { $0.id == id }) else { return }
        snapshot.favorites[index].name = normalized
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
        // 先截斷再比對同名,和 insertRoute、Android 的 FavoriteFoldersStore.save 相同(DRIFT D14);
        // 否則超過 40 個字、前 40 個字和既有資料夾相同的名稱會建出第二個同名資料夾。
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).prefixCodePoints(40)
        // 已經超過 30 個的舊資料保留,只是不能再新增(和速度預設的做法相同)
        guard snapshot.folders.count < FavoriteFolder.maxCount,
              !normalized.isEmpty,
              !snapshot.folders.contains(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return nil
        }
        let folder = FavoriteFolder(name: normalized)
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
        let normalized = SavedRoute.normalizedName(name)
        guard !normalized.isEmpty else { return }
        // 和 uniqueRouteName 用同一條大小寫規則(lowercased()),否則「Straße」和「STRASSE」這類名稱
        // 在產生名稱時不同名、儲存時又被 caseInsensitiveCompare 當成同名,無聲覆蓋既有路線(DRIFT D18)
        let key = normalized.lowercased()
        let old = snapshot.routes.first(where: { $0.name.lowercased() == key })
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

    func saveDraft(points: [GeoCoordinate], loop: Bool, isMultiPoint: Bool? = nil) {
        snapshot.draft = RouteDraft(points: points, loop: loop, isMultiPoint: isMultiPoint)
        persist()
    }

    func clearDraft() {
        snapshot.draft = nil
        persist()
    }

    func savePresets(_ presets: [QuickSpeedPreset]) {
        // 新增的上限由 SimulationController 把關;這裡保留舊上限,已經超過 6 個的人刪掉一個
        // 只會少一個,不會被一次截到 6 個。
        snapshot.presets = Array(presets.prefix(QuickSpeedPreset.legacyMaxStoredCount))
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
            : Array(payload.presets.prefix(QuickSpeedPreset.maxCount))
        // 兩個平台共通的設定:缺少或型別不對時套預設值,不保留裝置目前的值 ——
        // 還原就是還原,和 Android 相同(GFlyer-Suite docs/DRIFT.md D13)。
        let defaults = PlaybackSettings()
        snapshot.playback.crossDateWarningEnabled = payload.crossDateWarningEnabled ?? defaults.crossDateWarningEnabled
        snapshot.playback.autoStopMinutes = payload.autoStopMinutes ?? defaults.autoStopMinutes
        // 別的平台的設定原樣留著,下次匯出寫回,否則往返一次就會把它們清光。
        snapshot.foreignSettings = payload.foreignSettings
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
