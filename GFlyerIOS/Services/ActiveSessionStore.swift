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
    /// 這一趟路線實際採用的到點選項(0.6.10 起,GFlyer-Suite docs/features/route-arrival-actions.md §3.10、§5.4)。
    /// 鍵名和 Android 相同,值是 `RouteTravelMode` / `RoutePointAction` 的 rawValue(不可以改,I1)。
    /// `nil` 只表示快照裡沒有這個鍵;0.6.10 寫的快照四個一律不是 `nil`(`recordedRouteOptions`),
    /// 四個都是 `nil` 的是 0.6.9 以前寫的(`resumedRouteOptions`)。
    var routeTravelMode: RouteTravelMode? = nil
    var routePointAction: RoutePointAction? = nil
    var routeManualAdvance: Bool? = nil
    var routeDwellSeconds: Int? = nil
    var savedAt: Date
}

// `init(from:)` 寫在 extension 裡,struct 本體才會保留自動合成的 memberwise init(寫出快照與測試都靠它,
// 而且省略了有預設值的參數)。`encode(to:)` 維持自動合成:0.6.8 必要的鍵一定寫出,降版後照樣讀得到。
extension ActiveSessionSnapshot {
    /// 0.6.8 原有的欄位照 0.6.8 自動合成的規則解碼(一律要求存在);新增的探索欄位各自寬鬆:缺少、型別不對、
    /// 方向認不得,都只讓那一個欄位變成 nil,不能讓整份快照解碼失敗(`load()` 回傳 nil 會連路線快照一起丟掉)。
    /// GFlyer-Suite docs/features/serpentine-exploration.md §4.3。0.6.10 的四個到點選項也各自寬鬆,
    /// 但分得出「鍵不在」(nil)和「值認不得」(那一個欄位的預設值),見下面(route-arrival-actions.md §5.4)。
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
        // 到點選項(route-arrival-actions.md §5.4 第 3 點):鍵不在 → nil(0.6.9 以前寫的);鍵在但值認不得、
        // 型別不對或是 null → 那一個欄位的預設值(§3.10 第 1 步),不讓整份快照解碼失敗。不能只用
        // `try? decodeIfPresent`:認不得的值也會變成 nil,整份快照被當成舊快照。
        // `RoutePointAction.none` 寫全名:屬性是 Optional,只寫 `.none` 會變成 `Optional.none`。
        if container.contains(.routeTravelMode) {
            routeTravelMode =
                (try? container.decode(RouteTravelMode.self, forKey: .routeTravelMode)) ?? RouteTravelMode.simulate
        } else {
            routeTravelMode = nil
        }
        if container.contains(.routePointAction) {
            routePointAction =
                (try? container.decode(RoutePointAction.self, forKey: .routePointAction)) ?? RoutePointAction.none
        } else {
            routePointAction = nil
        }
        if container.contains(.routeManualAdvance) {
            routeManualAdvance = (try? container.decode(Bool.self, forKey: .routeManualAdvance)) ?? false
        } else {
            routeManualAdvance = nil
        }
        if container.contains(.routeDwellSeconds) {
            let saved = (try? container.decode(Int.self, forKey: .routeDwellSeconds)) ?? 0
            routeDwellSeconds = min(max(saved, 0), PlaybackSettings.dwellRange.upperBound)
        } else {
            routeDwellSeconds = nil
        }
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    /// 快照裡至少有一個到點選項的鍵(值認不得也算)。0.6.10 寫的快照一定是 true;false 是 0.6.9 以前寫的。
    var hasSavedRouteOptions: Bool {
        routeTravelMode != nil || routePointAction != nil || routeManualAdvance != nil || routeDwellSeconds != nil
    }

    /// 路線快照恢復時的種類,和 `SimulationController.routeStartKind` 相同:單點路線是單點,其他是多點
    /// (留言板路線直接開始的快照存的模式也是多點)。決定要不要循環,以及舊快照照哪一列算選項。
    var resumedRouteStartKind: RouteStartKind {
        mode == .singleRoute ? .singleRoute : .multiRoute
    }

    /// 路線快照恢復時這一趟用的播放選項(route-arrival-actions.md §3.10、§5.2 I17 第 2 點;對應 Android
    /// `SessionResume.route`)。一律不倒數。
    /// - 至少有一個到點選項的鍵(0.6.10 起寫的):用快照存的值,`nil` 的欄位用預設(模擬移動、無、false、0),
    ///   再套一次多點模式按「開始」的規則(只是擋住壞資料)。**不看 `settings`**:中斷前後改了設定都不影響。
    /// - 四個鍵都沒有(0.6.9 以前寫的):照 0.6.9 恢復時的做法,用恢復當下的設定算(單點路線純模擬移動,
    ///   其他照多點的規則),只是不倒數。0.6.9 播放中的「定點傳送 + 繞圈」路線更新到 0.6.10 後照樣定點傳送並繞圈。
    func resumedRouteOptions(settings: PlaybackSettings) -> RoutePlaybackOptions {
        var options: RoutePlaybackOptions
        if hasSavedRouteOptions {
            options = RoutePlaybackOptions.multiRoute(
                travelMode: routeTravelMode ?? RouteTravelMode.simulate,
                pointAction: routePointAction ?? RoutePointAction.none,
                manualAdvance: routeManualAdvance ?? false,
                dwellSeconds: routeDwellSeconds ?? 0,
                startDelaySeconds: 0
            )
        } else {
            options = RoutePlaybackOptions.effective(for: resumedRouteStartKind, settings: settings)
        }
        options.startDelaySeconds = 0
        return options
    }

    /// 快照要寫的到點選項(route-arrival-actions.md §5.2 I17 第 3 點,和 Android 相同):路線快照寫這一趟
    /// 實際採用的那一份(按「開始」時算的,恢復的那一趟就是恢復的選項,所以連續中斷兩次仍是原本的選項);
    /// 傳送(包括搖桿寫成的傳送快照)、探索,或沒有正在播的路線時寫純模擬移動,恢復時用不到。
    static func recordedRouteOptions(mode: SimulationMode, playing: RoutePlaybackOptions?) -> RoutePlaybackOptions {
        guard mode.isRoute, let playing else { return RoutePlaybackOptions.plainWalk }
        return playing
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
