import Combine
import Foundation

@MainActor
final class SimulationController: ObservableObject {
    @Published var mode: SimulationMode = .teleport
    @Published var selectedCoordinate = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
    @Published var routePoints: [GeoCoordinate] = []
    @Published var speedKilometresPerHour = 5.0
    @Published var loopRoute = false
    @Published var loopTransitionMode: LoopTransitionMode = .walkBack
    @Published var deviceIP = "10.7.0.1"
    @Published private(set) var status = SimulationStatus()
    @Published var lastError: String?

    let pairingStore = PairingFileStore()
    let backend: any LocationSimulationBackend

    private var playbackTask: Task<Void, Never>?
    private let tickNanoseconds: UInt64 = 250_000_000
    private let tickSeconds = 0.25

    init(backend: (any LocationSimulationBackend)? = nil) {
        self.backend = backend ?? LocationSimulationBackendFactory.makeDefault()
        status.message = self.backend.canControlDeviceLocation
            ? "裝置定位後端已就緒"
            : "目前為預覽模式；尚未連結 idevice"
    }

    var backendName: String { backend.name }
    var canControlDeviceLocation: Bool { backend.canControlDeviceLocation }

    func select(_ coordinate: GeoCoordinate) {
        selectedCoordinate = coordinate
        if mode == .route {
            routePoints.append(coordinate)
        }
    }

    func removeLastRoutePoint() {
        _ = routePoints.popLast()
    }

    func clearRoute() {
        routePoints.removeAll()
    }

    func start() {
        lastError = nil
        playbackTask?.cancel()

        if mode == .route {
            guard routePoints.count >= 2 else {
                lastError = SimulationError.routeNeedsTwoPoints.localizedDescription
                return
            }
            startRoute()
        } else {
            playbackTask = Task { [weak self] in
                guard let self else { return }
                await send(selectedCoordinate)
            }
        }
    }

    func togglePause() {
        guard status.isActive else { return }
        status.isPaused.toggle()
        status.message = status.isPaused ? "已暫停" : "模擬中"
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        if backend.canControlDeviceLocation, !pairingStore.isImported {
            lastError = SimulationError.pairingFileRequired.localizedDescription
            return
        }
        Task {
            do {
                try await backend.clearLocation(
                    pairingFileURL: pairingStore.url,
                    deviceIP: deviceIP
                )
                status = SimulationStatus(
                    isActive: false,
                    isPaused: false,
                    coordinate: nil,
                    message: "已清除模擬位置"
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func startRoute() {
        let points = RoutePlan.traversalPoints(
            routePoints,
            loop: loopRoute,
            transitionMode: loopTransitionMode
        )
        playbackTask = Task { [weak self] in
            guard let self else { return }
            var traversal = points

            while !Task.isCancelled {
                for index in 0..<max(traversal.count - 1, 0) {
                    let completed = await move(from: traversal[index], to: traversal[index + 1])
                    if !completed { return }
                }

                guard loopRoute else { break }
                if loopTransitionMode == .teleportToStart, let first = routePoints.first {
                    await send(first)
                }
                traversal = RoutePlan.traversalPoints(
                    routePoints,
                    loop: loopRoute,
                    transitionMode: loopTransitionMode
                )
            }

            if !Task.isCancelled {
                status.message = "路線已完成"
            }
        }
    }

    private func move(from start: GeoCoordinate, to end: GeoCoordinate) async -> Bool {
        let distance = max(GeoMath.distanceMetres(from: start, to: end), 0.1)
        var travelled = 0.0

        while travelled < distance, !Task.isCancelled {
            while status.isPaused, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickNanoseconds)
            }
            guard !Task.isCancelled else { return false }
            let coordinate = GeoMath.interpolate(from: start, to: end, fraction: travelled / distance)
            await send(coordinate)
            if lastError != nil { return false }
            let speed = max(speedKilometresPerHour / 3.6, 0.5)
            travelled += speed * tickSeconds
            try? await Task.sleep(nanoseconds: tickNanoseconds)
        }

        await send(end)
        return lastError == nil
    }

    private func send(_ coordinate: GeoCoordinate?) async {
        guard let coordinate else { return }
        if backend.canControlDeviceLocation, !pairingStore.isImported {
            lastError = SimulationError.pairingFileRequired.localizedDescription
            return
        }

        do {
            try await backend.setLocation(
                coordinate,
                pairingFileURL: pairingStore.url,
                deviceIP: deviceIP
            )
            status = SimulationStatus(
                isActive: true,
                isPaused: status.isPaused,
                coordinate: coordinate,
                message: backend.canControlDeviceLocation ? "裝置定位模擬中" : "預覽座標更新中"
            )
        } catch {
            lastError = error.localizedDescription
            playbackTask?.cancel()
            playbackTask = nil
        }
    }
}
