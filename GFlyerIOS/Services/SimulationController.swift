import Combine
import Foundation

@MainActor
final class SimulationController: ObservableObject {
    @Published var mode: SimulationMode = .teleport
    @Published var selectedCoordinate = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
    @Published var routePoints: [GeoCoordinate] = []
    @Published var speedKilometresPerHour = SpeedScale.walkKilometresPerHour
    @Published var loopRoute = false
    @Published var loopTransitionMode: LoopTransitionMode = .walkBack
    @Published var deviceIP = "10.7.0.1"
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [PlaceSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var favorites: [SavedPlace] = []
    @Published private(set) var history: [SavedPlace] = []
    @Published private(set) var favoriteFolders: [FavoriteFolder] = []
    @Published private(set) var savedRoutes: [SavedRoute] = []
    @Published private(set) var quickSpeedPresets: [QuickSpeedPreset] = SpeedScale.defaultPresets
    @Published private(set) var status = SimulationStatus()
    @Published private(set) var tunnelTestMessage = "尚未測試"
    @Published private(set) var isTestingTunnel = false
    @Published var lastError: String?

    let pairingStore = PairingFileStore()
    let backend: any LocationSimulationBackend
    let deviceLocation = DeviceLocationService()

    private let dataStore: LocalDataStore
    private var playbackTask: Task<Void, Never>?
    private var joystickTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var joystickBearing = 0.0
    private var spiralState = SpiralState()
    private var spiralCenter: GeoCoordinate?
    private let tickNanoseconds: UInt64 = 250_000_000
    private let tickSeconds = 0.25

    init(
        backend: (any LocationSimulationBackend)? = nil,
        dataStore: LocalDataStore = LocalDataStore()
    ) {
        self.backend = backend ?? LocationSimulationBackendFactory.makeDefault()
        self.dataStore = dataStore
        let stored = dataStore.snapshot
        favorites = stored.favorites
        history = stored.history
        favoriteFolders = stored.folders
        savedRoutes = stored.routes
        quickSpeedPresets = stored.presets
        if let draft = stored.draft {
            routePoints = draft.points
            loopRoute = draft.loop
            mode = draft.points.count > 2 ? .multiRoute : .singleRoute
        }
        status.message = self.backend.canControlDeviceLocation
            ? "裝置後端已載入；通道尚未測試"
            : "目前為預覽模式；尚未連結 idevice"
    }

    var backendName: String { backend.name }
    var canControlDeviceLocation: Bool { backend.canControlDeviceLocation }
    var isMotionActive: Bool { status.isActive }

    var explorationPreview: [GeoCoordinate] {
        guard mode == .explore else { return [] }
        let center = spiralCenter ?? selectedCoordinate
        let current = status.coordinate ?? selectedCoordinate
        return SpiralPath.preview(center: center, current: current, state: spiralState)
    }

    func setMode(_ newMode: SimulationMode) {
        guard status.isActive == false else { return }
        mode = newMode
        let anchor = status.coordinate ?? selectedCoordinate
        switch newMode {
        case .teleport:
            routePoints = []
            dataStore.clearDraft()
        case .singleRoute, .multiRoute:
            routePoints = [anchor]
            dataStore.saveDraft(points: routePoints, loop: loopRoute)
        case .explore:
            routePoints = []
            spiralCenter = selectedCoordinate
            spiralState = SpiralState()
            dataStore.clearDraft()
        }
        lastError = nil
    }

    func select(_ coordinate: GeoCoordinate) {
        let previous = selectedCoordinate
        selectedCoordinate = coordinate
        switch mode {
        case .teleport:
            break
        case .singleRoute:
            let origin = routePoints.first ?? status.coordinate ?? previous
            routePoints = [origin, coordinate]
            persistDraft()
        case .multiRoute:
            if routePoints.isEmpty { routePoints = [status.coordinate ?? previous] }
            routePoints.append(coordinate)
            persistDraft()
        case .explore:
            guard !status.isActive else { return }
            spiralCenter = coordinate
            spiralState = SpiralState()
        }
        lastError = nil
    }

    func removeLastRoutePoint() {
        guard routePoints.count > 1 else { return }
        routePoints.removeLast()
        persistDraft()
    }

    func clearRoute() {
        routePoints.removeAll()
        dataStore.clearDraft()
    }

    func setLoopRoute(_ enabled: Bool) {
        loopRoute = enabled
        persistDraft()
    }

    func setLoopTransitionMode(_ mode: LoopTransitionMode) {
        loopTransitionMode = mode
    }

    func setSpeed(_ speed: Double) {
        speedKilometresPerHour = SpeedScale.clamped(speed)
    }

    func setSpeedFromSlider(_ position: Double) {
        setSpeed(SpeedScale.fromSliderPosition(position))
    }

    func applySpeedPreset(_ preset: QuickSpeedPreset) {
        setSpeed(preset.kilometresPerHour)
    }

    func start() {
        lastError = nil
        playbackTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil
        deviceLocation.stopBackgroundRouteActivity()

        guard pairingIsReady else { return }

        switch mode {
        case .teleport:
            dataStore.addHistory(coordinate: selectedCoordinate)
            refreshStoredData()
            playbackTask = Task { [weak self] in
                guard let self else { return }
                await send(selectedCoordinate, message: "裝置定位模擬中")
            }
        case .singleRoute, .multiRoute:
            guard routePoints.count >= 2 else {
                lastError = SimulationError.routeNeedsTwoPoints.localizedDescription
                return
            }
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            dataStore.addHistory(coordinate: routePoints.last ?? selectedCoordinate)
            refreshStoredData()
            startRoute()
        case .explore:
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            startExplore()
        }
    }

    func togglePause() {
        guard status.isActive, status.mode == .singleRoute || status.mode == .multiRoute || status.mode == .explore else { return }
        status.isPaused.toggle()
        status.message = status.isPaused ? "已暫停" : "模擬中"
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        joystickTask?.cancel()
        joystickTask = nil
        deviceLocation.stopBackgroundRouteActivity()
        guard pairingIsReady else { return }
        Task {
            do {
                try await backend.clearLocation(
                    pairingFileURL: pairingStore.url,
                    pairingFileRevision: pairingStore.revision,
                    deviceIP: deviceIP
                )
                status = SimulationStatus(message: "已清除模擬位置；CoreDevice 通道保持待命")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func testTunnelConnection() {
        lastError = nil
        guard pairingIsReady, !isTestingTunnel else { return }
        isTestingTunnel = true
        tunnelTestMessage = "測試中..."
        Task {
            defer { isTestingTunnel = false }
            do {
                try await backend.testConnection(
                    pairingFileURL: pairingStore.url,
                    pairingFileRevision: pairingStore.revision,
                    deviceIP: deviceIP
                )
                tunnelTestMessage = "連線成功"
                status.message = "LocalDevVPN/CoreDevice 通道已驗證"
            } catch {
                tunnelTestMessage = "連線失敗"
                lastError = error.localizedDescription
            }
        }
    }

    func requestCurrentLocation(onSuccess: @escaping (GeoCoordinate) -> Void) {
        lastError = nil
        deviceLocation.requestCurrentLocation { [weak self] result in
            switch result {
            case let .success(coordinate):
                onSuccess(coordinate)
            case let .failure(error):
                self?.lastError = error.localizedDescription
            }
        }
    }

    func startJoystick(bearingDegrees: Double) {
        guard pairingIsReady else { return }
        joystickBearing = bearingDegrees
        if joystickTask != nil { return }
        joystickTask?.cancel()
        joystickTask = Task { [weak self] in
            guard let self else { return }
            var current = status.coordinate ?? selectedCoordinate
            while !Task.isCancelled {
                while status.isPaused, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: tickNanoseconds)
                }
                let distance = max(speedKilometresPerHour / 3.6 * tickSeconds, 0.5)
                current = GeoMath.destination(from: current, bearingDegrees: joystickBearing, distanceMetres: distance)
                await send(current, message: "搖桿控制中")
                try? await Task.sleep(nanoseconds: tickNanoseconds)
            }
        }
    }

    func updateJoystick(bearingDegrees: Double) {
        joystickBearing = bearingDegrees
    }

    func stopJoystick() {
        joystickTask?.cancel()
        joystickTask = nil
        if status.isActive {
            status.message = "位置已保持"
        }
    }

    func search() {
        searchTask?.cancel()
        let query = searchQuery
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await PlaceSearchService.search(query)
                guard !Task.isCancelled else { return }
                searchResults = results
                if results.isEmpty { lastError = "找不到符合的地點。" }
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error.localizedDescription
                searchResults = []
            }
            isSearching = false
        }
    }

    func chooseSearchResult(_ result: PlaceSearchResult) {
        searchQuery = result.coordinate.display
        searchResults = []
        select(result.coordinate)
    }

    func addFavorite(name: String? = nil) {
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "位置 \(selectedCoordinate.display)"
        dataStore.addFavorite(name: title, coordinate: selectedCoordinate)
        refreshStoredData()
    }

    func removeFavorite(_ id: UUID) { dataStore.removeFavorite(id); refreshStoredData() }
    func renameFavorite(_ id: UUID, name: String) { dataStore.renameFavorite(id, name: name); refreshStoredData() }
    func moveFavorite(_ id: UUID, folderID: UUID?) { dataStore.moveFavorite(id, folderID: folderID); refreshStoredData() }
    func clearHistory() { dataStore.clearHistory(); refreshStoredData() }

    func useSavedPlace(_ place: SavedPlace) {
        searchQuery = place.coordinate.display
        searchResults = []
        select(place.coordinate)
    }

    @discardableResult
    func createFavoriteFolder(name: String) -> FavoriteFolder? {
        let folder = dataStore.createFolder(name: name)
        refreshStoredData()
        return folder
    }

    func removeFavoriteFolder(_ id: UUID) { dataStore.removeFolder(id); refreshStoredData() }

    func saveRoute(name: String) {
        dataStore.saveRoute(name: name, points: routePoints, loop: loopRoute)
        refreshStoredData()
    }

    func loadSavedRoute(_ route: SavedRoute) {
        mode = .multiRoute
        routePoints = route.points
        loopRoute = route.loop
        selectedCoordinate = route.points.last ?? selectedCoordinate
        dataStore.saveDraft(points: routePoints, loop: loopRoute)
    }

    func removeSavedRoute(_ id: UUID) { dataStore.removeRoute(id); refreshStoredData() }
    func moveSavedRoute(_ id: UUID, folderID: UUID?) { dataStore.moveRoute(id, folderID: folderID); refreshStoredData() }

    @discardableResult
    func previewBoardCoordinate(_ coordinate: GeoCoordinate, startImmediately: Bool) -> Bool {
        guard !status.isActive else {
            lastError = "請先停止目前的定位模擬，再使用留言板座標。"
            return false
        }
        mode = .teleport
        routePoints = []
        dataStore.clearDraft()
        selectedCoordinate = coordinate
        searchQuery = coordinate.display
        searchResults = []
        lastError = nil
        if startImmediately { start() }
        return true
    }

    @discardableResult
    func previewBoardRoute(_ route: SharedBoardRoute, startImmediately: Bool) -> Bool {
        guard !status.isActive else {
            lastError = "請先停止目前的定位模擬，再使用留言板路線。"
            return false
        }
        mode = .multiRoute
        routePoints = route.points
        loopRoute = route.loop
        selectedCoordinate = route.points.last ?? selectedCoordinate
        dataStore.saveDraft(points: route.points, loop: route.loop)
        lastError = nil
        if startImmediately { start() }
        return true
    }

    func saveBoardCoordinate(_ coordinate: GeoCoordinate, name: String?) {
        let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredName = normalized.flatMap { $0.isEmpty ? nil : $0 }
        let title = String((preferredName ?? "留言板位置 \(coordinate.display)").prefix(80))
        dataStore.addFavorite(name: title, coordinate: coordinate)
        refreshStoredData()
    }

    func saveBoardRoute(_ route: SharedBoardRoute, authorName: String) {
        let baseName = String("\(route.name) (\(authorName))".prefix(80))
        let existingNames = Set(savedRoutes.map { $0.name.lowercased() })
        var name = baseName
        var suffix = 2
        while existingNames.contains(name.lowercased()) {
            let suffixText = " \(suffix)"
            name = String(baseName.prefix(max(80 - suffixText.count, 1))) + suffixText
            suffix += 1
        }
        dataStore.saveRoute(name: name, points: route.points, loop: route.loop)
        refreshStoredData()
    }

    func saveQuickSpeedPreset(name: String, speed: Double) {
        var presets = quickSpeedPresets
        presets.append(QuickSpeedPreset(name: name, kilometresPerHour: speed))
        dataStore.savePresets(presets)
        refreshStoredData()
    }

    func removeQuickSpeedPreset(_ id: UUID) {
        dataStore.savePresets(quickSpeedPresets.filter { $0.id != id })
        refreshStoredData()
    }

    private var pairingIsReady: Bool {
        guard backend.canControlDeviceLocation else { return true }
        guard pairingStore.isImported else {
            lastError = SimulationError.pairingFileRequired.localizedDescription
            return false
        }
        return true
    }

    private func startRoute() {
        let points = RoutePlan.traversalPoints(routePoints, loop: loopRoute, transitionMode: loopTransitionMode)
        playbackTask = Task { [weak self] in
            guard let self else { return }
            defer { deviceLocation.stopBackgroundRouteActivity() }
            while !Task.isCancelled {
                for index in 0..<max(points.count - 1, 0) {
                    guard await move(from: points[index], to: points[index + 1]) else { return }
                }
                guard loopRoute else { break }
                if loopTransitionMode == .teleportToStart, let first = routePoints.first {
                    await send(first, message: "循環路線模擬中")
                }
            }
            if !Task.isCancelled { status.message = "路線已完成" }
        }
    }

    private func startExplore() {
        guard !status.isActive else {
            lastError = SimulationError.exploreAlreadyActive.localizedDescription
            return
        }
        spiralCenter = selectedCoordinate
        spiralState = SpiralState()
        playbackTask = Task { [weak self] in
            guard let self, let center = spiralCenter else { return }
            defer { deviceLocation.stopBackgroundRouteActivity() }
            var current = selectedCoordinate
            while !Task.isCancelled {
                while status.isPaused, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: tickNanoseconds)
                }
                let step = SpiralPath.advance(
                    center: center,
                    current: current,
                    state: spiralState,
                    distanceMetres: max(speedKilometresPerHour / 3.6 * tickSeconds, 0.5)
                )
                spiralState = step.state
                current = step.coordinate
                await send(current, message: "螺旋探索中")
                try? await Task.sleep(nanoseconds: tickNanoseconds)
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
            let coordinate = GeoMath.interpolate(from: start, to: end, fraction: travelled / distance)
            await send(coordinate, message: "路線模擬中")
            if lastError != nil { return false }
            travelled += max(speedKilometresPerHour / 3.6 * tickSeconds, 0.5)
            try? await Task.sleep(nanoseconds: tickNanoseconds)
        }
        await send(end, message: "路線模擬中")
        return lastError == nil
    }

    private func send(_ coordinate: GeoCoordinate, message: String) async {
        do {
            try await backend.setLocation(
                coordinate,
                pairingFileURL: pairingStore.url,
                pairingFileRevision: pairingStore.revision,
                deviceIP: deviceIP
            )
            status = SimulationStatus(isActive: true, isPaused: status.isPaused, coordinate: coordinate, mode: mode, message: message)
        } catch {
            lastError = error.localizedDescription
            playbackTask?.cancel()
            joystickTask?.cancel()
            joystickTask = nil
            deviceLocation.stopBackgroundRouteActivity()
        }
    }

    private func persistDraft() {
        if mode == .singleRoute || mode == .multiRoute {
            if routePoints.isEmpty {
                dataStore.clearDraft()
            } else {
                dataStore.saveDraft(points: routePoints, loop: loopRoute)
            }
        }
    }

    private func refreshStoredData() {
        favorites = dataStore.snapshot.favorites
        history = dataStore.snapshot.history
        favoriteFolders = dataStore.snapshot.folders
        savedRoutes = dataStore.snapshot.routes
        quickSpeedPresets = dataStore.snapshot.presets
    }
}
