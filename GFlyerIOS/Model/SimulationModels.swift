import Foundation

enum SimulationMode: String, CaseIterable, Identifiable, Codable {
    case teleport = "傳送"
    case singleRoute = "單點"
    case multiRoute = "多點"
    case explore = "探索"

    var id: Self { self }

    var isRoute: Bool {
        self == .singleRoute || self == .multiRoute
    }
}

enum LoopTransitionMode: String, CaseIterable, Identifiable, Codable {
    case walkBack = "走回起點"
    case teleportToStart = "直接返回"

    var id: Self { self }
}

enum RouteTravelMode: String, CaseIterable, Identifiable, Codable {
    case simulate = "模擬移動"
    case teleport = "逐點傳送"

    var id: Self { self }
}

enum RoutePointAction: String, CaseIterable, Identifiable, Codable {
    case none = "無"
    case orbit = "繞圈"
    case microMove = "微動"

    var id: Self { self }
}

struct PlaybackSettings: Codable, Equatable {
    static let dwellRange = 0...300
    static let orbitRadiusRange = 5...500
    static let maxOrbitLaps = 4
    static let defaultOrbitRadiiMetres = [20, 30]
    static let startDelayOptions = [0, 3, 5, 10]
    static let autoStopOptions = [0, 30, 60, 120]
    static let microMoveDistanceMetres = 20.0
    static let joystickMaxSpeedOptions = [20, 60, 150, 500, 900]
    static let joystickMaxSpeedRange = 5...900

    var travelMode: RouteTravelMode = .simulate
    var pointAction: RoutePointAction = .none
    var manualAdvance = false
    var dwellSeconds = 10
    var orbitRadiiMetres = defaultOrbitRadiiMetres
    var startDelaySeconds = 0
    var autoStopMinutes = 0
    var crossDateWarningEnabled = true
    var joystickMaxSpeedKilometresPerHour = 500

    init() {}

    private enum CodingKeys: String, CodingKey {
        case travelMode, pointAction, manualAdvance, dwellSeconds
        case orbitRadiiMetres, startDelaySeconds, autoStopMinutes, crossDateWarningEnabled
        case joystickMaxSpeedKilometresPerHour
    }

    // 缺欄位或型別不符時退回屬性宣告上的預設值（單一定義處）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = PlaybackSettings()
        settings.travelMode = (try? container.decode(RouteTravelMode.self, forKey: .travelMode)) ?? settings.travelMode
        settings.pointAction = (try? container.decode(RoutePointAction.self, forKey: .pointAction)) ?? settings.pointAction
        settings.manualAdvance = (try? container.decode(Bool.self, forKey: .manualAdvance)) ?? settings.manualAdvance
        settings.dwellSeconds = (try? container.decode(Int.self, forKey: .dwellSeconds)) ?? settings.dwellSeconds
        settings.orbitRadiiMetres = (try? container.decode([Int].self, forKey: .orbitRadiiMetres)) ?? settings.orbitRadiiMetres
        settings.startDelaySeconds = (try? container.decode(Int.self, forKey: .startDelaySeconds)) ?? settings.startDelaySeconds
        settings.autoStopMinutes = (try? container.decode(Int.self, forKey: .autoStopMinutes)) ?? settings.autoStopMinutes
        settings.crossDateWarningEnabled =
            (try? container.decode(Bool.self, forKey: .crossDateWarningEnabled)) ?? settings.crossDateWarningEnabled
        settings.joystickMaxSpeedKilometresPerHour =
            (try? container.decode(Int.self, forKey: .joystickMaxSpeedKilometresPerHour))
            ?? settings.joystickMaxSpeedKilometresPerHour
        self = settings.sanitized()
    }

    func sanitized() -> PlaybackSettings {
        var copy = self
        copy.dwellSeconds = min(max(dwellSeconds, Self.dwellRange.lowerBound), Self.dwellRange.upperBound)
        copy.orbitRadiiMetres = orbitRadiiMetres
            .prefix(Self.maxOrbitLaps)
            .map { min(max($0, Self.orbitRadiusRange.lowerBound), Self.orbitRadiusRange.upperBound) }
        if copy.orbitRadiiMetres.isEmpty { copy.orbitRadiiMetres = Self.defaultOrbitRadiiMetres }
        // 非選項值（例如 Android 備份帶來的 15 分鐘）取最接近的選項而不是直接停用
        copy.startDelaySeconds = Self.nearestOption(to: startDelaySeconds, in: Self.startDelayOptions)
        copy.autoStopMinutes = Self.nearestOption(to: autoStopMinutes, in: Self.autoStopOptions)
        copy.joystickMaxSpeedKilometresPerHour = min(
            max(joystickMaxSpeedKilometresPerHour, Self.joystickMaxSpeedRange.lowerBound),
            Self.joystickMaxSpeedRange.upperBound
        )
        return copy
    }

    private static func nearestOption(to value: Int, in options: [Int]) -> Int {
        options.min(by: { abs($0 - value) < abs($1 - value) }) ?? 0
    }
}

enum OrbitPlanner {
    static func stepRadians(speedMetresPerSecond: Double, radiusMetres: Double, tickSeconds: Double) -> Double {
        max(speedMetresPerSecond, 0.1) / max(radiusMetres, 1) * tickSeconds
    }

    static func stepsPerLap(stepRadians: Double) -> Int {
        max(Int(ceil(2 * Double.pi / max(stepRadians, 1e-9))), 8)
    }

    static func stepsPerLap(speedMetresPerSecond: Double, radiusMetres: Double, tickSeconds: Double) -> Int {
        stepsPerLap(
            stepRadians: stepRadians(
                speedMetresPerSecond: speedMetresPerSecond,
                radiusMetres: radiusMetres,
                tickSeconds: tickSeconds
            )
        )
    }
}

struct QuickSpeedPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var kilometresPerHour: Double

    init(id: UUID = UUID(), name: String, kilometresPerHour: Double) {
        self.id = id
        self.name = name
        self.kilometresPerHour = SpeedScale.clamped(kilometresPerHour)
    }
}

struct SavedPlace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let coordinate: GeoCoordinate
    let createdAt: Date
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: GeoCoordinate,
        createdAt: Date = .now,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.createdAt = createdAt
        self.folderID = folderID
    }
}

struct FavoriteFolder: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct SavedRoute: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let points: [GeoCoordinate]
    var loop: Bool
    let createdAt: Date
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        points: [GeoCoordinate],
        loop: Bool,
        createdAt: Date = .now,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.loop = loop
        self.createdAt = createdAt
        self.folderID = folderID
    }
}

struct RouteDraft: Codable, Equatable {
    var points: [GeoCoordinate]
    var loop: Bool
}

struct SimulationStatus: Equatable {
    var isActive = false
    var isPaused = false
    var coordinate: GeoCoordinate?
    var mode: SimulationMode?
    var message = "預覽後端已就緒"
    var countdownRemaining: Int?
    var waitingManualAdvance = false
    var isOrbiting = false
    var autoStopAt: Date?
}

struct PlaceSearchResult: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: GeoCoordinate
}

enum SimulationError: LocalizedError {
    case pairingFileRequired
    case backendUnavailable(String)
    case invalidAddress
    case connectionFailed(String)
    case developerDiskImage(String)
    case routeNeedsTwoPoints
    case exploreAlreadyActive

    var errorDescription: String? {
        switch self {
        case .pairingFileRequired:
            return "尚未匯入這部 iPhone 的 pairing file。"
        case let .backendUnavailable(message):
            return message
        case .invalidAddress:
            return "LocalDevVPN 目標 IP 無效。"
        case let .connectionFailed(message):
            return message
        case let .developerDiskImage(message):
            return message
        case .routeNeedsTwoPoints:
            return "路線至少需要兩個座標。"
        case .exploreAlreadyActive:
            return "探索已經在執行中。"
        }
    }
}

enum RoutePlan {
    static func traversalPoints(
        _ points: [GeoCoordinate],
        loop: Bool,
        transitionMode: LoopTransitionMode = .walkBack
    ) -> [GeoCoordinate] {
        if loop, points.count >= 2, transitionMode == .walkBack {
            return points + [points[0]]
        }
        return points
    }
}

enum SpeedScale {
    static let minimumKilometresPerHour = 1.8
    static let walkKilometresPerHour = 5.0
    static let runKilometresPerHour = 10.8
    static let bicycleKilometresPerHour = 19.0
    static let carKilometresPerHour = 50.0
    static let airplaneKilometresPerHour = 900.0
    static let maximumKilometresPerHour = airplaneKilometresPerHour
    static let flowerLimitKilometresPerHour = 20.0

    static let defaultPresets = [
        QuickSpeedPreset(name: "正常走路", kilometresPerHour: walkKilometresPerHour),
        QuickSpeedPreset(name: "跑步", kilometresPerHour: runKilometresPerHour),
        QuickSpeedPreset(name: "腳踏車", kilometresPerHour: bicycleKilometresPerHour),
        QuickSpeedPreset(name: "汽車", kilometresPerHour: carKilometresPerHour),
        QuickSpeedPreset(name: "飛機", kilometresPerHour: airplaneKilometresPerHour),
    ]

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimumKilometresPerHour), maximumKilometresPerHour)
    }

    static func toSliderPosition(_ speed: Double) -> Double {
        let value = clamped(speed)
        let carPosition = 2.0 / 3.0
        if value <= carKilometresPerHour {
            return ((value - minimumKilometresPerHour) / (carKilometresPerHour - minimumKilometresPerHour)) * carPosition
        }
        return carPosition + ((value - carKilometresPerHour) / (airplaneKilometresPerHour - carKilometresPerHour)) * (1 - carPosition)
    }

    static func fromSliderPosition(_ position: Double) -> Double {
        let normalized = min(max(position, 0), 1)
        let carPosition = 2.0 / 3.0
        if normalized <= carPosition {
            return minimumKilometresPerHour
                + (normalized / carPosition) * (carKilometresPerHour - minimumKilometresPerHour)
        }
        return carKilometresPerHour + ((normalized - carPosition) / (1 - carPosition)) * (airplaneKilometresPerHour - carKilometresPerHour)
    }

    static func exceedsFlowerLimit(_ speed: Double) -> Bool {
        speed > flowerLimitKilometresPerHour
    }
}

struct SpiralState: Equatable {
    var angleRadians = 0.0
}

struct SpiralStep {
    let state: SpiralState
    let coordinate: GeoCoordinate
}

enum SpiralPath {
    static let ringSpacingMetres = 1_000.0
    private static let radiusPerRadian = ringSpacingMetres / (2.0 * Double.pi)

    static func advance(
        center: GeoCoordinate,
        current: GeoCoordinate,
        state: SpiralState,
        distanceMetres: Double
    ) -> SpiralStep {
        let distance = max(distanceMetres, 0)
        let arcLengthPerRadian = radiusPerRadian * sqrt(1 + state.angleRadians * state.angleRadians)
        let nextAngle = state.angleRadians + distance / arcLengthPerRadian
        let radius = radiusPerRadian * nextAngle
        let next = GeoMath.destination(
            from: center,
            bearingDegrees: nextAngle.radiansToDegrees,
            distanceMetres: radius
        )
        _ = current
        return SpiralStep(state: SpiralState(angleRadians: nextAngle), coordinate: next)
    }

    static func preview(
        center: GeoCoordinate,
        current: GeoCoordinate,
        state: SpiralState,
        distanceMetres: Double = 5_000,
        segmentLengthMetres: Double = 40
    ) -> [GeoCoordinate] {
        guard distanceMetres > 0 else { return [current] }
        var points = [current]
        var nextState = state
        var nextCoordinate = current
        var remaining = distanceMetres
        while remaining > 0 {
            let step = advance(
                center: center,
                current: nextCoordinate,
                state: nextState,
                distanceMetres: min(segmentLengthMetres, remaining)
            )
            nextState = step.state
            nextCoordinate = step.coordinate
            points.append(nextCoordinate)
            remaining -= segmentLengthMetres
        }
        return points
    }
}

enum CooldownEstimator {
    static func estimateSeconds(distanceMetres: Double) -> Int {
        switch distanceMetres {
        case ..<1_000: return 30
        case ..<5_000: return 120
        case ..<10_000: return 300
        case ..<25_000: return 600
        case ..<100_000: return 1_800
        case ..<250_000: return 2_700
        case ..<500_000: return 3_600
        case ..<1_000_000: return 5_400
        default: return 7_200
        }
    }
}

private extension Double {
    var radiansToDegrees: Double { self * 180 / .pi }
}
