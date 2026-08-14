import Foundation

enum SimulationMode: String, CaseIterable, Identifiable {
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

struct SavedRoute: Codable, Equatable, Identifiable {
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
