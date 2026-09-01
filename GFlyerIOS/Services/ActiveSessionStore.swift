import Foundation

/// 執行中的模擬快照，讓 App 被系統終止或強制關閉後可以提示恢復。
/// 對應 GFlyer Android 的 ActiveSessionStore：移動時定期寫入、到點時寫入，
/// 超過有效期的快照視同不存在。
struct ActiveSessionSnapshot: Codable, Equatable {
    var mode: SimulationMode
    var coordinate: GeoCoordinate
    var routePoints: [GeoCoordinate] = []
    /// 目前這一圈還沒走完的路線點（含正要前往的點）；恢復時從中斷位置接回。
    var remainingPoints: [GeoCoordinate] = []
    var loop = false
    var transition: LoopTransitionMode = .walkBack
    var speedKilometresPerHour: Double
    var spiralCenter: GeoCoordinate? = nil
    var spiralAngleRadians: Double? = nil
    var savedAt: Date
}

final class ActiveSessionStore {
    static let expiryInterval: TimeInterval = 600

    private let defaults: UserDefaults
    private let key = "gflyer.active-session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: ActiveSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func load(now: Date = Date()) -> ActiveSessionSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ActiveSessionSnapshot.self, from: data) else {
            return nil
        }
        guard now.timeIntervalSince(snapshot.savedAt) <= Self.expiryInterval, snapshot.savedAt <= now else {
            clear()
            return nil
        }
        return snapshot
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
