import Foundation

// 多點路線的到點動作(繞圈 / 向東微動)、停留、手動前進。0.6.9 起行為和 Android 相同
// (GFlyer-Suite docs/features/route-arrival-actions.md,期望值在 contracts/fixtures/route/arrival-actions.json)。
// 這裡是可以直接測試的決定;`SimulationController.startRoute` 照這些決定播放。

/// 路線是怎麼開始的,決定這一趟實際採用哪些播放選項(規格 §3.2)。
enum RouteStartKind: Equatable {
    /// 多點模式按「開始」,或留言板路線先預覽、之後自己按「開始」。
    case multiRoute
    /// 單點模式按「開始」。
    case singleRoute
    /// 留言板路線直接開始。
    case boardRoute
}

/// 一趟路線實際採用的播放選項。按「開始」時從 `PlaybackSettings` 取一份,播放中改設定不影響這一趟;
/// 唯一的例外是繞圈半徑,每次開始繞圈時才讀(`SimulationController.orbitAround`)。
struct RoutePlaybackOptions: Equatable {
    var travelMode: RouteTravelMode
    var pointAction: RoutePointAction
    var manualAdvance: Bool
    var dwellSeconds: Int
    var startDelaySeconds: Int

    /// 和 Android `MainViewModel.startPrimaryMovement` / `startBoardRoute` 相同(fixture 的 arrivalPlan.effective):
    /// - 單點路線、留言板路線直接開始:純模擬移動,沒有到點動作、不停留、不手動前進、不倒數。
    /// - 多點模擬移動:沒有到點動作、不手動前進、不停留;倒數照設定。
    /// - 多點定點傳送:到點動作、手動前進照設定;手動前進時停留 0,否則照設定(夾到 1〜300)。
    /// 存的設定不會因此被改掉:從模擬移動切回定點傳送時,之前選的到點動作與手動前進還在。
    static func effective(for kind: RouteStartKind, settings: PlaybackSettings) -> RoutePlaybackOptions {
        guard kind == .multiRoute else { return plainWalk }
        return multiRoute(
            travelMode: settings.travelMode,
            pointAction: settings.pointAction,
            manualAdvance: settings.manualAdvance,
            dwellSeconds: settings.dwellSeconds,
            startDelaySeconds: settings.startDelaySeconds
        )
    }

    /// 純模擬移動:沒有到點動作、不停留、不手動前進、不倒數。單點路線、留言板路線直接開始用它;
    /// 中斷快照在傳送、探索,或沒有正在播的路線時也寫它的四個值(`ActiveSessionSnapshot.recordedRouteOptions`)。
    static var plainWalk: RoutePlaybackOptions {
        RoutePlaybackOptions(
            travelMode: .simulate,
            pointAction: .none,
            manualAdvance: false,
            dwellSeconds: 0,
            startDelaySeconds: 0
        )
    }

    /// 「多點模式按「開始」」的規則(規格 §3.2;Android `RouteArrival.effectiveOptions(MULTI_ROUTE, …)`)。
    /// `effective(for: .multiRoute, settings:)` 與中斷恢復(`ActiveSessionSnapshot.resumedRouteOptions`,
    /// 規格 §3.10 第 2 步)都呼叫這一份,不另外寫一份規則:
    /// - 模擬移動:純模擬移動,不論另外三個值是什麼;倒數照傳進來的值。
    /// - 定點傳送:到點動作、手動前進照傳進來的值;手動前進時停留 0,否則夾到 1〜300。
    static func multiRoute(
        travelMode: RouteTravelMode,
        pointAction: RoutePointAction,
        manualAdvance: Bool,
        dwellSeconds: Int,
        startDelaySeconds: Int
    ) -> RoutePlaybackOptions {
        switch travelMode {
        case .simulate:
            var options = plainWalk
            options.startDelaySeconds = startDelaySeconds
            return options
        case .teleport:
            return RoutePlaybackOptions(
                travelMode: .teleport,
                pointAction: pointAction,
                manualAdvance: manualAdvance,
                dwellSeconds: manualAdvance ? 0 : PlaybackSettings.clampedDwellSeconds(dwellSeconds),
                startDelaySeconds: startDelaySeconds
            )
        }
    }

    /// 單點路線一律不循環,和 Android 相同(畫面上也不顯示循環選項)。
    static func loops(for kind: RouteStartKind, requested: Bool) -> Bool {
        kind == .singleRoute ? false : requested
    }
}

/// 一段抵達之後依序要做的事:停留 → 到點動作 → 等「下一點」(規格 §3.3)。
struct RouteArrivalSteps: Equatable {
    var dwellSeconds: Int
    var action: RoutePointAction
    var waitsForManualAdvance: Bool
}

extension RouteArrivalSteps {
    /// 停留只在定點傳送時有。不循環路線的最後一段照樣停留與做到點動作,但沒有下一點可等;
    /// 什麼都不用做時(模擬移動)就直接結束。
    init(options: RoutePlaybackOptions, isFinalStop: Bool) {
        self.init(
            dwellSeconds: options.travelMode == .teleport ? options.dwellSeconds : 0,
            action: options.pointAction,
            waitsForManualAdvance: options.manualAdvance && !isFinalStop
        )
    }
}

/// 一圈裡的一段。`from` / `to` 是路線點的位置編號(第幾個點,從 1 起算),同一個座標出現兩次也照位置編號。
struct RouteLeg: Equatable {
    var from: Int
    var to: Int
    /// 模擬移動從 `from` 走到 `to`;定點傳送直接傳送到 `to`,`from` 那一點不會被發送。
    var travelMode: RouteTravelMode
    var steps: RouteArrivalSteps
    /// 不循環路線的最後一段。
    var isFinalStop: Bool
}

enum RouteArrivalPlan {
    /// 一圈的每一段(fixture 的 arrivalPlan.lap),循環時整圈無限重複。段落用 `RoutePlan.traversalPoints`
    /// 排,和播放相同:`walkBack` 循環多一段回到第 1 點;`teleportToStart` 沒有,所以定點傳送時第 1 點
    /// 不會再被造訪(規格 Q5,照 Android)。
    static func lap(
        pointCount: Int,
        loop: Bool,
        transition: LoopTransitionMode,
        options: RoutePlaybackOptions
    ) -> [RouteLeg] {
        let positions = RoutePlan.traversalPoints(
            (0..<max(pointCount, 0)).map { $0 + 1 },
            loop: loop,
            transitionMode: transition
        )
        guard positions.count >= 2 else { return [] }
        return (0..<(positions.count - 1)).map { index in
            let isFinalStop = !loop && index == positions.count - 2
            return RouteLeg(
                from: positions[index],
                to: positions[index + 1],
                travelMode: options.travelMode,
                steps: RouteArrivalSteps(options: options, isFinalStop: isFinalStop),
                isFinalStop: isFinalStop
            )
        }
    }

    /// `SimulationController.startRoute` 播的一圈:`lap` 的每一段配上 `RoutePlan.traversalPoints` 的座標。
    /// 訊息裡的點編號(`leg.to`)、到點步驟與「最後一段」都直接用 `lap` 的結果,播放和 fixture 測的是同一份。
    static func playbackLap(
        points: [GeoCoordinate],
        loop: Bool,
        transition: LoopTransitionMode,
        options: RoutePlaybackOptions
    ) -> [RoutePlaybackLeg] {
        let traversal = RoutePlan.traversalPoints(points, loop: loop, transitionMode: transition)
        let legs = lap(pointCount: points.count, loop: loop, transition: transition, options: options)
        return legs.enumerated().map { index, leg in
            RoutePlaybackLeg(start: traversal[index], end: traversal[index + 1], leg: leg)
        }
    }

    /// 中斷恢復的第一圈:`stops` 是中斷的座標加上快照裡這一圈還沒到的點。那些點是這一圈的尾段,所以第 j 段
    /// 對齊到整圈的倒數同一段,用那一段的編號與步驟。快照比一整圈還長時(舊快照記的循環設定和當時播放的路線
    /// 不一致),多出來的前幾段用第一段的。少於兩個點時是空的。
    static func resumedLap(_ stops: [GeoCoordinate], aligningTo fullLap: [RoutePlaybackLeg]) -> [RoutePlaybackLeg] {
        guard stops.count >= 2, !fullLap.isEmpty else { return [] }
        let offset = fullLap.count - (stops.count - 1)
        return (0..<(stops.count - 1)).map { index in
            RoutePlaybackLeg(start: stops[index], end: stops[index + 1], leg: fullLap[max(offset + index, 0)].leg)
        }
    }
}

/// 播放時的一段:`RouteArrivalPlan.lap` 的一段,加上實際要走(或傳送)的座標。
struct RoutePlaybackLeg: Equatable {
    /// 模擬移動從這裡走起;定點傳送不發送這一點。
    var start: GeoCoordinate
    var end: GeoCoordinate
    var leg: RouteLeg
}

/// 到點微動:從路線點往正東走 20 公尺(大圓 `GeoMath.destination`),之後停在那裡、不走回路線點。
/// 和 Android `MockLocationService.microMoveEast` 相同(fixture 的 microMove)。
enum MicroMovePlanner {
    static let bearingDegrees = 90.0

    static func steps(speedMetresPerSecond: Double, tickSeconds: Double) -> Int {
        let metresPerTick = max(speedMetresPerSecond, 0.1) * tickSeconds
        return max(Int(ceil(PlaybackSettings.microMoveDistanceMetres / metresPerTick)), 1)
    }

    static func waypoints(origin: GeoCoordinate, speedMetresPerSecond: Double, tickSeconds: Double) -> [GeoCoordinate] {
        let count = steps(speedMetresPerSecond: speedMetresPerSecond, tickSeconds: tickSeconds)
        let stepLength = PlaybackSettings.microMoveDistanceMetres / Double(count)
        var current = origin
        var waypoints: [GeoCoordinate] = []
        waypoints.reserveCapacity(count)
        for _ in 0..<count {
            current = GeoMath.destination(from: current, bearingDegrees: bearingDegrees, distanceMetres: stepLength)
            waypoints.append(current)
        }
        return waypoints
    }
}

/// 路線播放的狀態文字,兩個平台一字不差(規格 §3「使用者看得到的文字」)。同一個訊息留到下一個事件,
/// 走路、繞圈、微動的每一步不改寫它。
enum RoutePlaybackMessages {
    static func headingTo(point: Int) -> String { "正在前往第 \(point) 點" }
    static func countdown(seconds: Int) -> String { "\(seconds) 秒後開始路線…" }
    static let countdownSkipped = "已跳過倒數，立即開始路線"
    static func teleported(to point: Int) -> String { "已傳送至第 \(point) 點" }
    static func arrived(at point: Int) -> String { "已到達第 \(point) 點" }
    static func dwelling(point: Int, remainingSeconds: Int) -> String { "第 \(point) 點 · \(remainingSeconds) 秒後開始動作…" }
    static func orbitLap(_ lap: Int, of lapCount: Int, radiusMetres: Int) -> String {
        "正在繞圈 · 第 \(lap)/\(lapCount) 圈 · 半徑 \(radiusMetres) 米"
    }
    static let orbitSkipped = "已跳過繞圈，前往下一點"
    static func orbitFinished(point: Int) -> String { "已完成第 \(point) 點繞圈" }
    static let microMoveStarted = "到點微動中 · 向東 20 米"
    static func microMoveFinished(point: Int) -> String { "已完成第 \(point) 點微動" }
    static func waitingManualAdvance(point: Int) -> String { "已到達第 \(point) 點，按「下一點」繼續" }
    static let advancing = "前往下一點"
    static let nextLap = "開始下一輪循環"
    static let finished = "路線已完成"
    /// 暫停與繼續也是事件,路線與探索共用(Android 的 `TogglePause`)。繼續之後不恢復暫停前的訊息,
    /// 「已繼續移動」留到下一個事件。
    static let paused = "移動已暫停"
    static let resumed = "已繼續移動"
}
