import CoreLocation
import XCTest
@testable import GFlyerIOS

/// 定位檢查頁（GFlyer-Suite docs/features/location-check.md）。期望值照抄
/// `contracts/fixtures/location-check/verdict-and-text.json`，fixture 改了這裏要跟着改。
@MainActor
final class LocationCheckTests: XCTestCase {
    private let pushed = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)

    // MARK: - 結論（fixture 的 verdictCases）

    func testVerdictsMatchTheSharedFixture() {
        let north9 = GeoCoordinate(latitude: 25.033980939, longitude: 121.5645)
        let north12 = GeoCoordinate(latitude: 25.034007919, longitude: 121.5645)
        let north30 = GeoCoordinate(latitude: 25.034169796, longitude: 121.5645)
        let cases: [(name: String, permission: Bool, pushed: GeoCoordinate?, speed: Double, received: ReceivedLocation?, expected: LocationCheckVerdict)] = [
            ("without-permission-asks-for-it-before-anything-else", false, pushed, 0,
             ReceivedLocation(coordinate: pushed, isSimulated: true), .needsPermission),
            ("no-location-yet-while-simulating", true, pushed, 0, nil, .waiting),
            ("no-location-yet-without-simulation", true, nil, 0, nil, .waiting),
            ("simulated-at-the-pushed-point-matches", true, pushed, 0,
             ReceivedLocation(coordinate: pushed, isSimulated: true), .matches),
            ("simulated-9-metres-away-matches", true, pushed, 0,
             ReceivedLocation(coordinate: north9, isSimulated: true), .matches),
            ("simulated-12-metres-away-does-not-match", true, pushed, 0,
             ReceivedLocation(coordinate: north12, isSimulated: true), .mismatch),
            ("moving-7-metres-per-second-widens-the-tolerance-to-31-metres", true, pushed, 7,
             ReceivedLocation(coordinate: north30, isSimulated: true), .matches),
            ("moving-6-metres-per-second-is-28-metres-and-30-is-too-far", true, pushed, 6,
             ReceivedLocation(coordinate: north30, isSimulated: true), .mismatch),
            ("a-negative-speed-counts-as-standing-still", true, pushed, -5,
             ReceivedLocation(coordinate: north9, isSimulated: true), .matches),
            ("the-real-location-while-simulating-does-not-match-even-at-the-same-place", true, pushed, 0,
             ReceivedLocation(coordinate: pushed, isSimulated: false), .mismatch),
            ("not-simulating-and-the-real-location", true, nil, 0,
             ReceivedLocation(coordinate: pushed, isSimulated: false), .realLocation),
            ("not-simulating-but-a-simulated-location", true, nil, 0,
             ReceivedLocation(coordinate: pushed, isSimulated: true), .mockFromElsewhere),
        ]
        XCTAssertEqual(LocationCheck.matchMetres, 10)
        XCTAssertEqual(LocationCheck.movingLagSeconds, 3)
        for testCase in cases {
            XCTAssertEqual(
                LocationCheck.verdict(
                    hasPermission: testCase.permission,
                    pushed: testCase.pushed,
                    movingMetresPerSecond: testCase.speed,
                    received: testCase.received
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    /// fixture 的 verdicts（`text` 和 `iosHint`）與 updatesFailedHint.ios。
    func testVerdictTextsAndIOSHintsMatchTheSharedFixture() {
        let expected: [(LocationCheckVerdict, String, String?)] = [
            (.needsPermission, "需要定位權限才能讀取其他 App 收到的位置", nil),
            (.waiting, "等待位置…", "室內或剛打開時可能要等一下。"),
            (.matches, "其他 App 收到的就是本 App 推送的位置", nil),
            (.realLocation, "現在沒有模擬，收到的是手機的真實位置", nil),
            (.mockFromElsewhere, "本 App 沒有在模擬，但收到的位置仍標示為模擬位置",
             "剛停止時要等幾秒；一直這樣的話，請回到設定頁，按「恢復」的「完整清除模擬定位」。"),
            (.mismatch, "模擬中，但其他 App 收到的不是本 App 推送的位置",
             "剛開始模擬時要等幾秒；一直這樣的話，請按「停止模擬」，再按「傳送到選取的位置」。"),
        ]
        for (verdict, text, hint) in expected {
            XCTAssertEqual(verdict.text, text)
            XCTAssertEqual(verdict.hint, hint, "\(verdict)")
        }
        XCTAssertEqual(LocationCheckText.updatesFailedHint, "iOS 沒有交出位置：可能暫時收不到定位，請到收訊較好的位置再試。")
    }

    // MARK: - 值的寫法（fixture 的 distanceText、accuracyText、ageText）

    func testDistanceIsInMetresBelowOneKilometreAndRoundsHalfUpInKilometres() {
        let cases: [(Double, String)] = [
            (0.2, "0 公尺"), (0.5, "1 公尺"), (999.4, "999 公尺"), (999.5, "1000 公尺"),
            (1_000, "1.0 公里"), (1_250, "1.3 公里"), (12_345, "12.3 公里"),
        ]
        for (metres, text) in cases {
            XCTAssertEqual(LocationCheck.distanceText(metres: metres), text, "\(metres)")
        }
    }

    func testAccuracyIsAPlusMinusInMetresOrADashWhenMissing() {
        XCTAssertEqual(LocationCheck.accuracyText(metres: 4.6), "±5 公尺")
        XCTAssertEqual(LocationCheck.accuracyText(metres: 4.5), "±5 公尺")
        XCTAssertEqual(LocationCheck.accuracyText(metres: 0), "±0 公尺")
        XCTAssertEqual(LocationCheck.accuracyText(metres: nil), "—")
    }

    func testAgeReadsInSecondsMinutesAndHours() {
        let cases: [(Int, String)] = [
            (0, "剛剛"), (1, "1 秒前"), (59, "59 秒前"), (60, "1 分鐘前"), (3_599, "59 分鐘前"), (7_200, "2 小時前"),
        ]
        for (seconds, text) in cases {
            XCTAssertEqual(LocationCheck.ageText(seconds: seconds), text, "\(seconds)")
        }
    }

    /// fixture 的 page.timeText：24 小時制、全形括號；秒數捨去小數，定位的時間在未來時當 0。
    func testTimeTextShowsTheClockTimeAndHowLongAgo() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 14, minute: 5, second: 9)))
        XCTAssertEqual(
            LocationCheck.timeText(timestamp: timestamp, now: timestamp.addingTimeInterval(3.7), timeZone: utc),
            "14:05:09（3 秒前）"
        )
        XCTAssertEqual(
            LocationCheck.timeText(timestamp: timestamp, now: timestamp.addingTimeInterval(-2), timeZone: utc),
            "14:05:09（剛剛）"
        )
    }

    // MARK: - 頁面的字（fixture 的 page）

    func testPageTextsMatchTheSharedFixture() {
        XCTAssertEqual(LocationCheckText.title, "定位檢查")
        XCTAssertEqual(LocationCheckText.entrySubtitle, "看其他 App 現在收到的位置，確認模擬有沒有生效")
        XCTAssertEqual(
            LocationCheckText.intro,
            "這一頁顯示 iOS 現在交給其他 App 的位置，用來確認模擬定位有沒有生效。只在這一頁開著時讀取，不儲存、不傳送。"
        )
        XCTAssertEqual(LocationCheckText.settingsSection, "設定")
        XCTAssertEqual(LocationCheckText.pushingLabel, "本 App 正在推送")
        XCTAssertEqual(LocationCheckText.notPushing, "沒有（現在沒有模擬）")
        XCTAssertEqual(LocationCheckText.receivedSection, "其他 App 收到的位置")
        XCTAssertEqual(
            [LocationCheckText.coordinateLabel, LocationCheckText.accuracyLabel, LocationCheckText.timeLabel,
             LocationCheckText.sourceLabel, LocationCheckText.distanceLabel],
            ["座標", "精度", "時間", "來源", "和推送的位置相距"]
        )
        XCTAssertEqual(LocationCheckText.noValue, "—")
        XCTAssertEqual(LocationCheckText.sourceSimulated, "模擬位置")
        XCTAssertEqual(LocationCheckText.sourceReal, "手機的真實位置")
        XCTAssertEqual(LocationCheckText.grantPermissionButton, "允許定位權限")
        XCTAssertEqual(LocationCheckText.teleportButton, "傳送到選取的位置")
        XCTAssertEqual(LocationCheckText.stopButton, "停止模擬")
        XCTAssertEqual(LocationCheckText.selected(pushed), "選取的位置：25.033900, 121.564500")
        XCTAssertEqual(LocationCheckText.teleportWhileMoving, "請先停止目前的定位模擬，再傳送到選取的位置。")
    }

    // MARK: - CLLocation 轉成頁面的一筆

    func testReaderReadsTheSimulatedFlagAndTreatsNegativeAccuracyAsMissing() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 25.0339, longitude: 121.5645)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let simulated = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 4.6,
            verticalAccuracy: -1,
            course: -1,
            courseAccuracy: -1,
            speed: -1,
            speedAccuracy: -1,
            timestamp: timestamp,
            sourceInfo: CLLocationSourceInformation(softwareSimulationState: true, andExternalAccessoryState: false)
        )
        let simulatedFix = try XCTUnwrap(LocationCheckReader.fix(from: simulated))
        XCTAssertEqual(simulatedFix.received, ReceivedLocation(coordinate: pushed, isSimulated: true))
        XCTAssertEqual(simulatedFix.accuracyMetres, 4.6)
        XCTAssertEqual(simulatedFix.timestamp, timestamp)

        // 沒有 sourceInformation 算真實位置；精度是負的就是沒有給
        let plain = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        let plainFix = try XCTUnwrap(LocationCheckReader.fix(from: plain))
        XCTAssertFalse(plainFix.received.isSimulated)
        XCTAssertNil(plainFix.accuracyMetres)
    }

    func testOnlyWhenInUseAndAlwaysCountAsPermission() {
        XCTAssertTrue(LocationCheckReader.isAuthorized(.authorizedWhenInUse))
        XCTAssertTrue(LocationCheckReader.isAuthorized(.authorizedAlways))
        XCTAssertFalse(LocationCheckReader.isAuthorized(.notDetermined))
        XCTAssertFalse(LocationCheckReader.isAuthorized(.denied))
        XCTAssertFalse(LocationCheckReader.isAuthorized(.restricted))
    }

    // MARK: - SimulationController（規格 3.3 的速度、3.7 的傳送）

    @MainActor
    private final class Harness {
        let controller: SimulationController
        private let defaults: UserDefaults
        private let suite: String

        init() {
            let suite = "gflyer.location-check-tests.\(UUID().uuidString)"
            self.suite = suite
            defaults = UserDefaults(suiteName: suite)!
            controller = SimulationController(
                backend: PreviewLocationSimulationBackend(),
                dataStore: LocalDataStore(defaults: defaults),
                sessionStore: ActiveSessionStore(defaults: defaults),
                regionLookup: .offline(defaults: defaults)
            )
            // 跨日提醒和這裏無關，否則跑測試的時區可能擋住傳送
            controller.updatePlayback { $0.crossDateWarningEnabled = false }
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    func testTeleportToSelectedSwitchesToTeleportWhenNothingIsSimulated() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let controller = harness.controller
        let a = GeoCoordinate(latitude: 25.0, longitude: 121.5)
        let b = GeoCoordinate(latitude: 25.01, longitude: 121.5)
        controller.setMode(.multiRoute)
        controller.select(a)
        controller.select(b)
        XCTAssertEqual(controller.routePoints, [a, b])

        controller.teleportToSelected()
        XCTAssertEqual(controller.mode, .teleport)
        XCTAssertEqual(controller.routePoints, [], "切到定點傳送時清掉路線")
        await waitUntil("傳送到選取的位置") { controller.status.isActive && controller.status.coordinate == b }
        XCTAssertEqual(controller.status.mode, .teleport)
        XCTAssertEqual(controller.movingMetresPerSecond, 0, "定點不動")

        // 已經在定點模擬：換一個選取點再按，就傳送過去
        controller.select(a)
        controller.teleportToSelected()
        await waitUntil("傳送到新的選取點") { controller.status.coordinate == a }
        XCTAssertNil(controller.lastError)
    }

    func testTeleportToSelectedRefusesWhileAnotherModeIsSimulating() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let controller = harness.controller
        XCTAssertEqual(controller.movingMetresPerSecond, 0, "沒有在模擬")
        controller.setMode(.multiRoute)
        controller.select(GeoCoordinate(latitude: 25.0, longitude: 121.5))
        // 搖桿在多點路線模式下推送：`status.mode` 是多點路線
        controller.startJoystick(bearingDegrees: 0)
        defer { controller.stopJoystick() }
        await waitUntil("搖桿開始推送") { controller.status.isActive && controller.movingMetresPerSecond > 0 }

        controller.teleportToSelected()
        XCTAssertEqual(controller.lastError, "請先停止目前的定位模擬，再傳送到選取的位置。")
        XCTAssertEqual(controller.mode, .multiRoute)
    }

    /// 推送與清除都要經過 backend 的 actor 再回到主執行緒，所以照時間等。
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("等不到：\(description)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
