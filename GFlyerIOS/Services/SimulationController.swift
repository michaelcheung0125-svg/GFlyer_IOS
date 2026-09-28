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
    @Published var deviceIP = "10.7.0.1" {
        didSet { vpn.deviceIP = deviceIP }
    }
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
    /// 執行中那一輪探索(含暫停)。停止、切到其他移動方式、搖桿接管或推送失敗時清掉。
    @Published private(set) var exploration: ExplorationRun?
    /// 收藏位置與收藏路線第一點的「國家 · 城市」,鍵用 `RegionLabel.key(for:)` 算;查到才有
    /// (GFlyer-Suite docs/features/region-labels.md)。清單開著時查到新的,那一列直接更新。
    @Published private(set) var regionLabels: [String: String] = [:]
    @Published var lastError: String?

    let pairingStore = PairingFileStore()
    let backend: any LocationSimulationBackend
    let deviceLocation = DeviceLocationService()
    let vpn: LocalDevVPNBridge

    private let dataStore: LocalDataStore
    private let sessionStore: ActiveSessionStore
    private let regionLookup: RegionLookup
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
    private var explorationPreviewCache: ExplorationPreviewCache?
    private let tickNanoseconds: UInt64 = 250_000_000
    private let tickSeconds = 0.25

    init(
        backend: (any LocationSimulationBackend)? = nil,
        dataStore: LocalDataStore = LocalDataStore(),
        sessionStore: ActiveSessionStore = ActiveSessionStore(),
        vpn: LocalDevVPNBridge? = nil,
        regionLookup: RegionLookup? = nil
    ) {
        self.backend = backend ?? LocationSimulationBackendFactory.makeDefault()
        self.vpn = vpn ?? LocalDevVPNBridge()
        self.dataStore = dataStore
        self.sessionStore = sessionStore
        self.regionLookup = regionLookup ?? RegionLookup()
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
            let isMultiPoint = draft.isMultiPoint ?? (draft.points.count > 2)
            mode = isMultiPoint ? .multiRoute : .singleRoute
        }
        status.message = self.backend.canControlDeviceLocation
            ? "裝置後端已載入；通道尚未測試"
            : "目前為預覽模式；尚未連結 idevice"
        regionLabels = self.regionLookup.labels
        self.regionLookup.onLabelsChange = { [weak self] labels in self?.regionLabels = labels }
        // App 啟動就開始查,不等清單打開(和 Android 相同,隱私說明也照這樣寫)
        requestRegionLabels()
    }

    var backendName: String { backend.name }
    var canControlDeviceLocation: Bool { backend.canControlDeviceLocation }
    var isMotionActive: Bool { status.isActive }

    var isExploring: Bool { exploration != nil }

    /// 開始探索的起點:模擬中(包含靜態傳送)是目前的模擬座標,沒有模擬時是選取點。
    /// 和 Android 的 `mockStatus.coordinate ?: selected` 相同(GFlyer-Suite docs/features/serpentine-exploration.md §3.3)。
    var explorationStart: GeoCoordinate {
        if status.isActive, let coordinate = status.coordinate { return coordinate }
        return selectedCoordinate
    }

    /// 地圖上的探索預覽線(規格 §3.5):沒有在探索時從起點、進度 (0, 0)、設定的 Y 與方向畫;探索中從目前位置、
    /// 目前進度、這一輪實際在用的 Y 與方向畫。SwiftUI 每次重算 body 都會讀它,Y = 5000 時一條約 1,300 點,
    /// 所以輸入沒變就用上一次的結果。
    var explorationPreview: [GeoCoordinate] {
        guard mode == .explore else { return [] }
        let request: ExplorationPreviewRequest
        if let exploration {
            request = ExplorationPreviewRequest(
                start: exploration.current,
                state: exploration.state,
                verticalLengthMetres: exploration.verticalLengthMetres,
                direction: exploration.direction
            )
        } else {
            request = ExplorationPreviewRequest(
                start: explorationStart,
                state: SerpentineState(),
                verticalLengthMetres: Double(playbackSettings.explorationVerticalLengthMetres),
                direction: playbackSettings.explorationDirection
            )
        }
        if let cache = explorationPreviewCache, cache.request == request { return cache.points }
        let points = SerpentinePath.preview(
            current: request.start,
            state: request.state,
            verticalLengthMetres: request.verticalLengthMetres,
            direction: request.direction
        )
        explorationPreviewCache = ExplorationPreviewCache(request: request, points: points)
        return points
    }

    private struct ExplorationPreviewRequest: Equatable {
        let start: GeoCoordinate
        let state: SerpentineState
        let verticalLengthMetres: Double
        let direction: ExplorationDirection
    }

    private struct ExplorationPreviewCache {
        let request: ExplorationPreviewRequest
        let points: [GeoCoordinate]
    }

    func setMode(_ newMode: SimulationMode) {
        guard status.isActive == false else { return }
        mode = newMode
        let anchor = status.coordinate ?? selectedCoordinate
        switch newMode {
        case .teleport:
            routePoints = []
            dataStore.clearDraft()
        case .singleRoute:
            // 單點路線是「從目前位置走到點選的地方」，起點一定要有
            routePoints = [anchor]
            persistDraft()
        case .multiRoute:
            // 多點路線只放使用者自己點的點：自動帶入的起點多半只是上一次
            // 選取的位置，使用者看到它被連進路線會以為是誤點
            routePoints = []
            persistDraft()
        case .explore:
            // 起點是選取點(模擬中不能切模式)。Android 這時把選取點換成地圖中心,iOS 沒有地圖中心可用,
            // 保留目前的選取點(規格 §3.3,只影響預設起點)
            routePoints = []
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
            routePoints.append(coordinate)
            persistDraft()
        case .explore:
            // 只改選取點;探索中也可以點,不會重新開始(和 Android 相同)
            break
        }
        lastError = nil
    }

    func removeLastRoutePoint() {
        // 單點路線保留起點；多點路線可以一路刪到空
        guard routePoints.count > (mode == .multiRoute ? 0 : 1) else { return }
        routePoints.removeLast()
        persistDraft()
    }

    func clearRoute() {
        routePoints.removeAll()
        persistDraft()
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
        start(bypassCrossDateCheck: bypassCrossDateCheck, isBoardRouteStart: false)
    }

    /// - Parameter isBoardRouteStart: 留言板路線直接開始。這種路線一律純模擬移動、不倒數,
    ///   不套用使用者的播放選項(`RoutePlaybackOptions.effective`)。
    private func start(bypassCrossDateCheck: Bool, isBoardRouteStart: Bool) {
        lastError = nil
        // 模擬開始前留住真實位置，完整清除時要用（模擬中的快取定位會被略過）
        deviceLocation.recordCachedRealLocation()
        if mode == .teleport,
           !bypassCrossDateCheck,
           playbackSettings.crossDateWarningEnabled,
           let warning = CrossDateChecker.warning(destination: selectedCoordinate) {
            pendingCrossDateWarning = warning
            return
        }
        pendingCrossDateWarning = nil
        playbackTask?.cancel()
        exploration = nil
        joystickTask?.cancel()
        joystickTask = nil
        deviceLocation.stopBackgroundRouteActivity()

        guard pairingIsReady else { return }
        // 先檢查路線，才決定要不要跳去 LocalDevVPN：否則使用者切過去又回來，
        // 才看到「路線至少需要兩個點」
        if mode.isRoute, routePoints.count < 2 {
            lastError = SimulationError.routeNeedsTwoPoints.localizedDescription
            return
        }
        // 走到這裡跨日提醒已經確認過，回來後不必再問一次
        if deferUntilTunnelIsUp({ [weak self] in
            self?.start(bypassCrossDateCheck: true, isBoardRouteStart: isBoardRouteStart)
        }) { return }
        lastSessionSnapshotAt = .distantPast
        currentLapPoints = []
        currentLapNextIndex = 0
        playbackGeneration += 1
        // 被取代的路線任務不會再清這個旗標(generation 不同了);要播路線時 startRoute 會再設回來
        status.isPlayingRoute = false

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
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            dataStore.addHistory(coordinate: routePoints.last ?? selectedCoordinate)
            refreshStoredData()
            startRoute(kind: isBoardRouteStart ? .boardRoute : routeStartKind)
            scheduleAutoStop()
        case .explore:
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            // 探索中再按一次 = 從目前位置、進度 (0, 0) 重新開始,不是錯誤(規格 §3.3)。
            // 探索不寫「最近前往」,和 Android 相同
            let origin = explorationStart
            startExplore(
                ExplorationRun(
                    center: origin,
                    current: origin,
                    verticalLengthMetres: Double(playbackSettings.explorationVerticalLengthMetres),
                    direction: playbackSettings.explorationDirection
                )
            )
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
        // App 被系統結束後 VPN 多半也斷了。pendingResumeSession 已經清掉，
        // 所以從 LocalDevVPN 回來時要把快照直接帶回來
        if deferUntilTunnelIsUp({ [weak self] in self?.resumeInterruptedSession(snapshot) }) { return }
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
            persistDraft()
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            let firstLap = [snapshot.coordinate] + snapshot.remainingPoints
            startRoute(kind: routeStartKind, resumingFrom: firstLap.count >= 2 ? firstLap : nil)
            scheduleAutoStop()
        case .explore:
            // 從中斷的位置以快照的進度接著走,不跳回這一輪的起點;0.6.8 的螺旋快照變成一輪新的蛇形
            // (GFlyer-Suite docs/features/serpentine-exploration.md §4.2、§4.3)
            mode = .explore
            routePoints = []
            selectedCoordinate = snapshot.coordinate
            guard deviceLocation.startBackgroundRouteActivity() else {
                lastError = deviceLocation.backgroundPermissionMessage
                return
            }
            startExplore(snapshot.resumedExploration)
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
        // 探索的進度在 send() 之前就換成這一個 tick 的結果,所以和 coordinate 成對
        let run = snapshotMode == .explore ? exploration : nil
        sessionStore.save(
            ActiveSessionSnapshot(
                mode: snapshotMode,
                coordinate: coordinate,
                routePoints: snapshotMode.isRoute ? routePoints : [],
                remainingPoints: remaining,
                loop: loopRoute,
                transition: loopTransitionMode,
                speedKilometresPerHour: speedKilometresPerHour,
                explorationCenter: run?.center,
                explorationState: run?.state,
                explorationVerticalLengthMetres: run?.verticalLengthMetres,
                explorationDirection: run?.direction,
                savedAt: now
            )
        )
    }

    /// 探索的 Y 加減鈕(規格 §3.7)。探索中(含暫停)不能改,和 Android 一樣直接忽略。
    func adjustExplorationVerticalLength(by direction: Int) {
        guard !isExploring else { return }
        let adjusted = SerpentinePath.adjustedVerticalLength(
            playbackSettings.explorationVerticalLengthMetres,
            by: direction
        )
        updatePlayback { $0.explorationVerticalLengthMetres = adjusted }
    }

    func setExplorationDirection(_ direction: ExplorationDirection) {
        guard !isExploring else { return }
        updatePlayback { $0.explorationDirection = direction }
    }

    func updatePlayback(_ mutate: (inout PlaybackSettings) -> Void) {
        var settings = playbackSettings
        mutate(&settings)
        playbackSettings = settings.sanitized()
        dataStore.savePlaybackSettings(playbackSettings)
    }

    /// 設定頁「繞圈設定」的按鈕。按鈕不存在或停用的操作(`editedOrbitRadii` 回傳 nil)不做事。
    func editOrbitRadii(_ edit: PlaybackSettings.OrbitRadiusEdit) {
        guard let radii = PlaybackSettings.editedOrbitRadii(playbackSettings.orbitRadiiMetres, edit) else { return }
        updatePlayback { $0.orbitRadiiMetres = radii }
    }

    // 0.6.8 以前在「模擬移動」用了到點動作或手動前進的人,升級後看一次這個提示:這是這次唯一
    // 「原本有、現在沒有」的行為(GFlyer-Suite docs/features/route-arrival-actions.md §5.3、Q2)。
    static let arrivalRulesNoticeTitle = "多點路線設定已調整"
    static let arrivalRulesNoticeMessage = "「模擬移動」到點後不再繞圈、微動或等待「下一點」，這些選項只在「定點傳送」使用。"

    func dismissArrivalRulesNotice() {
        guard playbackSettings.pendingArrivalRulesNotice else { return }
        updatePlayback { $0.pendingArrivalRulesNotice = false }
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

    /// 文字和 Android 相同(GFlyer-Suite docs/features/route-arrival-actions.md §3、I14)。
    func togglePause() {
        guard status.isActive, status.mode == .singleRoute || status.mode == .multiRoute || status.mode == .explore else { return }
        status.isPaused.toggle()
        status.message = status.isPaused ? RoutePlaybackMessages.paused : RoutePlaybackMessages.resumed
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
        // 先等進行中的傳送落地，否則它可能蓋掉下面移回真實位置那一筆
        for task in motionTasks { _ = await task.value }
        await moveNearRealLocationBeforeClear()
        let cleared = await performClear(motionTasks: [], reason: nil, tearDownSession: true)
        // 清除失敗時絕不能關 VPN：之後重試清除還要靠這條通道
        guard lastError == nil else { return cleared }

        // 驗證：等一筆「清除之後」產生的新定位。要在關 VPN 之前做，因為關 VPN
        // 會跳去 LocalDevVPN，App 不在前景時未必取得到定位
        let result = await verifyRealLocation()
        let vpnClosed = await disconnectVPNAfterClearIfWanted()
        let verification: String
        switch result {
        case .real:
            verification = "已完整清除，目前回報的是真實位置。"
        case .simulated:
            verification = vpnClosed == true
                ? "模擬 session 已關閉，但 iOS 仍回報模擬座標。請開關一次飛行模式後再確認；必要時重新開機。"
                : "模擬 session 已關閉，但 iOS 仍回報模擬座標。請關閉 LocalDevVPN，開關一次飛行模式後再確認；必要時重新開機。"
        case .unavailable:
            verification = "模擬 session 已關閉，但暫時取不到新的定位。請到收訊較好的位置，或開關一次飛行模式後再試。"
        }
        let message: String
        switch vpnClosed {
        case true?: message = "\(verification)\nLocalDevVPN 已關閉。"
        case false?: message = "\(verification)\n\(LocalDevVPNBridge.disconnectFailureMessage)"
        case nil: message = verification
        }
        status.message = message
        return message
    }

    /// 清除前先在同一條連線上把模擬位置設到最後一次已知的真實位置。
    ///
    /// 兩個原因（pymobiledevice3 issue #572 的回報，GFlyer 實機也遇到第一種）：
    /// 1. 模擬位置離真實位置很遠時，清除後 iOS 常常長時間取不到定位，其他
    ///    App 顯示灰色圓圈停在模擬位置。先移到真實位置附近再清除，恢復快得多。
    /// 2. 從「不是設定模擬位置的那條連線」送出清除，有時完全無效——App 重開
    ///    後重建 session 就是這種情況。先在目前連線設定一次，清除就一定由它負責。
    ///
    /// 不知道真實位置時退而求其次，只做第 2 點：設回目前的模擬座標。
    private func moveNearRealLocationBeforeClear() async {
        let realAnchor = deviceLocation.lastRealCoordinate
        guard let anchor = realAnchor ?? status.coordinate else { return }
        do {
            try await backend.setLocation(
                anchor,
                pairingFileURL: pairingStore.url,
                pairingFileRevision: pairingStore.revision,
                deviceIP: deviceIP
            )
        } catch {
            // 設不過去也照樣清除；清除本身的錯誤由 performClear 回報
            return
        }
        guard realAnchor != nil else { return }
        status.message = "已移回真實位置附近，準備清除…"
        // 讓其他 App 先收到這個位置，清除後殘留的就是真實位置附近
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    /// 使用者開了「清除後同時關閉 LocalDevVPN」而且 VPN 目前開著才會動作。
    /// 回傳 nil 代表沒有嘗試關閉。
    private func disconnectVPNAfterClearIfWanted() async -> Bool? {
        vpn.refreshStatus()
        guard vpn.disconnectAfterFullClear, vpn.isTunnelUp, vpn.isInstalled else { return nil }
        return await vpn.perform(.disconnect)
    }

    // MARK: - LocalDevVPN

    /// 裝置模式下 VPN 沒開，就先請 LocalDevVPN 開啟，回到 GFlyer 且確認
    /// VPN 已連線後才執行 `resume`。回傳 true 代表已跳走，呼叫端這次不要繼續。
    private func deferUntilTunnelIsUp(_ resume: @escaping @MainActor () -> Void) -> Bool {
        guard backend.canControlDeviceLocation, vpn.needsConnectBeforeStart() else { return false }
        status.message = "正在開啟 LocalDevVPN…"
        Task { [weak self] in
            guard let self else { return }
            if await vpn.perform(.connect) {
                resume()
            } else {
                status.message = "LocalDevVPN 尚未連線"
                lastError = LocalDevVPNBridge.connectFailureMessage
            }
        }
        return true
    }

    /// 設定頁的手動開關。模擬進行中不准關：之後的清除指令要靠這條通道送出。
    func switchLocalDevVPN(on: Bool) {
        lastError = nil
        guard on || !status.isActive else {
            lastError = "請先按停止結束模擬，再關閉 LocalDevVPN。"
            return
        }
        guard vpn.isInstalled else {
            lastError = "找不到 LocalDevVPN，請先從 App Store 安裝。"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let reached = await vpn.perform(on ? .connect : .disconnect)
            if !reached {
                lastError = on
                    ? LocalDevVPNBridge.connectFailureMessage
                    : LocalDevVPNBridge.disconnectFailureMessage
            }
        }
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
        exploration = nil
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

    /// - Parameter onFinish: 成功與失敗都會呼叫，給呼叫端收掉「定位中」的畫面。
    ///   只靠 `onSuccess` 收不掉：失敗時它不會被呼叫，轉圈會一直留在畫面上。
    func requestCurrentLocation(
        onFinish: (() -> Void)? = nil,
        onSuccess: @escaping (DeviceLocationService.CurrentLocationFix) -> Void
    ) {
        lastError = nil
        deviceLocation.requestCurrentLocation { [weak self] result in
            onFinish?()
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
        exploration = nil
        playbackGeneration += 1
        deviceLocation.stopBackgroundRouteActivity()
        currentLapPoints = []
        currentLapNextIndex = 0
        status.isPaused = false
        status.countdownRemaining = nil
        status.waitingManualAdvance = false
        status.isOrbiting = false
        status.isPlayingRoute = false
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

    static let favoriteAddedMessage = "收藏成功"
    static let favoriteAlreadyExistsMessage = "此座標已經收藏過"

    /// 和 Android 的 `MainViewModel.addFavorite` 相同:座標已經收藏過就不新增(原本會取代那一筆),
    /// 沒有名稱時用「收藏 <座標>」。回傳要顯示的訊息。
    @discardableResult
    func addFavorite(name: String? = nil) -> String {
        let coordinate = selectedCoordinate
        guard !favorites.contains(where: { $0.coordinate == coordinate }) else {
            return Self.favoriteAlreadyExistsMessage
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? "收藏 \(coordinate.display)" : trimmed
        dataStore.addFavorite(name: title, coordinate: coordinate)
        refreshStoredData()
        return Self.favoriteAddedMessage
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
        // 單點模式看不到循環選項,不能存下看不到的循環設定
        let loop = RoutePlaybackOptions.loops(for: routeStartKind, requested: loopRoute)
        dataStore.saveRoute(name: name, points: routePoints, loop: loop)
        refreshStoredData()
    }

    func loadSavedRoute(_ route: SavedRoute) {
        mode = .multiRoute
        routePoints = route.points
        loopRoute = route.loop
        selectedCoordinate = route.points.last ?? selectedCoordinate
        persistDraft()
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
        persistDraft()
        lastError = nil
        // 直接開始是純模擬移動、不倒數(和 Android 的 startBoardRoute 相同);只預覽、之後自己按
        // 「開始」時,照一般的多點路線套用播放選項
        if startImmediately { start(bypassCrossDateCheck: false, isBoardRouteStart: true) }
        return true
    }

    func saveBoardCoordinate(_ coordinate: GeoCoordinate, name: String?) {
        let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredName = normalized.flatMap { $0.isEmpty ? nil : $0 }
        let title = (preferredName ?? "留言板位置 \(coordinate.display)").prefixCodePoints(80)
        dataStore.addFavorite(name: title, coordinate: coordinate)
        refreshStoredData()
    }

    func saveBoardRoute(_ route: SharedBoardRoute, authorName: String) {
        let baseName = "\(route.name) (\(authorName))".prefixCodePoints(80)
        let existingNames = Set(savedRoutes.map { $0.name.lowercased() })
        let name = Self.uniqueRouteName(base: baseName, existingLowercased: existingNames)
        dataStore.saveRoute(name: name, points: route.points, loop: route.loop)
        refreshStoredData()
    }

    // MARK: - GPX 與備份

    /// 選了檔案但一條路線都沒有(包括每個檔案都讀不到)時的訊息,整批只顯示一次。
    static let gpxNoRoutesMessage = "GPX 檔案中找不到可用路線（每條路線至少需要兩個座標）。"

    static func gpxImportedMessage(count: Int) -> String {
        "已匯入 \(count) 條 GPX 路線。"
    }

    /// 匯入之後要不要把第一條匯入的路線載入編輯器:模擬進行中、或草稿已經有 2 個點以上
    /// (使用者正在畫、還沒存的路線)時不載入,不可以覆蓋(GFlyer-Suite docs/features/gpx-import.md)。
    static func shouldLoadImportedRoute(isSimulating: Bool, draftPointCount: Int, importedCount: Int) -> Bool {
        importedCount > 0 && !isSimulating && draftPointCount <= 1
    }

    /// 一個 GPX 檔案:存下所有 2 點以上的路線,回傳存了幾條。沒有路線時靜默回傳 0,
    /// 訊息由呼叫端在整批處理完之後顯示一次。
    @discardableResult
    func importGpxData(_ data: Data) -> Int {
        let imported = GpxCodec.readRoutes(from: data).filter { $0.points.count >= 2 }
        guard !imported.isEmpty else { return 0 }
        let names = Self.importedRouteNames(
            for: imported.map(\.name),
            existingLowercased: Set(savedRoutes.map { $0.name.lowercased() })
        )
        let namedRoutes: [(name: String, points: [GeoCoordinate], loop: Bool)] = zip(names, imported).map { name, route in
            (name: name, points: route.points, loop: false)
        }
        dataStore.saveRoutes(namedRoutes)
        refreshStoredData()
        // 每個檔案之後判斷一次:第一個檔案載入之後草稿就超過 1 點,後面的檔案不會再載入,
        // 結果和整批之後判斷一次相同
        if Self.shouldLoadImportedRoute(
            isSimulating: status.isActive,
            draftPointCount: routePoints.count,
            importedCount: imported.count
        ),
           let firstName = namedRoutes.first?.name,
           let firstRoute = savedRoutes.first(where: { $0.name == firstName }) {
            loadImportedRoute(firstRoute)
        }
        return imported.count
    }

    /// 和 `loadSavedRoute` 相同,但不動循環設定,和 Android 的 `importGpxBatch` 相同。
    private func loadImportedRoute(_ route: SavedRoute) {
        mode = .multiRoute
        routePoints = route.points
        selectedCoordinate = route.points.last ?? selectedCoordinate
        persistDraft()
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

    /// GPX 裡的路線沒有 `<name>` 時的名稱。
    static let gpxImportFallbackName = "匯入路線"

    /// GPX 匯入的路線名稱,依 `names` 的順序:用 GPX 裡的 `<name>`,沒有時是「匯入路線」;
    /// 和既有路線或同一次匯入裡前面的路線同名(不分大小寫)時加上編號,不覆蓋既有路線。
    /// Android 的 `RouteNames.forImport` 已改成相同的規則(GFlyer-Suite docs/DRIFT.md D18、
    /// contracts/fixtures/gpx/import-names.json)。
    static func importedRouteNames(for names: [String?], existingLowercased: Set<String>) -> [String] {
        var used = existingLowercased
        return names.map { name in
            let base = name.map { $0.prefixCodePoints(80) } ?? gpxImportFallbackName
            let unique = uniqueRouteName(base: base, existingLowercased: used)
            used.insert(unique.lowercased())
            return unique
        }
    }

    static func uniqueRouteName(base: String, existingLowercased: Set<String>) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = SavedRoute.normalizedName(trimmed)
        var suffix = 2
        while existingLowercased.contains(name.lowercased()) {
            let suffixText = " \(suffix)"
            name = trimmed.prefixCodePoints(max(80 - suffixText.unicodeScalars.count, 1))
                .trimmingCharacters(in: .whitespacesAndNewlines) + suffixText
            suffix += 1
        }
        return name
    }

    func saveQuickSpeedPreset(name: String, speed: Double) {
        guard quickSpeedPresets.count < QuickSpeedPreset.maxCount else { return }
        // 和 Android 的 QuickSpeedPresetsStore 相同:去掉前後空白、最多 20 個 code point。
        // 原本不限長度,備份還原後名稱會被截短,往返一次就變了(DRIFT D14)。
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefixCodePoints(QuickSpeedPreset.maxNameLength)
        guard !normalized.isEmpty else { return }
        var presets = quickSpeedPresets
        presets.append(QuickSpeedPreset(name: normalized, kilometresPerHour: speed))
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

    /// 目前模式的路線是單點還是多點。留言板路線直接開始由 `start` 另外指定。
    private var routeStartKind: RouteStartKind {
        mode == .singleRoute ? .singleRoute : .multiRoute
    }

    /// 播放一條路線,和 Android `MockLocationService.startRoute` 相同(GFlyer-Suite
    /// docs/features/route-arrival-actions.md §3.3):實際採用的選項見 `RoutePlaybackOptions.effective`,
    /// 每一段抵達之後的步驟見 `RouteArrivalSteps`。
    private func startRoute(kind: RouteStartKind, resumingFrom firstLapPoints: [GeoCoordinate]? = nil) {
        let points = routePoints
        guard points.count >= 2 else { return }
        let options = RoutePlaybackOptions.effective(for: kind, settings: playbackSettings)
        let loop = RoutePlaybackOptions.loops(for: kind, requested: loopRoute)
        let transition = loopTransitionMode
        let traversal = RoutePlan.traversalPoints(points, loop: loop, transitionMode: transition)
        advanceRequested = false
        countdownSkipRequested = false
        orbitSkipRequested = false
        status.isActive = true
        status.isPaused = false
        status.mode = mode
        status.isPlayingRoute = true
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
        let firstLap = firstLapPoints ?? traversal
        status.message = RoutePlaybackMessages.headingTo(point: pointNumber(lapPoints: firstLap, nextIndex: 1))
        playbackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == playbackGeneration {
                    deviceLocation.stopBackgroundRouteActivity()
                    status.countdownRemaining = nil
                    status.waitingManualAdvance = false
                    status.isOrbiting = false
                    status.isPlayingRoute = false
                }
            }
            // 中斷後恢復的路線不倒數
            let countdownSeconds = firstLapPoints == nil ? options.startDelaySeconds : 0
            guard await runStartCountdown(seconds: countdownSeconds) else { return }
            var lapPoints = firstLap
            while !Task.isCancelled {
                currentLapPoints = lapPoints
                for index in 0..<max(lapPoints.count - 1, 0) {
                    let start = lapPoints[index]
                    let end = lapPoints[index + 1]
                    let number = pointNumber(lapPoints: lapPoints, nextIndex: index + 1)
                    currentLapNextIndex = index + 1
                    switch options.travelMode {
                    case .simulate:
                        guard await move(from: start, to: end) else { return }
                        status.message = RoutePlaybackMessages.arrived(at: number)
                    case .teleport:
                        // 這一段的起點不發送:開始時不先傳到第 1 點,「瞬間跳轉」循環也不回到第 1 點(和 Android 相同)
                        guard await send(end, message: RoutePlaybackMessages.teleported(to: number)) else { return }
                    }
                    saveSessionSnapshot(coordinate: end, force: true)
                    let steps = RouteArrivalSteps(
                        options: options,
                        isFinalStop: !loop && index + 1 == lapPoints.count - 1
                    )
                    if steps.dwellSeconds > 0 {
                        guard await dwellAtPoint(seconds: steps.dwellSeconds, pointNumber: number) else { return }
                    }
                    switch steps.action {
                    case .orbit:
                        guard await orbitAround(end, pointNumber: number) else { return }
                    case .microMove:
                        guard await microMoveEast(from: end, pointNumber: number) else { return }
                    case .none:
                        break
                    }
                    if steps.waitsForManualAdvance {
                        guard await waitForManualAdvance(pointNumber: number) else { return }
                    }
                }
                lapPoints = traversal
                guard loop, !Task.isCancelled else { break }
                // 模擬移動的下一圈從第 1 點走起;定點傳送不發送第 1 點(規格 Q5)
                status.message = RoutePlaybackMessages.nextLap
            }
            if !Task.isCancelled {
                status.message = RoutePlaybackMessages.finished
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
            status.message = RoutePlaybackMessages.countdown(seconds: remaining)
            await sleepThroughPause(nanoseconds: 1_000_000_000)
            if !status.isPaused { remaining -= 1 }
        }
        let skipped = countdownSkipRequested && remaining > 0
        countdownSkipRequested = false
        status.countdownRemaining = nil
        guard !Task.isCancelled else { return false }
        if skipped { status.message = RoutePlaybackMessages.countdownSkipped }
        return true
    }

    private func dwellAtPoint(seconds: Int, pointNumber: Int) async -> Bool {
        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            status.message = RoutePlaybackMessages.dwelling(point: pointNumber, remainingSeconds: remaining)
            await sleepThroughPause(nanoseconds: 1_000_000_000)
            if !status.isPaused { remaining -= 1 }
        }
        return !Task.isCancelled
    }

    private func waitForManualAdvance(pointNumber: Int) async -> Bool {
        advanceRequested = false
        status.waitingManualAdvance = true
        status.message = RoutePlaybackMessages.waitingManualAdvance(point: pointNumber)
        defer { status.waitingManualAdvance = false }
        while !advanceRequested, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: tickNanoseconds)
        }
        advanceRequested = false
        guard !Task.isCancelled else { return false }
        status.message = RoutePlaybackMessages.advancing
        return true
    }

    /// 半徑在每次開始繞圈時才讀目前的設定(播放中改了半徑,下一個點就用新的),速度在每一圈開始時讀;
    /// 狀態文字每一圈寫一次。和 Android 相同(規格 §3.2、§3.4)。
    private func orbitAround(_ center: GeoCoordinate, pointNumber: Int) async -> Bool {
        let radii = PlaybackSettings.normalizedOrbitRadii(playbackSettings.orbitRadiiMetres)
        orbitSkipRequested = false
        status.isOrbiting = true
        defer { status.isOrbiting = false }
        var angle = 0.0
        for (lapIndex, radius) in radii.enumerated() {
            let lap = OrbitPlanner.lap(
                center: center,
                radiusMetres: radius,
                startAngleRadians: angle,
                speedMetresPerSecond: routeSpeedMetresPerSecond,
                tickSeconds: tickSeconds
            )
            angle = lap.endAngleRadians
            status.message = RoutePlaybackMessages.orbitLap(lapIndex + 1, of: radii.count, radiusMetres: radius)
            for target in lap.waypoints {
                if orbitSkipRequested {
                    orbitSkipRequested = false
                    status.message = RoutePlaybackMessages.orbitSkipped
                    return true
                }
                guard !Task.isCancelled else { return false }
                guard await send(target, message: nil) else { return false }
                await sleepThroughPause(nanoseconds: tickNanoseconds)
            }
        }
        guard !Task.isCancelled else { return false }
        status.message = RoutePlaybackMessages.orbitFinished(point: pointNumber)
        return true
    }

    /// 路線播放(走路、繞圈、微動)用的速度。
    private var routeSpeedMetresPerSecond: Double {
        SpeedScale.clamped(speedKilometresPerHour) / 3.6
    }

    private func microMoveEast(from origin: GeoCoordinate, pointNumber: Int) async -> Bool {
        status.message = RoutePlaybackMessages.microMoveStarted
        let waypoints = MicroMovePlanner.waypoints(
            origin: origin,
            speedMetresPerSecond: routeSpeedMetresPerSecond,
            tickSeconds: tickSeconds
        )
        for target in waypoints {
            guard !Task.isCancelled else { return false }
            guard await send(target, message: nil) else { return false }
            await sleepThroughPause(nanoseconds: tickNanoseconds)
        }
        guard !Task.isCancelled else { return false }
        status.message = RoutePlaybackMessages.microMoveFinished(point: pointNumber)
        return true
    }

    private func sleepThroughPause(nanoseconds: UInt64) async {
        while status.isPaused, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: tickNanoseconds)
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    /// 蛇形探索,和 Android `MockLocationService.startExploration` 相同(GFlyer-Suite
    /// docs/features/serpentine-exploration.md §3.4):每 0.25 秒從上一次的位置與進度走「速度 × 0.25 秒」,
    /// 沒有最小移動距離(0.6.8 螺旋的 0.5 公尺下限會讓 7.2 km/h 以下全部變成 7.2 km/h)。速度每個 tick 重新讀。
    /// 沒有終點,只會因為停止、自動停止、推送失敗或換成其他移動方式而結束。
    private func startExplore(_ run: ExplorationRun) {
        exploration = run
        status.isActive = true
        status.isPaused = false
        status.mode = .explore
        status.message = ExplorationTexts.exploring
        playbackGeneration += 1
        let generation = playbackGeneration
        playbackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == playbackGeneration {
                    deviceLocation.stopBackgroundRouteActivity()
                }
            }
            var running = run
            while !Task.isCancelled {
                // 暫停時不前進、不推送,進度不變;繼續後從同一個進度接著走
                if !status.isPaused {
                    let step = SerpentinePath.advance(
                        current: running.current,
                        state: running.state,
                        distanceMetres: routeSpeedMetresPerSecond * tickSeconds,
                        verticalLengthMetres: running.verticalLengthMetres,
                        direction: running.direction
                    )
                    running.state = step.state
                    running.current = step.coordinate
                    // 先換進度再呼叫會順便存快照的 send(),快照的座標與進度才是同一個 tick 的結果(規格 §4.2)
                    exploration = running
                    // 逐步的傳送不改狀態文字:「正在蛇形探索」開始時寫一次,暫停 / 繼續的文字留到下一個事件
                    guard await send(step.coordinate, message: nil) else { return }
                }
                try? await Task.sleep(nanoseconds: tickNanoseconds)
            }
        }
    }

    /// 逐步的傳送不改狀態文字:「已到達第 N 點」這類事件訊息要留到下一個事件(規格 §3)。
    private func move(from start: GeoCoordinate, to end: GeoCoordinate) async -> Bool {
        let distance = max(GeoMath.distanceMetres(from: start, to: end), 0.1)
        var travelled = 0.0
        while travelled < distance, !Task.isCancelled {
            let coordinate = GeoMath.interpolate(from: start, to: end, fraction: travelled / distance)
            guard await send(coordinate, message: nil) else { return false }
            // 每一步走「速度 × 0.25 秒」,和 Android 相同。原本每步至少 0.5 公尺,最低速 1.8 km/h
            // 時實際走得比顯示的快 4 倍
            travelled += routeSpeedMetresPerSecond * tickSeconds
            await sleepThroughPause(nanoseconds: tickNanoseconds)
        }
        guard !Task.isCancelled else { return false }
        return await send(end, message: nil)
    }

    /// 回傳這次傳送是否成功。播放迴圈只依這個回傳值決定去留，
    /// 不看共用的 `lastError`——否則其他畫面（例如留言板守衛）設定的
    /// 錯誤訊息會被誤判成傳送失敗而中止路線。
    /// - Parameter message: nil 時不改狀態文字(路線播放的逐步傳送)。
    @discardableResult
    private func send(_ coordinate: GeoCoordinate, message: String?) async -> Bool {
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
            if let message { status.message = message }
            saveSessionSnapshot(coordinate: coordinate)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            lastError = error.localizedDescription
            playbackTask?.cancel()
            exploration = nil
            joystickTask?.cancel()
            joystickTask = nil
            autoStopTask?.cancel()
            autoStopTask = nil
            status.isActive = false
            status.isPaused = false
            status.countdownRemaining = nil
            status.waitingManualAdvance = false
            status.isOrbiting = false
            status.isPlayingRoute = false
            status.autoStopAt = nil
            deviceLocation.stopBackgroundRouteActivity()
            return false
        }
    }

    /// 路線模式一律存草稿，連空路線也存：多點模式剛切換時是空的，
    /// 不存的話重開 App 會掉回傳送模式。
    private func persistDraft() {
        guard mode.isRoute else { return }
        dataStore.saveDraft(points: routePoints, loop: loopRoute, isMultiPoint: mode == .multiRoute)
    }

    private func refreshStoredData() {
        favorites = dataStore.snapshot.favorites
        history = dataStore.snapshot.history
        favoriteFolders = dataStore.snapshot.folders
        savedRoutes = dataStore.snapshot.routes
        quickSpeedPresets = dataStore.snapshot.presets
        // 新增、刪除、還原備份、GPX 匯入都經過這裡;每次開始模擬、寫入歷史也會跑,
        // 已知、排過隊、失敗過的鍵 RegionLookup 都會跳過,不會多送請求
        requestRegionLabels()
    }

    /// 收藏位置依清單順序,接著是收藏路線的第一點,和 Android 相同。定位歷史不送出查詢,
    /// 只有剛好和某個收藏落在同一個快取格時才顯示標籤(region-labels.md §3.1)。
    private func requestRegionLabels() {
        regionLookup.request(favorites.map(\.coordinate) + savedRoutes.compactMap(\.points.first))
    }
}
