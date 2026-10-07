import Foundation

/// 座標圖鑑的使用者個人資料：星號最愛、「上次前往時間」標記，以及在圖鑑按「傳送」的前往紀錄與
/// 「隱藏已前往」開關。只存在本機 `UserDefaults`，不會同步給其他人，也不在備份裡。
final class CoordinateMarkStore {
    private struct Snapshot: Codable {
        var favorites: [String] = []
        var marks: [String: Double] = [:]
    }

    private let defaults: UserDefaults
    private let key = "gflyer.coordinate-marks.v1"
    // 前往紀錄與開關用自己的鍵，不放進 Snapshot：0.6.8 存的 Snapshot 沒有新欄位，自動合成的解碼會
    // 整份失敗、清掉最愛與造訪標記；分開存也讓前往紀錄壞掉時只影響它自己，降版再升回來也還在
    // (GFlyer-Suite docs/features/library-teleport-history.md 第 4 節)。
    private let teleportsKey = "gflyer.coordinate-teleports.v1"
    private let hideTeleportedKey = "gflyer.coordinate-hide-teleported.v1"
    /// 還沒看過的新座標 id，同樣用自己的鍵（GFlyer-Suite docs/features/coordinate-library-new-badge.md 3.4）。
    private let newCoordinatesKey = "gflyer.coordinate-new-ids.v1"
    private var snapshot: Snapshot

    private(set) var favorites: Set<String>
    private(set) var marks: [String: Date]
    private(set) var teleports: [String: LibraryTeleportRecord]
    /// 沒存過時 `bool(forKey:)` 回 false，正好是預設值。
    private(set) var hideTeleported: Bool
    /// 地圖工具列「座標圖鑑」旁的「NEW」：不是空的就顯示，打開圖鑑就清空。
    private(set) var newCoordinateIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = Snapshot()
        }
        favorites = Set(snapshot.favorites)
        marks = snapshot.marks.mapValues { Date(timeIntervalSince1970: $0) }
        teleports = LibraryTeleportHistory.decode(defaults.data(forKey: teleportsKey))
        hideTeleported = defaults.bool(forKey: hideTeleportedKey)
        newCoordinateIDs = Set(defaults.stringArray(forKey: newCoordinatesKey) ?? [])
    }

    /// 回傳切換後是否為最愛。
    @discardableResult
    func toggleFavorite(_ id: String) -> Bool {
        let isFavorite: Bool
        if favorites.contains(id) {
            favorites.remove(id)
            isFavorite = false
        } else {
            favorites.insert(id)
            isFavorite = true
        }
        snapshot.favorites = Array(favorites)
        persist()
        return isFavorite
    }

    /// 標記上次前往時間；取整到小時，因為提醒只需要準確到小時。
    @discardableResult
    func markVisited(_ id: String, now: Date = Date()) -> Date {
        let seconds = now.timeIntervalSince1970
        let hourPrecision = Date(timeIntervalSince1970: seconds - seconds.truncatingRemainder(dividingBy: 3_600))
        marks[id] = hourPrecision
        snapshot.marks[id] = hourPrecision.timeIntervalSince1970
        persist()
        return hourPrecision
    }

    func clearMark(_ id: String) {
        marks.removeValue(forKey: id)
        snapshot.marks.removeValue(forKey: id)
        persist()
    }

    /// 在圖鑑按「傳送」：記下這次的時間（毫秒，不取整）並把次數加 1，立刻寫回。
    func recordTeleport(_ id: String, now: Date = Date()) {
        teleports = LibraryTeleportHistory.record(teleports, id: id, nowEpochMs: LibraryTeleportHistory.epochMs(now))
        persistTeleports()
    }

    /// 清除後再傳送，次數從 1 開始；沒有紀錄時不做事。
    func clearTeleport(_ id: String) {
        guard teleports.removeValue(forKey: id) != nil else { return }
        persistTeleports()
    }

    func setHideTeleported(_ hide: Bool) {
        hideTeleported = hide
        defaults.set(hide, forKey: hideTeleportedKey)
    }

    func setNewCoordinateIDs(_ ids: Set<String>) {
        newCoordinateIDs = ids
        defaults.set(ids.sorted(), forKey: newCoordinatesKey)
    }

    private func persistTeleports() {
        defaults.set(LibraryTeleportHistory.encode(teleports), forKey: teleportsKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
