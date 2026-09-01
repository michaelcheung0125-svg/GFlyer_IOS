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
    @Published private(set) var playbackSettings = PlaybackSettings()
    @Published private(set) var pendingCrossDateWarning: CrossDateWarning?
    @Published private(set) var pendingResumeSession: ActiveSessionSnapshot?
    @Published var lastError: String?

    let pairingStore = PairingFileStore()
    let backend: any LocationSimulationBackend
    let deviceLocation = DeviceLocationService()

    private let dataStore: LocalDataStore
    private let sessionStore: ActiveSessionStore
    private var lastSessionSnapshotAt = Date.distantPast
    private var currentLapPoints: [GeoCoordinate] = []
    private var currentLapNextIndex = 0
    // 每次啟動遞增；被取代的播放任務在 defer 中比對，避免關閉新任務的背景活動
    private var playbackGeneration = 0
    private var playbackTask: Task<Void, Never>?
    private var joystickTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var joystickBearing = 0.0
    private var joystickMagnitude = 0.0
    private var joystickSpeedMetresPerSecond = 0.0
    private var advanceRequested = false
    private var countdownSkipRequested = false
    private var orbitSkipRequested = false
    private var spiralState = SpiralState()
    private var spiralCenter: GeoCoordinate?
    private let tickNanoseconds: UInt64 = 250_000_000
    private let tickSeconds = 0.25

    init(
        backend: (any LocationSimulationBackend)? = nil,
        dataStore: LocalDataStore = LocalDataStore(),
        sessionStore: ActiveSessionStore = ActiveSessionStore()
    ) {
        self.backend = backend ?? LocationSimulationBackendFactory.makeDefault()
        self.dataStore = dataStore
        self.sessionStore = sessionStore
        pendingResumeSession = sessionStore.load()
        let stored = dataStore.snapshot
        favorites = stored.favorites
        history = stored.history
        favoriteFolders = stored.folders
        savedRoutes = stored.routes
        quickSpeedPresets = stored.presets
        playbackSettings = stored.playback
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

    func start(bypassCrossDateCheck: Bool = false) {
        lastError = nil
        if mode == .teleport,
           !bypassCrossDateCheck,
           playbackSettings.crossDateWarningEnabled,
           let warning = CrossDateChecker.warning(destination: selectedCoordinate) {
            pendingCrossDateWarning = warning
            return
        }
        pendingCrossDateWarning = nil
        playbackTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil
        deviceLocation.stopBackgroundRouteActivity()

        guard pairingIsReady else { return }
        lastSessionSnapshotAt = .distantPast
        currentLapPoints = []
        currentLapNextIndex = 0
        playbackGeneration += 1

        switch mode {
        case .teleport:
            dataStore.addHistory(coordinate: selectedCoordinate)
            refreshStoredData()
            playbackTask = Task { [weak self] in
                guard let self else { return }
                await send(selectedCoordinate, message: "裝置定位模擬中")
            }
            scheduleAutoStop()
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
            scheduleAutoStop()
        case .explore:
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            startExplore()
            scheduleAutoStop()
        }
    }

    // 不檢查 pendingCrossDateWarning：SwiftUI 可能在按鈕動作前先把
    // isPresented binding 設為 false（清掉 pending），確認仍必須生效。
    func confirmCrossDateStart() {
        pendingCrossDateWarning = nil
        start(bypassCrossDateCheck: true)
    }

    func cancelCrossDateStart() {
        pendingCrossDateWarning = nil
    }

    // MARK: - 中斷恢復

    /// 恢復中斷的模擬。快照由呼叫端（alert 的 presenting 值）傳入，
    /// 因為 isPresented binding 的 setter 可能在按鈕動作前先清掉 pending 狀態。
    func resumeInterruptedSession(_ snapshotOverride: ActiveSessionSnapshot? = nil) {
        guard let snapshot = snapshotOverride ?? pendingResumeSession else { return }
        pendingResumeSession = nil
        guard pairingIsReady else { return }
        speedKilometresPerHour = SpeedScale.clamped(snapshot.speedKilometresPerHour)
        lastSessionSnapshotAt = .distantPast
        switch snapshot.mode {
        case .teleport:
            mode = .teleport
            routePoints = []
            selectedCoordinate = snapshot.coordinate
            start(bypassCrossDateCheck: true)
        case .singleRoute, .multiRoute:
            guard snapshot.routePoints.count >= 2 else {
                sessionStore.clear()
                return
            }
            mode = snapshot.mode
            routePoints = snapshot.routePoints
            loopRoute = snapshot.loop
            loopTransitionMode = snapshot.transition
            selectedCoordinate = snapshot.coordinate
            dataStore.saveDraft(points: routePoints, loop: loopRoute)
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            let firstLap = [snapshot.coordinate] + snapshot.remainingPoints
            startRoute(resumingFrom: firstLap.count >= 2 ? firstLap : nil)
            scheduleAutoStop()
        case .explore:
            mode = .explore
            routePoints = []
            spiralCenter = snapshot.spiralCenter ?? snapshot.coordinate
            spiralState = SpiralState(angleRadians: snapshot.spiralAngleRadians ?? 0)
            selectedCoordinate = snapshot.coordinate
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            startExplore(preserveState: true)
            scheduleAutoStop()
        }
    }

    /// 只關閉恢復提示，不動已儲存的快照（alert 收合時呼叫）。
    func clearResumePrompt() {
        pendingResumeSession = nil
    }

    func discardInterruptedSession() {
        pendingResumeSession = nil
        sessionStore.clear()
    }

    private func saveSessionSnapshot(coordinate: GeoCoordinate, force: Bool = false) {
        guard status.isActive else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSessionSnapshotAt) >= 15 else { return }
        lastSessionSnapshotAt = now
        // 搖桿移動時視為「保持位置」快照，恢復時不會重播整條路線
        let snapshotMode: SimulationMode = joystickTask != nil ? .teleport : (status.mode ?? mode)
        let remaining: [GeoCoordinate]
        if snapshotMode.isRoute, currentLapNextIndex < currentLapPoints.count {
            remaining = Array(currentLapPoints[currentLapNextIndex...])
        } else {
            remaining = []
        }
        sessionStore.save(
            ActiveSessionSnapshot(
                mode: snapshotMode,
                coordinate: coordinate,
                routePoints: snapshotMode.isRoute ? routePoints : [],
                remainingPoints: remaining,
                loop: loopRoute,
                transition: loopTransitionMode,
                speedKilometresPerHour: speedKilometresPerHour,
                spiralCenter: snapshotMode == .explore ? spiralCenter : nil,
                spiralAngleRadians: snapshotMode == .explore ? spiralState.angleRadians : nil,
                savedAt: now
            )
        )
    }

    func updatePlayback(_ mutate: (inout PlaybackSettings) -> Void) {
        var settings = playbackSettings
        mutate(&settings)
        playbackSettings = settings.sanitized()
        dataStore.savePlaybackSettings(playbackSettings)
    }

    func skipStartCountdown() {
        guard status.countdownRemaining != nil else { return }
        countdownSkipRequested = true
    }

    func advanceToNextRoutePoint() {
        guard status.waitingManualAdvance else { return }
        advanceRequested = true
    }

    func skipOrbit() {
        guard status.isOrbiting else { return }
        orbitSkipRequested = true
    }

    func togglePause() {
        guard status.isActive, status.mode == .singleRoute || status.mode == .multiRoute || status.mode == .explore else { return }
        status.isPaused.toggle()
        status.message = status.isPaused ? "已暫停" : "模擬中"
    }

    func stop(reason: String? = nil) {
        let motionTasks = beginStop()
        guard pairingIsReady else { return }
        Task { _ = await performClear(motionTasks: motionTasks, reason: reason, tearDownSession: false) }
    }

    /// 完整清除：清除座標、拆掉模擬 session，然後「驗證」——抓一筆新的定位，
    /// 如實回報現在是真實位置、仍是模擬座標，還是取不到定位。
    /// 實機觀察：即使拆掉 session，iOS 仍會沿用快取的模擬定位直到取得新的
    /// 真實 fix，所以只能驗證與指引，不能宣稱「已恢復真實定位」。
    @discardableResult
    func forceClearSimulation() async -> String {
        let motionTasks = beginStop()
        guard pairingIsReady else {
            let message = "目前為預覽模式，不需要清除裝置定位。"
            status = SimulationStatus(message: message)
            return message
        }
        let cleared = await performClear(motionTasks: motionTasks, reason: nil, tearDownSession: true)
        guard lastError == nil else { return cleared }

        // 驗證：等一筆「清除之後」產生的新定位
        let verification: String
        switch await verifyRealLocation() {
        case .real:
            verification = "已完整清除，目前回報的是真實位置。"
        case .simulated:
            verification = "模擬 session 已關閉，但 iOS 仍回報模擬座標。請關閉 LocalDevVPN，開關一次飛行模式後再確認；必要時重新開機。"
        case .unavailable:
            verification = "模擬 session 已關閉，但暫時取不到新的定位。請到收訊較好的位置，或開關一次飛行模式後再試。"
        }
        status.message = verification
        return verification
    }

    private enum LocationVerification { case real, simulated, unavailable }

    private func verifyRealLocation() async -> LocationVerification {
        await withCheckedContinuation { continuation in
            deviceLocation.requestCurrentLocation { result in
                switch result {
                case let .success(fix):
                    continuation.resume(returning: fix.isSimulatedBySoftware ? .simulated : .real)
                case .failure:
                    continuation.resume(returning: .unavailable)
                }
            }
        }
    }

    /// 取消進行中的任務並釋放本機狀態，回傳需要先等它結束的移動任務。
    private func beginStop() -> [Task<Void, Never>] {
        // 這些任務可能各有一筆 setLocation 已經送出。若先清除、再讓那筆落地，
        // 裝置會在「已清除」訊息下繼續模擬，所以要先等它們結束才清除。
        let motionTasks = [playbackTask, joystickTask].compactMap { $0 }
        playbackTask?.cancel()
        playbackTask = nil
        joystickTask?.cancel()
        joystickTask = nil
        autoStopTask?.cancel()
        autoStopTask = nil
        sessionStore.clear()
        currentLapPoints = []
        currentLapNextIndex = 0
        status.autoStopAt = nil
        deviceLocation.stopBackgroundRouteActivity()
        return motionTasks
    }

    @discardableResult
    private func performClear(
        motionTasks: [Task<Void, Never>],
        reason: String?,
        tearDownSession: Bool
    ) async -> String {
        for task in motionTasks { _ = await task.value }
        do {
            try await backend.clearLocation(
                pairingFileURL: pairingStore.url,
                pairingFileRevision: pairingStore.revision,
                deviceIP: deviceIP,
                tearDownSession: tearDownSession
            )
            // 誠實訊息：清除只是送出指令，iOS 可能仍沿用快取的模擬定位。
            // 要確認回到真實位置，用設定內的「完整清除模擬定位」。
            let base = "已清除模擬位置；通道保持待命"
            let message = reason.map { "\($0)；\(base)" } ?? base
            status = SimulationStatus(message: message)
            return message
        } catch {
            lastError = error.localizedDescription
            return error.localizedDescription
        }
    }

    private func scheduleAutoStop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        let minutes = playbackSettings.autoStopMinutes
        guard minutes > 0 else {
            status.autoStopAt = nil
            return
        }
        status.autoStopAt = Date().addingTimeInterval(Double(minutes) * 60)
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            stop(reason: "已按自動停止設定關閉虛擬定位")
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

    func requestCurrentLocation(
        onSuccess: @escaping (DeviceLocationService.CurrentLocationFix) -> Void
    ) {
        lastError = nil
        deviceLocation.requestCurrentLocation { [weak self] result in
            switch result {
            case let .success(fix):
                onSuccess(fix)
            case let .failure(error):
                self?.lastError = error.localizedDescription
            }
        }
    }

    func startJoystick(bearingDegrees: Double, magnitude: Double = 1) {
        guard pairingIsReady else { return }
        joystickBearing = bearingDegrees
        joystickMagnitude = min(max(magnitude, 0), 1)
        if joystickTask != nil { return }
        // 搖桿接管移動：結束路線／探索播放，避免兩個任務同時推送座標
        playbackTask?.cancel()
        playbackTask = nil
        playbackGeneration += 1
        deviceLocation.stopBackgroundRouteActivity()
        currentLapPoints = []
        currentLapNextIndex = 0
        status.isPaused = false
        status.countdownRemaining = nil
        status.waitingManualAdvance = false
        status.isOrbiting = false
        joystickSpeedMetresPerSecond = 0
        joystickTask = Task { [weak self] in
            guard let self else { return }
            var current = status.coordinate ?? selectedCoordinate
            while !Task.isCancelled {
                joystickSpeedMetresPerSecond = JoystickDynamics.nextSpeed(
                    currentMetresPerSecond: joystickSpeedMetresPerSecond,
                    magnitude: joystickMagnitude,
                    maxSpeedMetresPerSecond: Double(playbackSettings.joystickMaxSpeedKilometresPerHour) / 3.6,
                    deltaSeconds: tickSeconds
                )
                let distance = joystickSpeedMetresPerSecond * tickSeconds
                if distance > 0 {
                    current = GeoMath.destination(
                        from: current,
                        bearingDegrees: joystickBearing,
                        distanceMetres: distance
                    )
                }
                let displaySpeed = Int((joystickSpeedMetresPerSecond * 3.6).rounded())
                guard await send(current, message: "搖桿控制中 · \(displaySpeed) km/h") else { return }
                await sleepThroughPause(nanoseconds: tickNanoseconds)
            }
        }
    }

    func updateJoystick(bearingDegrees: Double, magnitude: Double = 1) {
        joystickBearing = bearingDegrees
        joystickMagnitude = min(max(magnitude, 0), 1)
    }

    func stopJoystick() {
        joystickTask?.cancel()
        joystickTask = nil
        joystickMagnitude = 0
        joystickSpeedMetresPerSecond = 0
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

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        searchResults = []
        isSearching = false
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
        previewExternalCoordinate(coordinate, startImmediately: startImmediately, sourceLabel: "留言板")
    }

    @discardableResult
    func previewExternalCoordinate(
        _ coordinate: GeoCoordinate,
        startImmediately: Bool,
        sourceLabel: String
    ) -> Bool {
        guard !status.isActive else {
            lastError = "請先停止目前的定位模擬，再使用\(sourceLabel)座標。"
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
        let name = Self.uniqueRouteName(base: baseName, existingLowercased: existingNames)
        dataStore.saveRoute(name: name, points: route.points, loop: route.loop)
        refreshStoredData()
    }

    // MARK: - GPX 與備份

    @discardableResult
    func importGpxData(_ data: Data) -> Int {
        let imported = GpxCodec.readRoutes(from: data).filter { $0.points.count >= 2 }
        guard !imported.isEmpty else {
            lastError = "GPX 檔案中找不到可用路線（每條路線至少需要兩個座標）。"
            return 0
        }
        var existingNames = Set(savedRoutes.map { $0.name.lowercased() })
        var namedRoutes: [(name: String, points: [GeoCoordinate], loop: Bool)] = []
        for route in imported {
            let base = route.name.map { String($0.prefix(80)) } ?? "匯入路線"
            let name = Self.uniqueRouteName(base: base, existingLowercased: existingNames)
            existingNames.insert(name.lowercased())
            namedRoutes.append((name: name, points: route.points, loop: false))
        }
        dataStore.saveRoutes(namedRoutes)
        refreshStoredData()
        // 只有在沒有進行中的模擬、也沒有未儲存的路線草稿時才自動載入
        if !status.isActive,
           routePoints.count <= 1,
           let firstName = namedRoutes.first?.name,
           let firstRoute = savedRoutes.first(where: { $0.name == firstName }) {
            loadSavedRoute(firstRoute)
        }
        return imported.count
    }

    func exportAllRoutesAsGpx() -> Data? {
        let routes = savedRoutes.filter { $0.points.count >= 2 }
        guard !routes.isEmpty else {
            lastError = "沒有可匯出的已儲存路線。"
            return nil
        }
        return GpxCodec.write(routes: routes.map { GpxCodec.ExportRoute(name: $0.name, points: $0.points) })
    }

    func exportBackupData() -> Data? {
        do {
            return try AppBackupCodec.export(snapshot: dataStore.snapshot)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func importBackupData(_ data: Data) -> BackupImportResult? {
        do {
            let payload = try AppBackupCodec.decode(data)
            let result = dataStore.applyBackup(payload)
            refreshStoredData()
            playbackSettings = dataStore.snapshot.playback
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    static func uniqueRouteName(base: String, existingLowercased: Set<String>) -> String {
        var name = String(base.prefix(80))
        var suffix = 2
        while existingLowercased.contains(name.lowercased()) {
            let suffixText = " \(suffix)"
            name = String(base.prefix(max(80 - suffixText.count, 1))) + suffixText
            suffix += 1
        }
        return name
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

    private func startRoute(resumingFrom firstLapPoints: [GeoCoordinate]? = nil) {
        var settings = playbackSettings
        // 進階播放選項的 UI 只出現在多點模式，單點路線一律用預設行為
        if mode != .multiRoute {
            settings.travelMode = .simulate
            settings.pointAction = .none
            settings.manualAdvance = false
        }
        let points = routePoints
        let traversal = RoutePlan.traversalPoints(points, loop: loopRoute, transitionMode: loopTransitionMode)
        let loop = loopRoute
        let transition = loopTransitionMode
        advanceRequested = false
        countdownSkipRequested = false
        orbitSkipRequested = false
        status.isActive = true
        status.isPaused = false
        status.mode = mode
        playbackGeneration += 1
        let generation = playbackGeneration
        // 依 lap 內位置換算原路線的顯示編號；walk-back 尾段回到第 1 點。
        // 恢復的第一圈是 traversal 的尾段，先對齊再換算。
        func pointNumber(lapPoints: [GeoCoordinate], nextIndex: Int) -> Int {
            let traversalIndex = min(
                max(traversal.count - lapPoints.count + nextIndex, 0),
                max(traversal.count - 1, 0)
            )
            if loop, transition == .walkBack, traversalIndex == traversal.count - 1 { return 1 }
            return traversalIndex + 1
        }
        playbackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == playbackGeneration {
                    deviceLocation.stopBackgroundRouteActivity()
                    status.countdownRemaining = nil
                    status.waitingManualAdvance = false
                    status.isOrbiting = false
                }
            }
            let countdownSeconds = firstLapPoints == nil ? settings.startDelaySeconds : 0
            guard await runStartCountdown(seconds: countdownSeconds) else { return }
            var lapPoints = firstLapPoints ?? traversal
            while !Task.isCancelled {
                currentLapPoints = lapPoints
                for index in 0..<max(lapPoints.count - 1, 0) {
                    let start = lapPoints[index]
                    let end = lapPoints[index + 1]
                    let number = pointNumber(lapPoints: lapPoints, nextIndex: index + 1)
                    currentLapNextIndex = index + 1
                    switch settings.travelMode {
                    case .simulate:
                        guard await move(from: start, to: end) else { return }
                    case .teleport:
                        guard await send(end, message: "已傳送至第 \(number) 點") else { return }
                    }
                    saveSessionSnapshot(coordinate: end, force: true)
                    let isFinalStop = !loop && index + 1 == lapPoints.count - 1
                    let hasArrivalStep = settings.manualAdvance
                        || settings.pointAction != .none
                        || (settings.travelMode == .teleport && settings.dwellSeconds > 0)
                    if !hasArrivalStep && isFinalStop { continue }
                    if settings.travelMode == .teleport, settings.dwellSeconds > 0 {
                        guard await dwellAtPoint(seconds: settings.dwellSeconds, pointNumber: number) else { return }
                    }
                    switch settings.pointAction {
                    case .orbit:
                        guard await orbitAround(end, pointNumber: number, radiiMetres: settings.orbitRadiiMetres) else { return }
                    case .microMove:
                        guard await microMoveEast(from: end, pointNumber: number) else { return }
                    case .none:
                        break
                    }
                    if isFinalStop { continue }
                    if settings.manualAdvance {
                        guard await waitForManualAdvance(pointNumber: number) else { return }
                    }
                }
                lapPoints = traversal
                guard loop else { break }
                if transition == .teleportToStart, let first = points.first {
                    guard await send(first, message: "循環路線模擬中") else { return }
                }
            }
            if !Task.isCancelled {
                status.message = "路線已完成"
                sessionStore.clear()
                currentLapPoints = []
                currentLapNextIndex = 0
            }
        }
    }

    private func runStartCountdown(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        var remaining = seconds
        while remaining > 0, !Task.isCancelled, !countdownSkipRequested {
            status.countdownRemaining = remaining
            status.message = "\(remaining) 秒後開始路線…"
            await sleepThroughPause(nanoseconds: 1_000_000_000)
            if !status.isPaused { remaining -= 1 }
        }
        let skipped = countdownSkipRequested && remaining > 0
        countdownSkipRequested = false
        status.countdownRemaining = nil
        guard !Task.isCancelled else { return false }
        if skipped { status.message = "已跳過倒數，立即開始路線" }
        return true
    }

    private func dwellAtPoint(seconds: Int, pointNumber: Int) async -> Bool {
        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            status.message = "第 \(pointNumber) 點 · 停留 \(remaining) 秒…"
            await sleepThroughPause(nanoseconds: 1_000_000_000)
            if !status.isPaused { remaining -= 1 }
        }
        return !Task.isCancelled
    }

    private func waitForManualAdvance(pointNumber: Int) async -> Bool {
        advanceRequested = false
        status.waitingManualAdvance = true
        status.message = "已到達第 \(pointNumber) 點，按「下一點」繼續"
        defer { status.waitingManualAdvance = false }
        while !advanceRequested, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: tickNanoseconds)
        }
        advanceRequested = false
        guard !Task.isCancelled else { return false }
        status.message = "前往下一點"
        return true
    }

    private func orbitAround(_ center: GeoCoordinate, pointNumber: Int, radiiMetres: [Int]) async -> Bool {
        let radii = radiiMetres.isEmpty ? PlaybackSettings.defaultOrbitRadiiMetres : radiiMetres
        orbitSkipRequested = false
        status.isOrbiting = true
        defer { status.isOrbiting = false }
        var angle = 0.0
        for (lapIndex, radiusValue) in radii.enumerated() {
            let radius = Double(radiusValue)
            let stepRadians = OrbitPlanner.stepRadians(
                speedMetresPerSecond: clampedSpeedMetresPerSecond,
                radiusMetres: radius,
                tickSeconds: tickSeconds
            )
            let stepsPerLap = OrbitPlanner.stepsPerLap(stepRadians: stepRadians)
            for _ in 0..<stepsPerLap {
                if orbitSkipRequested {
                    orbitSkipRequested = false
                    status.message = "已跳過繞圈，前往下一點"
                    return true
                }
                guard !Task.isCancelled else { return false }
                angle += stepRadians
                let target = GeoMath.offset(
                    from: center,
                    eastMetres: radius * cos(angle),
                    northMetres: radius * sin(angle)
                )
                guard await send(
                    target,
                    message: "繞圈中 · 第 \(lapIndex + 1)/\(radii.count) 圈 · 半徑 \(radiusValue) 米"
                ) else { return false }
                await sleepThroughPause(nanoseconds: tickNanoseconds)
            }
        }
        status.message = "已完成第 \(pointNumber) 點繞圈"
        return true
    }

    private var clampedSpeedMetresPerSecond: Double {
        max(speedKilometresPerHour / 3.6, 0.5)
    }

    private func microMoveEast(from origin: GeoCoordinate, pointNumber: Int) async -> Bool {
        let distance = PlaybackSettings.microMoveDistanceMetres
        let steps = max(Int(ceil(distance / (clampedSpeedMetresPerSecond * tickSeconds))), 1)
        let stepLength = distance / Double(steps)
        var current = origin
        for _ in 0..<steps {
            guard !Task.isCancelled else { return false }
            current = GeoMath.destination(from: current, bearingDegrees: 90, distanceMetres: stepLength)
            guard await send(current, message: "到點微動中 · 向東 20 米") else { return false }
            await sleepThroughPause(nanoseconds: tickNanoseconds)
        }
        status.message = "已完成第 \(pointNumber) 點微動"
        return true
    }

    private func sleepThroughPause(nanoseconds: UInt64) async {
        while status.isPaused, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: tickNanoseconds)
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func startExplore(preserveState: Bool = false) {
        guard !status.isActive || preserveState else {
            lastError = SimulationError.exploreAlreadyActive.localizedDescription
            return
        }
        if !preserveState {
            spiralCenter = selectedCoordinate
            spiralState = SpiralState()
        }
        playbackGeneration += 1
        let generation = playbackGeneration
        playbackTask = Task { [weak self] in
            guard let self, let center = spiralCenter else { return }
            defer {
                if generation == playbackGeneration {
                    deviceLocation.stopBackgroundRouteActivity()
                }
            }
            var current = selectedCoordinate
            while !Task.isCancelled {
                let step = SpiralPath.advance(
                    center: center,
                    current: current,
                    state: spiralState,
                    distanceMetres: max(speedKilometresPerHour / 3.6 * tickSeconds, 0.5)
                )
                spiralState = step.state
                current = step.coordinate
                guard await send(current, message: "螺旋探索中") else { return }
                await sleepThroughPause(nanoseconds: tickNanoseconds)
            }
        }
    }

    private func move(from start: GeoCoordinate, to end: GeoCoordinate) async -> Bool {
        let distance = max(GeoMath.distanceMetres(from: start, to: end), 0.1)
        var travelled = 0.0
        while travelled < distance, !Task.isCancelled {
            let coordinate = GeoMath.interpolate(from: start, to: end, fraction: travelled / distance)
            guard await send(coordinate, message: "路線模擬中") else { return false }
            travelled += max(speedKilometresPerHour / 3.6 * tickSeconds, 0.5)
            await sleepThroughPause(nanoseconds: tickNanoseconds)
        }
        guard !Task.isCancelled else { return false }
        return await send(end, message: "路線模擬中")
    }

    /// 回傳這次傳送是否成功。播放迴圈只依這個回傳值決定去留，
    /// 不看共用的 `lastError`——否則其他畫面（例如留言板守衛）設定的
    /// 錯誤訊息會被誤判成傳送失敗而中止路線。
    @discardableResult
    private func send(_ coordinate: GeoCoordinate, message: String) async -> Bool {
        // 取消後排隊中的傳送不能再送出：這一筆若在 clearLocation 之後
        // 才進到後端，裝置會被重新設成模擬位置
        guard !Task.isCancelled else { return false }
        do {
            try await backend.setLocation(
                coordinate,
                pairingFileURL: pairingStore.url,
                pairingFileRevision: pairingStore.revision,
                deviceIP: deviceIP
            )
            // Stop 之後回來的 in-flight 傳送不得復活狀態或重寫已清除的快照
            guard !Task.isCancelled else { return false }
            status.isActive = true
            status.coordinate = coordinate
            status.mode = mode
            status.message = message
            saveSessionSnapshot(coordinate: coordinate)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            lastError = error.localizedDescription
            playbackTask?.cancel()
            joystickTask?.cancel()
            joystickTask = nil
            autoStopTask?.cancel()
            autoStopTask = nil
            status.isActive = false
            status.isPaused = false
            status.countdownRemaining = nil
            status.waitingManualAdvance = false
            status.isOrbiting = false
            status.autoStopAt = nil
            deviceLocation.stopBackgroundRouteActivity()
            return false
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
