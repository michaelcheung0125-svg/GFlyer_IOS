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
            sessionStore: ActiveSessionStore(defaults: defaults)
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
}
