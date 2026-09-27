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
    /// 探索這一輪的起點、進度與設定(0.6.9 起;0.6.8 存的是螺旋的 `spiralCenter` / `spiralAngleRadians`,
    /// 讀的時候忽略)。`coordinate` 與 `explorationState` 是同一個 tick 的結果。
    var explorationCenter: GeoCoordinate? = nil
    var explorationState: SerpentineState? = nil
    var explorationVerticalLengthMetres: Double? = nil
    var explorationDirection: ExplorationDirection? = nil
    var savedAt: Date
}

// `init(from:)` 寫在 extension 裡,struct 本體才會保留自動合成的 memberwise init(寫出快照與測試都靠它,
// 而且省略了有預設值的參數)。`encode(to:)` 維持自動合成:0.6.8 必要的鍵一定寫出,降版後照樣讀得到。
extension ActiveSessionSnapshot {
    /// 0.6.8 原有的欄位照 0.6.8 自動合成的規則解碼(一律要求存在);新增的探索欄位各自寬鬆:缺少、型別不對、
    /// 方向認不得,都只讓那一個欄位變成 nil,不能讓整份快照解碼失敗(`load()` 回傳 nil 會連路線快照一起丟掉)。
    /// GFlyer-Suite docs/features/serpentine-exploration.md §4.3。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(SimulationMode.self, forKey: .mode)
        coordinate = try container.decode(GeoCoordinate.self, forKey: .coordinate)
        routePoints = try container.decode([GeoCoordinate].self, forKey: .routePoints)
        remainingPoints = try container.decode([GeoCoordinate].self, forKey: .remainingPoints)
        loop = try container.decode(Bool.self, forKey: .loop)
        transition = try container.decode(LoopTransitionMode.self, forKey: .transition)
        speedKilometresPerHour = try container.decode(Double.self, forKey: .speedKilometresPerHour)
        explorationCenter = try? container.decodeIfPresent(GeoCoordinate.self, forKey: .explorationCenter)
        explorationState = try? container.decodeIfPresent(SerpentineState.self, forKey: .explorationState)
        explorationVerticalLengthMetres =
            try? container.decodeIfPresent(Double.self, forKey: .explorationVerticalLengthMetres)
        explorationDirection = try? container.decodeIfPresent(ExplorationDirection.self, forKey: .explorationDirection)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    /// 探索快照接回的那一輪(規格 §4.2):從中斷的 `coordinate` 以快照的進度接著走,**不跳回這一輪的起點**。
    /// 缺的欄位照 Android 的規則補:進度 (0, 0)、Y 1000(非有限或 ≤ 0 也是)再夾到 200〜5000、方向 EAST、
    /// 起點用 `coordinate`。所以 0.6.8 的螺旋快照會變成從 `coordinate` 開始的一輪新蛇形(§4.3 第 5 點)。
    var resumedExploration: ExplorationRun {
        let length: Double
        if let saved = explorationVerticalLengthMetres, saved.isFinite, saved > 0 {
            length = saved
        } else {
            length = Double(SerpentinePath.defaultVerticalLengthMetres)
        }
        return ExplorationRun(
            center: explorationCenter ?? coordinate,
            current: coordinate,
            state: explorationState?.sanitized() ?? SerpentineState(),
            verticalLengthMetres: min(
                max(length, Double(SerpentinePath.minVerticalLengthMetres)),
                Double(SerpentinePath.maxVerticalLengthMetres)
            ),
            direction: explorationDirection ?? .east
        )
    }
}

final class ActiveSessionStore {
    static let expiryInterval: TimeInterval = 600

    private let defaults: UserDefaults
    // 不要升版:換鍵會讓升級當下正在跑的路線 / 傳送快照一起消失
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
