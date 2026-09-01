import Foundation

/// 座標圖鑑的使用者個人資料：星號最愛與「上次前往時間」標記。
/// 只存在本機 `UserDefaults`，不會同步給其他人。
final class CoordinateMarkStore {
    private struct Snapshot: Codable {
        var favorites: [String] = []
        var marks: [String: Double] = [:]
    }

    private let defaults: UserDefaults
    private let key = "gflyer.coordinate-marks.v1"
    private var snapshot: Snapshot

    private(set) var favorites: Set<String>
    private(set) var marks: [String: Date]

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

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
