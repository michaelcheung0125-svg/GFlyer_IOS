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
        XCTAssertEqual(sanitized.orbitRadiiMetres, [500, 5, 30, 40])
        // 非選項值取最接近的選項（例如 Android 備份帶來的自訂分鐘數）
        XCTAssertEqual(sanitized.startDelaySeconds, 5)
        XCTAssertEqual(sanitized.autoStopMinutes, 30)

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
