import XCTest
@testable import GFlyerIOS

final class PlaybackFeatureTests: XCTestCase {
    func testLongitudeOffsetEstimates() {
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: 114.1694), 480)
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: 0), 0)
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: -150), -600)
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: 179), 840)
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: -179), -720)
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: 7.6), 60)
        XCTAssertEqual(LongitudeTimeZoneEstimator.offsetMinutes(longitude: 7.4), 0)
    }

    func testCrossDateCheckerDetectsDifferentLocalDate() throws {
        // 2026-08-31T20:00:00Z: device UTC+8 is already 2026-09-01,
        // longitude -150 (UTC-10) is still 2026-08-31.
        let now = Date(timeIntervalSince1970: 1_788_206_400)
        let deviceZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))

        let warning = CrossDateChecker.warning(
            destination: GeoCoordinate(latitude: 21.3, longitude: -150),
            now: now,
            deviceTimeZone: deviceZone
        )
        let unwrapped = try XCTUnwrap(warning)
        XCTAssertEqual(unwrapped.deviceDateText, "2026-09-01")
        XCTAssertEqual(unwrapped.destinationDateText, "2026-08-31")
        XCTAssertEqual(unwrapped.destinationUTCOffsetMinutes, -600)

        XCTAssertNil(
            CrossDateChecker.warning(
                destination: GeoCoordinate(latitude: 25.0, longitude: 121.5),
                now: now,
                deviceTimeZone: deviceZone
            )
        )
    }

    func testPlaybackSettingsSanitization() {
        var settings = PlaybackSettings()
        settings.dwellSeconds = 999
        settings.orbitRadiiMetres = [1_000, 1, 30, 40, 50]
        settings.startDelaySeconds = 7
        settings.autoStopMinutes = 45
        let sanitized = settings.sanitized()
        XCTAssertEqual(sanitized.dwellSeconds, 300)
        // 範圍外的半徑丟掉而不是夾限,和 Android 相同
        XCTAssertEqual(sanitized.orbitRadiiMetres, [30, 40, 50])
        settings.dwellSeconds = 0
        XCTAssertEqual(settings.sanitized().dwellSeconds, 1, "停留至少 1 秒")
        // 非選項值取最接近的選項（例如 Android 備份帶來的自訂分鐘數）
        XCTAssertEqual(sanitized.startDelaySeconds, 5)
        // 45 和 30、60 距離相同,取較大的(DRIFT D15)
        XCTAssertEqual(sanitized.autoStopMinutes, 60)

        var empty = PlaybackSettings()
        empty.orbitRadiiMetres = []
        XCTAssertEqual(empty.sanitized().orbitRadiiMetres, PlaybackSettings.defaultOrbitRadiiMetres)

        var joystick = PlaybackSettings()
        joystick.joystickMaxSpeedKilometresPerHour = 2_000
        XCTAssertEqual(joystick.sanitized().joystickMaxSpeedKilometresPerHour, 900)
        joystick.joystickMaxSpeedKilometresPerHour = 1
        XCTAssertEqual(joystick.sanitized().joystickMaxSpeedKilometresPerHour, 5)
    }

    func testJoystickTargetSpeedCubicCurve() {
        let top = 500.0 / 3.6
        let minimum = JoystickDynamics.minimumMetresPerSecond
        XCTAssertEqual(JoystickDynamics.targetSpeed(magnitude: 0, maxSpeedMetresPerSecond: top), 0)
        XCTAssertEqual(
            JoystickDynamics.targetSpeed(magnitude: 0.5, maxSpeedMetresPerSecond: top),
            minimum + (top - minimum) * 0.125,
            accuracy: 0.001
        )
        XCTAssertEqual(
            JoystickDynamics.targetSpeed(magnitude: 1, maxSpeedMetresPerSecond: top),
            top,
            accuracy: 0.001
        )
    }

    func testJoystickEdgeRampIsLinearAndCapped() {
        let next = JoystickDynamics.nextSpeed(
            currentMetresPerSecond: 0,
            magnitude: 1,
            maxSpeedMetresPerSecond: 100,
            deltaSeconds: 1
        )
        XCTAssertEqual(next, 10, accuracy: 0.001)
        let capped = JoystickDynamics.nextSpeed(
            currentMetresPerSecond: 99,
            magnitude: 1,
            maxSpeedMetresPerSecond: 100,
            deltaSeconds: 1
        )
        XCTAssertEqual(capped, 100, accuracy: 0.001)
    }

    func testJoystickRampDeceleratesFasterThanAcceleratesAndSnaps() {
        let up = JoystickDynamics.rampSpeed(
            currentMetresPerSecond: 0,
            targetMetresPerSecond: 10,
            deltaSeconds: 0.25
        )
        let down = JoystickDynamics.rampSpeed(
            currentMetresPerSecond: 10,
            targetMetresPerSecond: 0,
            deltaSeconds: 0.25
        )
        XCTAssertLessThan(up, 10 - down)
        XCTAssertEqual(
            JoystickDynamics.rampSpeed(
                currentMetresPerSecond: 9.999,
                targetMetresPerSecond: 10,
                deltaSeconds: 0.25
            ),
            10
        )
    }

    func testLocalDataSnapshotDecodingToleratesMissingKeys() throws {
        var snapshot = LocalDataSnapshot()
        snapshot.favorites = [SavedPlace(name: "家", coordinate: GeoCoordinate(latitude: 22.3, longitude: 114.1))]
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "playback")
        object.removeValue(forKey: "presets")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(LocalDataSnapshot.self, from: stripped)
        XCTAssertEqual(decoded.favorites.first?.name, "家")
        XCTAssertEqual(decoded.presets, SpeedScale.defaultPresets)
        XCTAssertEqual(decoded.playback, PlaybackSettings())
    }

    func testLocalDataStorePersistsPlaybackSettings() {
        let suiteName = "gflyer.playback-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)

        var settings = PlaybackSettings()
        settings.travelMode = .teleport
        settings.pointAction = .orbit
        settings.manualAdvance = true
        settings.dwellSeconds = 25
        settings.orbitRadiiMetres = [15]
        settings.startDelaySeconds = 5
        settings.autoStopMinutes = 30
        settings.crossDateWarningEnabled = false
        store.savePlaybackSettings(settings)

        let restored = LocalDataStore(defaults: defaults)
        XCTAssertEqual(restored.snapshot.playback, settings)
        XCTAssertEqual(restored.snapshot.playback.arrivalRulesVersion, 2)
        XCTAssertEqual(try storedPlayback(in: defaults)["arrivalRulesVersion"] as? Int, 2, "版本要寫進存檔")
    }

    // MARK: - 到點規則的遷移(GFlyer-Suite docs/features/route-arrival-actions.md §5.3)

    private let localDataKey = "gflyer.local-data.v1"

    /// 0.6.8 存的播放設定:每個欄位都寫出來,沒有 arrivalRulesVersion。移動方式與到點動作存的是
    /// 當時的 rawValue(「逐點傳送」「無」),這裡刻意寫死,改了 rawValue 會讓這些測試失敗。
    private func legacyPlayback(
        travelMode: String,
        pointAction: String,
        manualAdvance: Bool = false,
        dwellSeconds: Int = 10,
        orbitRadiiMetres: [Int] = [20, 30],
        startDelaySeconds: Int = 0
    ) -> String {
        """
        {"travelMode": "\(travelMode)", "pointAction": "\(pointAction)", "manualAdvance": \(manualAdvance), \
        "dwellSeconds": \(dwellSeconds), "orbitRadiiMetres": \(orbitRadiiMetres), \
        "startDelaySeconds": \(startDelaySeconds), "autoStopMinutes": 0, "crossDateWarningEnabled": true, \
        "joystickMaxSpeedKilometresPerHour": 500}
        """
    }

    /// 把 0.6.8 的資料放進一個獨立的 UserDefaults,再用它建立 LocalDataStore(遷移在這時發生)。
    private func withLegacyStore(
        playback: String,
        _ body: (LocalDataStore, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "gflyer.arrival-migration-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = """
        {"favorites": [{"id": "\(UUID().uuidString)", "name": "家", \
        "coordinate": {"latitude": 22.3, "longitude": 114.1}, "createdAt": 0}], "playback": \(playback)}
        """
        defaults.set(Data(snapshot.utf8), forKey: localDataKey)
        try body(LocalDataStore(defaults: defaults), defaults)
    }

    private func storedPlayback(in defaults: UserDefaults) throws -> [String: Any] {
        let data = try XCTUnwrap(defaults.data(forKey: localDataKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["playback"] as? [String: Any])
    }

    func testMigrationTurnsSimulateWithoutActionIntoOrbitSilently() throws {
        try withLegacyStore(playback: legacyPlayback(travelMode: "模擬移動", pointAction: "無")) { store, defaults in
            let playback = store.snapshot.playback
            XCTAssertEqual(playback.travelMode, .simulate)
            XCTAssertEqual(playback.pointAction, .orbit, "之後切到定點傳送時預先選好繞圈(Android 的預設)")
            XCTAssertFalse(playback.pendingArrivalRulesNotice)
            XCTAssertEqual(playback.arrivalRulesVersion, 2)
            XCTAssertEqual(store.snapshot.favorites.map(\.name), ["家"], "其他資料不受影響")
            // 模擬移動本來就不做到點動作,現在也一樣
            XCTAssertEqual(RoutePlaybackOptions.effective(for: .multiRoute, settings: playback).pointAction, RoutePointAction.none)
            // 遷移後立刻寫回
            XCTAssertEqual(try storedPlayback(in: defaults)["arrivalRulesVersion"] as? Int, 2)
            XCTAssertEqual(try storedPlayback(in: defaults)["pointAction"] as? String, "繞圈")
        }
    }

    func testMigrationKeepsSimulateArrivalActionsAndShowsTheNotice() throws {
        for action in [("繞圈", RoutePointAction.orbit), ("微動", RoutePointAction.microMove)] {
            try withLegacyStore(playback: legacyPlayback(travelMode: "模擬移動", pointAction: action.0)) { store, _ in
                let playback = store.snapshot.playback
                XCTAssertEqual(playback.pointAction, action.1, action.0)
                XCTAssertTrue(playback.pendingArrivalRulesNotice, action.0)
                // 模擬移動到點不再繞圈或微動
                XCTAssertEqual(RoutePlaybackOptions.effective(for: .multiRoute, settings: playback).pointAction, RoutePointAction.none)
            }
        }
    }

    func testMigrationKeepsSimulateManualAdvanceAndShowsTheNotice() throws {
        let legacy = legacyPlayback(travelMode: "模擬移動", pointAction: "無", manualAdvance: true)
        try withLegacyStore(playback: legacy) { store, _ in
            let playback = store.snapshot.playback
            XCTAssertTrue(playback.manualAdvance, "存的值保留,切回定點傳送時還在")
            XCTAssertEqual(playback.pointAction, .orbit)
            XCTAssertTrue(playback.pendingArrivalRulesNotice)
            XCTAssertFalse(RoutePlaybackOptions.effective(for: .multiRoute, settings: playback).manualAdvance)
        }
    }

    func testMigrationKeepsTeleportWithoutAction() throws {
        try withLegacyStore(playback: legacyPlayback(travelMode: "逐點傳送", pointAction: "無")) { store, _ in
            let playback = store.snapshot.playback
            XCTAssertEqual(playback.travelMode, .teleport, "rawValue「逐點傳送」仍然讀得回來")
            XCTAssertEqual(playback.pointAction, RoutePointAction.none, "照舊傳送 → 停留 → 下一點(Q1)")
            XCTAssertFalse(playback.pendingArrivalRulesNotice)
            let options = RoutePlaybackOptions.effective(for: .multiRoute, settings: playback)
            XCTAssertEqual(options.pointAction, RoutePointAction.none)
            XCTAssertEqual(options.dwellSeconds, 10)
        }
    }

    func testMigrationKeepsTeleportManualAdvanceDwellButPlaysWithoutIt() throws {
        let legacy = legacyPlayback(travelMode: "逐點傳送", pointAction: "繞圈", manualAdvance: true, dwellSeconds: 25)
        try withLegacyStore(playback: legacy) { store, _ in
            let playback = store.snapshot.playback
            XCTAssertEqual(playback.dwellSeconds, 25)
            XCTAssertTrue(playback.manualAdvance)
            XCTAssertFalse(playback.pendingArrivalRulesNotice)
            // 手動前進時到點立刻做動作,再等「下一點」
            XCTAssertEqual(RoutePlaybackOptions.effective(for: .multiRoute, settings: playback).dwellSeconds, 0)
        }
    }

    func testMigrationRaisesZeroDwellToOneSecond() throws {
        try withLegacyStore(playback: legacyPlayback(travelMode: "逐點傳送", pointAction: "無", dwellSeconds: 0)) { store, _ in
            XCTAssertEqual(store.snapshot.playback.dwellSeconds, 1)
            XCTAssertFalse(store.snapshot.playback.pendingArrivalRulesNotice)
        }
    }

    func testMigrationDeduplicatesOrbitRadii() throws {
        let legacy = legacyPlayback(travelMode: "逐點傳送", pointAction: "繞圈", orbitRadiiMetres: [20, 20, 30, 30])
        try withLegacyStore(playback: legacy) { store, _ in
            XCTAssertEqual(store.snapshot.playback.orbitRadiiMetres, [20, 30])
            XCTAssertFalse(store.snapshot.playback.pendingArrivalRulesNotice)
        }
    }

    func testMigrationKeepsStartDelayButSingleRoutesNoLongerCountDown() throws {
        let legacy = legacyPlayback(travelMode: "模擬移動", pointAction: "無", startDelaySeconds: 5)
        try withLegacyStore(playback: legacy) { store, _ in
            let playback = store.snapshot.playback
            XCTAssertEqual(playback.startDelaySeconds, 5)
            XCTAssertEqual(RoutePlaybackOptions.effective(for: .multiRoute, settings: playback).startDelaySeconds, 5)
            XCTAssertEqual(RoutePlaybackOptions.effective(for: .singleRoute, settings: playback).startDelaySeconds, 0)
            XCTAssertEqual(RoutePlaybackOptions.effective(for: .boardRoute, settings: playback).startDelaySeconds, 0)
        }
    }

    func testMigrationRunsOnceAndCanBeRepeated() throws {
        try withLegacyStore(playback: legacyPlayback(travelMode: "模擬移動", pointAction: "繞圈")) { store, defaults in
            let migrated = store.snapshot.playback
            XCTAssertEqual(migrated.migratedToArrivalRulesV2(), migrated, "版本 2 原樣回傳")
            let reloaded = LocalDataStore(defaults: defaults)
            XCTAssertEqual(reloaded.snapshot.playback, migrated, "第二次載入不再改")
        }
    }

    /// 遷移不在存檔時跑:版本 2 的使用者從「定點傳送 + 無動作」切到模擬移動之後,存檔再載入仍然是無動作。
    func testVersionTwoSimulateWithoutActionIsNotRewrittenOnSave() {
        let suiteName = "gflyer.arrival-migration-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        var settings = PlaybackSettings()
        settings.travelMode = .simulate
        settings.pointAction = .none
        XCTAssertEqual(settings.sanitized(), settings)
        store.savePlaybackSettings(settings)

        let restored = LocalDataStore(defaults: defaults)
        XCTAssertEqual(restored.snapshot.playback.pointAction, RoutePointAction.none)
        XCTAssertFalse(restored.snapshot.playback.pendingArrivalRulesNotice)
    }

    func testRestoringABackupKeepsTheArrivalRulesVersion() throws {
        try withLegacyStore(playback: legacyPlayback(travelMode: "模擬移動", pointAction: "微動")) { store, defaults in
            let json = #"{"format": "GFlyer Backup", "version": 1, "settings": {"autoStopMinutes": 30}}"#
            store.applyBackup(try AppBackupCodec.decode(Data(json.utf8)))
            let reloaded = LocalDataStore(defaults: defaults)
            XCTAssertEqual(reloaded.snapshot.playback.arrivalRulesVersion, 2)
            XCTAssertEqual(reloaded.snapshot.playback.pointAction, .microMove)
            XCTAssertTrue(reloaded.snapshot.playback.pendingArrivalRulesNotice, "還原備份不會清掉還沒看過的提示")
        }
    }

    @MainActor
    func testArrivalRulesNoticeIsShownOnceAndDismissedForGood() throws {
        let suiteName = "gflyer.arrival-migration-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = #"{"playback": "# + legacyPlayback(travelMode: "模擬移動", pointAction: "繞圈") + "}"
        defaults.set(Data(snapshot.utf8), forKey: localDataKey)
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults)
        )
        XCTAssertTrue(controller.playbackSettings.pendingArrivalRulesNotice)
        XCTAssertEqual(SimulationController.arrivalRulesNoticeTitle, "多點路線設定已調整")
        XCTAssertEqual(
            SimulationController.arrivalRulesNoticeMessage,
            "「模擬移動」到點後不再繞圈、微動或等待「下一點」，這些選項只在「定點傳送」使用。"
        )

        controller.dismissArrivalRulesNotice()
        XCTAssertFalse(controller.playbackSettings.pendingArrivalRulesNotice)
        XCTAssertFalse(LocalDataStore(defaults: defaults).snapshot.playback.pendingArrivalRulesNotice)
    }

    // MARK: - 路線播放

    func testRoutePlaybackMessagesMatchAndroid() {
        XCTAssertEqual(RoutePlaybackMessages.headingTo(point: 2), "正在前往第 2 點")
        XCTAssertEqual(RoutePlaybackMessages.countdown(seconds: 3), "3 秒後開始路線…")
        XCTAssertEqual(RoutePlaybackMessages.countdownSkipped, "已跳過倒數，立即開始路線")
        XCTAssertEqual(RoutePlaybackMessages.teleported(to: 3), "已傳送至第 3 點")
        XCTAssertEqual(RoutePlaybackMessages.arrived(at: 3), "已到達第 3 點")
        XCTAssertEqual(RoutePlaybackMessages.dwelling(point: 2, remainingSeconds: 7), "第 2 點 · 7 秒後開始動作…")
        XCTAssertEqual(RoutePlaybackMessages.orbitLap(1, of: 2, radiusMetres: 20), "正在繞圈 · 第 1/2 圈 · 半徑 20 米")
        XCTAssertEqual(RoutePlaybackMessages.orbitSkipped, "已跳過繞圈，前往下一點")
        XCTAssertEqual(RoutePlaybackMessages.orbitFinished(point: 2), "已完成第 2 點繞圈")
        XCTAssertEqual(RoutePlaybackMessages.microMoveStarted, "到點微動中 · 向東 20 米")
        XCTAssertEqual(RoutePlaybackMessages.microMoveFinished(point: 2), "已完成第 2 點微動")
        XCTAssertEqual(RoutePlaybackMessages.waitingManualAdvance(point: 2), "已到達第 2 點，按「下一點」繼續")
        XCTAssertEqual(RoutePlaybackMessages.advancing, "前往下一點")
        XCTAssertEqual(RoutePlaybackMessages.nextLap, "開始下一輪循環")
        XCTAssertEqual(RoutePlaybackMessages.finished, "路線已完成")
    }

    /// 單點路線不循環(畫面上也沒有循環選項),存路線時也不會存下看不到的循環設定。
    @MainActor
    func testSingleRoutesNeverLoop() {
        XCTAssertFalse(RoutePlaybackOptions.loops(for: .singleRoute, requested: true))
        XCTAssertTrue(RoutePlaybackOptions.loops(for: .multiRoute, requested: true))
        XCTAssertTrue(RoutePlaybackOptions.loops(for: .boardRoute, requested: true))

        let suiteName = "gflyer.single-route-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults),
            regionLookup: .offline(defaults: defaults)
        )
        controller.setMode(.multiRoute)
        controller.setLoopRoute(true)
        controller.setMode(.singleRoute)
        controller.select(GeoCoordinate(latitude: 22.4, longitude: 114.2))
        controller.saveRoute(name: "單點")
        XCTAssertEqual(controller.savedRoutes.first?.loop, false)
    }

    func testOrbitPlannerStepCounts() {
        XCTAssertEqual(
            OrbitPlanner.stepsPerLap(speedMetresPerSecond: 5, radiusMetres: 20, tickSeconds: 0.25),
            101
        )
        // A very fast, tight orbit still gets at least 8 steps per lap.
        XCTAssertEqual(
            OrbitPlanner.stepsPerLap(speedMetresPerSecond: 250, radiusMetres: 5, tickSeconds: 0.25),
            8
        )
    }

    func testActiveSessionStoreRoundTripAndExpiry() {
        let suiteName = "gflyer.session-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActiveSessionStore(defaults: defaults)
        let snapshot = ActiveSessionSnapshot(
            mode: .multiRoute,
            coordinate: GeoCoordinate(latitude: 22.3, longitude: 114.1),
            routePoints: [
                GeoCoordinate(latitude: 22.3, longitude: 114.1),
                GeoCoordinate(latitude: 22.4, longitude: 114.2),
            ],
            remainingPoints: [GeoCoordinate(latitude: 22.4, longitude: 114.2)],
            loop: true,
            transition: .teleportToStart,
            speedKilometresPerHour: 19,
            savedAt: Date()
        )
        store.save(snapshot)

        let restored = store.load()
        XCTAssertEqual(restored?.mode, .multiRoute)
        XCTAssertEqual(restored?.routePoints, snapshot.routePoints)
        XCTAssertEqual(restored?.remainingPoints, snapshot.remainingPoints)
        XCTAssertEqual(restored?.loop, true)
        XCTAssertEqual(restored?.transition, .teleportToStart)
        XCTAssertEqual(
            restored?.savedAt.timeIntervalSince1970 ?? 0,
            snapshot.savedAt.timeIntervalSince1970,
            accuracy: 0.01
        )

        XCTAssertNil(store.load(now: snapshot.savedAt.addingTimeInterval(ActiveSessionStore.expiryInterval + 1)))
        XCTAssertNil(store.load())
    }

    @MainActor
    func testControllerOffersAndDiscardsInterruptedSession() {
        let suiteName = "gflyer.resume-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionStore = ActiveSessionStore(defaults: defaults)
        sessionStore.save(
            ActiveSessionSnapshot(
                mode: .teleport,
                coordinate: GeoCoordinate(latitude: 22.3, longitude: 114.1),
                speedKilometresPerHour: 5,
                savedAt: Date()
            )
        )

        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: sessionStore
        )
        XCTAssertEqual(controller.pendingResumeSession?.mode, .teleport)

        controller.discardInterruptedSession()
        XCTAssertNil(controller.pendingResumeSession)
        XCTAssertNil(sessionStore.load())
    }

    func testGeoMathOffsetMovesEastAndNorth() {
        let origin = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        let east = GeoMath.offset(from: origin, eastMetres: 100, northMetres: 0)
        XCTAssertEqual(GeoMath.distanceMetres(from: origin, to: east), 100, accuracy: 1)
        XCTAssertEqual(GeoMath.bearingDegrees(from: origin, to: east), 90, accuracy: 1)

        let north = GeoMath.offset(from: origin, eastMetres: 0, northMetres: 100)
        XCTAssertEqual(GeoMath.distanceMetres(from: origin, to: north), 100, accuracy: 1)

        let nearPole = GeoMath.offset(
            from: GeoCoordinate(latitude: 89.9999, longitude: 0),
            eastMetres: 0,
            northMetres: 10_000
        )
        XCTAssertLessThanOrEqual(nearPole.latitude, 90)
    }

    /// 在極點附近用最大半徑繞圈不會當掉:每一步的經度都在 [-180, 180)(I13)。改回截斷取餘的話,
    /// `GeoCoordinate.init` 的 precondition 會讓整個測試行程當掉。
    func testOrbitNextToAPoleStaysOnValidLongitudes() {
        for center in [GeoCoordinate(latitude: 90, longitude: 0), GeoCoordinate(latitude: 89.99995, longitude: -179.9)] {
            let laps = OrbitPlanner.laps(
                center: center,
                radiiMetres: [100, PlaybackSettings.orbitRadiusRange.upperBound],
                speedMetresPerSecond: 50,
                tickSeconds: 0.25
            )
            let longitudes = laps.flatMap(\.waypoints).map(\.longitude)
            XCTAssertFalse(longitudes.isEmpty)
            XCTAssertTrue(longitudes.allSatisfy { $0 >= -180 && $0 < 180 }, "\(center)")
        }
    }

    // MARK: - 蛇形探索(GFlyer-Suite docs/features/serpentine-exploration.md)

    private let activeSessionKey = "gflyer.active-session.v1"

    /// §4.3 的 0.6.8 探索快照(螺旋),原樣照抄。
    private let legacySpiralSnapshot = """
    {"mode":"探索","coordinate":{"latitude":22.331,"longitude":114.171},"routePoints":[],"remainingPoints":[],\
    "loop":false,"transition":"走回起點","speedKilometresPerHour":19,\
    "spiralCenter":{"latitude":22.3193,"longitude":114.1694},"spiralAngleRadians":12.5,"savedAt":780000000}
    """

    /// 要貼近上面的 savedAt,否則 `load(now:)` 會因為過期(600 秒)而不是因為解碼失敗回傳 nil。
    private let legacySnapshotNow = Date(timeIntervalSinceReferenceDate: 780_000_060)

    /// 把快照 JSON 放進一個獨立的 UserDefaults,再用它建立 ActiveSessionStore。
    private func withSessionStore(
        json: String,
        _ body: (ActiveSessionStore) throws -> Void
    ) throws {
        let suiteName = "gflyer.serpentine-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(json.utf8), forKey: activeSessionKey)
        try body(ActiveSessionStore(defaults: defaults))
    }

    /// §4.3 第 5 點:0.6.8 的螺旋快照照樣解得開,恢復成從 `coordinate` 開始的一輪新蛇形
    /// (進度 (0, 0)、Y 1000、EAST),不是從螺旋的中心出發。
    func testLegacySpiralSnapshotResumesAsAFreshSerpentineAtItsCoordinate() throws {
        try withSessionStore(json: legacySpiralSnapshot) { store in
            let snapshot = try XCTUnwrap(store.load(now: legacySnapshotNow))
            XCTAssertEqual(snapshot.mode, .explore)
            XCTAssertEqual(snapshot.coordinate, GeoCoordinate(latitude: 22.331, longitude: 114.171))
            XCTAssertEqual(snapshot.speedKilometresPerHour, 19)
            XCTAssertNil(snapshot.explorationCenter)
            XCTAssertNil(snapshot.explorationState)
            XCTAssertNil(snapshot.explorationVerticalLengthMetres)
            XCTAssertNil(snapshot.explorationDirection)

            let run = snapshot.resumedExploration
            XCTAssertEqual(run.current, GeoCoordinate(latitude: 22.331, longitude: 114.171))
            XCTAssertEqual(run.center, GeoCoordinate(latitude: 22.331, longitude: 114.171))
            XCTAssertEqual(run.state, SerpentineState())
            XCTAssertEqual(run.verticalLengthMetres, 1_000)
            XCTAssertEqual(run.direction, .east)
        }
    }

    /// 上機驗證的「用 0.6.8 在探索中結束 App,10 分鐘內升級再開」:提示可以恢復,不當機。
    @MainActor
    func testControllerOffersToResumeALegacySpiralSnapshot() throws {
        let suiteName = "gflyer.serpentine-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let savedAt = Date().timeIntervalSinceReferenceDate
        let json = legacySpiralSnapshot.replacingOccurrences(
            of: "\"savedAt\":780000000",
            with: "\"savedAt\":\(savedAt)"
        )
        XCTAssertNotEqual(json, legacySpiralSnapshot)
        defaults.set(Data(json.utf8), forKey: activeSessionKey)

        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults)
        )
        let pending = try XCTUnwrap(controller.pendingResumeSession)
        XCTAssertEqual(pending.mode, .explore)
        XCTAssertEqual(pending.resumedExploration.current, GeoCoordinate(latitude: 22.331, longitude: 114.171))
    }

    /// 方向認不得時只有方向變成 nil(對照 Android `ActiveSessionStoreTest.unknownEnumsFallBackWithoutLosingSnapshot`);
    /// 恢復時從中斷的位置以快照的進度接著走,不跳回這一輪的起點(§4.2)。
    func testUnknownExplorationDirectionOnlyDropsThatField() throws {
        let json = """
        {"mode":"探索","coordinate":{"latitude":22.331,"longitude":114.171},"routePoints":[],"remainingPoints":[],\
        "loop":false,"transition":"走回起點","speedKilometresPerHour":19,\
        "explorationCenter":{"latitude":22.3193,"longitude":114.1694},\
        "explorationState":{"segmentIndex":7,"distanceAlongSegmentMetres":12.25},\
        "explorationVerticalLengthMetres":2500,"explorationDirection":"UPWARDS","savedAt":780000000}
        """
        try withSessionStore(json: json) { store in
            let snapshot = try XCTUnwrap(store.load(now: legacySnapshotNow))
            XCTAssertNil(snapshot.explorationDirection)
            XCTAssertEqual(snapshot.explorationCenter, GeoCoordinate(latitude: 22.3193, longitude: 114.1694))
            XCTAssertEqual(snapshot.explorationState, SerpentineState(segmentIndex: 7, distanceAlongSegmentMetres: 12.25))
            XCTAssertEqual(snapshot.explorationVerticalLengthMetres, 2_500)

            let run = snapshot.resumedExploration
            XCTAssertEqual(run.current, GeoCoordinate(latitude: 22.331, longitude: 114.171), "從中斷的位置接著走")
            XCTAssertEqual(run.center, GeoCoordinate(latitude: 22.3193, longitude: 114.1694))
            XCTAssertEqual(run.state, SerpentineState(segmentIndex: 7, distanceAlongSegmentMetres: 12.25))
            XCTAssertEqual(run.verticalLengthMetres, 2_500)
            XCTAssertEqual(run.direction, .east)
        }
    }

    /// 每個探索欄位各自寬鬆:型別不對只讓那一個欄位變成 nil,整份快照照樣讀得到。
    func testMalformedExplorationFieldsDoNotLoseTheSnapshot() throws {
        let json = """
        {"mode":"探索","coordinate":{"latitude":22.331,"longitude":114.171},"routePoints":[],"remainingPoints":[],\
        "loop":false,"transition":"走回起點","speedKilometresPerHour":19,\
        "explorationCenter":"here","explorationState":{"segmentIndex":"seven"},\
        "explorationVerticalLengthMetres":"long","explorationDirection":7,"savedAt":780000000}
        """
        try withSessionStore(json: json) { store in
            let snapshot = try XCTUnwrap(store.load(now: legacySnapshotNow))
            XCTAssertEqual(snapshot.mode, .explore)
            XCTAssertNil(snapshot.explorationCenter)
            XCTAssertNil(snapshot.explorationState)
            XCTAssertNil(snapshot.explorationVerticalLengthMetres)
            XCTAssertNil(snapshot.explorationDirection)
            let run = snapshot.resumedExploration
            XCTAssertEqual(run.current, snapshot.coordinate)
            XCTAssertEqual(run.state, SerpentineState())
            XCTAssertEqual(run.verticalLengthMetres, 1_000)
            XCTAssertEqual(run.direction, .east)
        }
    }

    /// 0.6.8 寫的路線快照解碼與內容不受影響。
    func testLegacyRouteSnapshotIsUnaffected() throws {
        let json = """
        {"mode":"多點","coordinate":{"latitude":22.3,"longitude":114.1},\
        "routePoints":[{"latitude":22.3,"longitude":114.1},{"latitude":22.4,"longitude":114.2}],\
        "remainingPoints":[{"latitude":22.4,"longitude":114.2}],"loop":true,"transition":"直接返回",\
        "speedKilometresPerHour":50,"savedAt":780000000}
        """
        try withSessionStore(json: json) { store in
            let snapshot = try XCTUnwrap(store.load(now: legacySnapshotNow))
            XCTAssertEqual(snapshot.mode, .multiRoute)
            XCTAssertEqual(snapshot.routePoints, [
                GeoCoordinate(latitude: 22.3, longitude: 114.1),
                GeoCoordinate(latitude: 22.4, longitude: 114.2),
            ])
            XCTAssertEqual(snapshot.remainingPoints, [GeoCoordinate(latitude: 22.4, longitude: 114.2)])
            XCTAssertTrue(snapshot.loop)
            XCTAssertEqual(snapshot.transition, .teleportToStart)
            XCTAssertEqual(snapshot.speedKilometresPerHour, 50)
            XCTAssertNil(snapshot.explorationState)
        }
    }

    /// 0.6.8 解碼時要求的鍵(沒有 `spiralCenter` 也行)一定寫出,降版後照樣讀得到(§4.3 第 7 點)。
    func testExplorationSnapshotRoundTripsAndKeepsTheKeysThat068Needs() throws {
        let suiteName = "gflyer.serpentine-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActiveSessionStore(defaults: defaults)
        store.save(
            ActiveSessionSnapshot(
                mode: .explore,
                coordinate: GeoCoordinate(latitude: 35.0, longitude: 139.0),
                speedKilometresPerHour: 50,
                explorationCenter: GeoCoordinate(latitude: 34.99, longitude: 139.0),
                explorationState: SerpentineState(segmentIndex: 7, distanceAlongSegmentMetres: 12.25),
                explorationVerticalLengthMetres: 250,
                explorationDirection: .west,
                savedAt: Date()
            )
        )

        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.mode, .explore)
        XCTAssertEqual(restored.explorationCenter, GeoCoordinate(latitude: 34.99, longitude: 139.0))
        XCTAssertEqual(restored.explorationState, SerpentineState(segmentIndex: 7, distanceAlongSegmentMetres: 12.25))
        XCTAssertEqual(restored.explorationVerticalLengthMetres, 250)
        XCTAssertEqual(restored.explorationDirection, .west)

        let data = try XCTUnwrap(defaults.data(forKey: activeSessionKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in [
            "mode", "coordinate", "routePoints", "remainingPoints", "loop", "transition",
            "speedKilometresPerHour", "savedAt",
        ] {
            XCTAssertNotNil(object[key], key)
        }
        XCTAssertEqual(object["explorationDirection"] as? String, "WEST")
    }

    /// §4.3 第 4 點與 §4.2:用之前清理,非有限值不可以一路傳到 `GeoMath.destination`。
    func testResumedExplorationSanitizesSavedValues() {
        let coordinate = GeoCoordinate(latitude: 22.331, longitude: 114.171)
        func resumed(state: SerpentineState?, verticalLength: Double?) -> ExplorationRun {
            ActiveSessionSnapshot(
                mode: .explore,
                coordinate: coordinate,
                speedKilometresPerHour: 19,
                explorationState: state,
                explorationVerticalLengthMetres: verticalLength,
                savedAt: Date()
            ).resumedExploration
        }
        XCTAssertEqual(
            resumed(state: SerpentineState(segmentIndex: -3, distanceAlongSegmentMetres: -10), verticalLength: nil).state,
            SerpentineState()
        )
        for distance in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(
                resumed(state: SerpentineState(segmentIndex: 4, distanceAlongSegmentMetres: distance), verticalLength: nil).state,
                SerpentineState(segmentIndex: 4, distanceAlongSegmentMetres: 0),
                "\(distance)"
            )
        }
        for invalid in [0, -5, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(resumed(state: nil, verticalLength: invalid).verticalLengthMetres, 1_000, "\(invalid)")
        }
        XCTAssertEqual(resumed(state: nil, verticalLength: 50).verticalLengthMetres, 200)
        XCTAssertEqual(resumed(state: nil, verticalLength: 9_000).verticalLengthMetres, 5_000)
        XCTAssertEqual(resumed(state: nil, verticalLength: 1_234.5).verticalLengthMetres, 1_234.5, "範圍內的非整數照用")
        XCTAssertEqual(resumed(state: nil, verticalLength: nil).center, coordinate, "沒有起點就用中斷的位置")
    }

    /// §3.7:Y 預設 1000、夾在 200〜5000;方向預設 EAST。0.6.8 的設定沒有這兩個鍵,解碼成預設值。
    func testExplorationSettingsDefaultsAndLenientDecoding() throws {
        try withLegacyStore(playback: legacyPlayback(travelMode: "模擬移動", pointAction: "繞圈")) { store, _ in
            XCTAssertEqual(store.snapshot.playback.explorationVerticalLengthMetres, 1_000)
            XCTAssertEqual(store.snapshot.playback.explorationDirection, .east)
        }
        let cases: [(json: String, verticalLength: Int, direction: ExplorationDirection)] = [
            (#"{"explorationVerticalLengthMetres": 150, "explorationDirection": "WEST"}"#, 200, .west),
            (#"{"explorationVerticalLengthMetres": 6000, "explorationDirection": "NORTH"}"#, 5_000, .east),
            (#"{"explorationVerticalLengthMetres": "long", "explorationDirection": 1}"#, 1_000, .east),
            (#"{"explorationVerticalLengthMetres": 2300}"#, 2_300, .east),
        ]
        for testCase in cases {
            let decoded = try JSONDecoder().decode(PlaybackSettings.self, from: Data(testCase.json.utf8))
            XCTAssertEqual(decoded.explorationVerticalLengthMetres, testCase.verticalLength, testCase.json)
            XCTAssertEqual(decoded.explorationDirection, testCase.direction, testCase.json)
        }
    }

    /// 新欄位在明確列出的 CodingKeys 裡:存得進去,重開 App 讀得回來。
    func testExplorationSettingsArePersisted() throws {
        let suiteName = "gflyer.serpentine-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var settings = PlaybackSettings()
        settings.explorationVerticalLengthMetres = 2_300
        settings.explorationDirection = .west
        LocalDataStore(defaults: defaults).savePlaybackSettings(settings)

        let restored = LocalDataStore(defaults: defaults).snapshot.playback
        XCTAssertEqual(restored.explorationVerticalLengthMetres, 2_300)
        XCTAssertEqual(restored.explorationDirection, .west)
        let stored = try storedPlayback(in: defaults)
        XCTAssertEqual(stored["explorationVerticalLengthMetres"] as? Int, 2_300)
        XCTAssertEqual(stored["explorationDirection"] as? String, "WEST")
    }

    func testVerticalLengthStepsBy100WithinTheRange() {
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(1_000, by: 1), 1_100)
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(1_000, by: -1), 900)
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(200, by: -1), 200)
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(5_000, by: 1), 5_000)
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(1_000, by: 5), 1_100, "方向只取 -1 / +1")
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(1_000, by: -7), 900)
        XCTAssertEqual(SerpentinePath.adjustedVerticalLength(1_000, by: 0), 1_000)
    }

    /// 沒有在探索時:預覽線從選取點、進度 (0, 0)、設定的 Y 與方向畫;Y 與方向改了立刻存。
    @MainActor
    func testIdleExplorationControlsAndPreview() throws {
        let suiteName = "gflyer.serpentine-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: ActiveSessionStore(defaults: defaults)
        )
        XCTAssertTrue(controller.explorationPreview.isEmpty, "只在探索模式畫")
        controller.setMode(.explore)
        let start = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        controller.select(start)
        XCTAssertFalse(controller.isExploring)
        XCTAssertEqual(controller.explorationStart, start)
        let preview = controller.explorationPreview
        XCTAssertEqual(preview.count, 308, "serpentine-path.json 的 default-v1000-east-from-start")
        XCTAssertEqual(preview.first, start)

        controller.adjustExplorationVerticalLength(by: 1)
        controller.setExplorationDirection(.west)
        XCTAssertEqual(controller.playbackSettings.explorationVerticalLengthMetres, 1_100)
        XCTAssertEqual(controller.playbackSettings.explorationDirection, .west)
        XCTAssertEqual(
            controller.explorationPreview,
            SerpentinePath.preview(current: start, state: SerpentineState(), verticalLengthMetres: 1_100, direction: .west)
        )
        let restored = LocalDataStore(defaults: defaults).snapshot.playback
        XCTAssertEqual(restored.explorationVerticalLengthMetres, 1_100)
        XCTAssertEqual(restored.explorationDirection, .west)

        for _ in 0..<60 { controller.adjustExplorationVerticalLength(by: 1) }
        XCTAssertEqual(controller.playbackSettings.explorationVerticalLengthMetres, 5_000)
        for _ in 0..<60 { controller.adjustExplorationVerticalLength(by: -1) }
        XCTAssertEqual(controller.playbackSettings.explorationVerticalLengthMetres, 200)
    }

    /// §3.9:三平台一字不差,括號是全形;數字固定照繁體中文地區的樣子。
    func testExplorationTextsMatchAndroid() {
        XCTAssertEqual(ExplorationTexts.idleTitle, "探索中心")
        XCTAssertEqual(ExplorationTexts.activeTitle, "虛擬定位已啟用")
        XCTAssertEqual(ExplorationTexts.widthHint, "預設路線寬度為鳥瞰地圖縮至最遠的寬度")
        XCTAssertEqual(ExplorationTexts.horizontalSpacing, "X 固定 530 米")
        XCTAssertEqual(ExplorationTexts.verticalLengthLabel, "Y")
        XCTAssertEqual(ExplorationTexts.decreaseVerticalLength, "減少 Y 值 100 米")
        XCTAssertEqual(ExplorationTexts.increaseVerticalLength, "增加 Y 值 100 米")
        XCTAssertEqual(ExplorationTexts.startButton, "開始探索")
        XCTAssertEqual(ExplorationTexts.exploring, "正在蛇形探索")
        XCTAssertEqual(ExplorationDirection.allCases.map(\.label), ["左\u{FF08}西\u{FF09}", "右\u{FF08}東\u{FF09}"])
        XCTAssertEqual(ExplorationTexts.verticalLength(200), "200 米")
        XCTAssertEqual(ExplorationTexts.verticalLength(1_000), "1,000 米")
        XCTAssertEqual(ExplorationTexts.verticalLength(5_000), "5,000 米")
        XCTAssertEqual(ExplorationTexts.verticalLength(1_234_567), "1,234,567 米")
        XCTAssertEqual(ExplorationTexts.previewDistance(verticalLengthMetres: 200), "預覽 4.12 公里")
        XCTAssertEqual(ExplorationTexts.previewDistance(verticalLengthMetres: 1_000), "預覽 12.12 公里")
        XCTAssertEqual(ExplorationTexts.previewDistance(verticalLengthMetres: 5_000), "預覽 52.12 公里")
    }
}
