import Foundation

enum SimulationMode: String, CaseIterable, Identifiable {
    case teleport = "傳送"
    case route = "路線"

    var id: Self { self }
}

enum LoopTransitionMode: String, CaseIterable, Identifiable {
    case walkBack = "走回起點"
    case teleportToStart = "直接返回"

    var id: Self { self }
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

struct SimulationStatus: Equatable {
    var isActive = false
    var isPaused = false
    var coordinate: GeoCoordinate?
    var message = "預覽後端已就緒"
}

enum SimulationError: LocalizedError {
    case pairingFileRequired
    case backendUnavailable(String)
    case invalidAddress
    case connectionFailed(String)
    case developerDiskImage(String)
    case routeNeedsTwoPoints

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
        }
    }
}
