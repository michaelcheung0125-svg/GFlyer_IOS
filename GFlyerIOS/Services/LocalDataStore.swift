import Foundation

struct LocalDataSnapshot: Codable {
    var favorites: [SavedPlace] = []
    var history: [SavedPlace] = []
    var folders: [FavoriteFolder] = []
    var routes: [SavedRoute] = []
    var presets = SpeedScale.defaultPresets
    var draft: RouteDraft?
}

@MainActor
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
        guard points.count >= 2 else { return }
        let normalized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !normalized.isEmpty else { return }
        let old = snapshot.routes.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame })
        let route = SavedRoute(id: old?.id ?? UUID(), name: normalized, points: points, loop: loop, folderID: old?.folderID)
        snapshot.routes = [route] + Array(snapshot.routes.filter { $0.id != route.id }.prefix(49))
        snapshot.draft = nil
        persist()
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
