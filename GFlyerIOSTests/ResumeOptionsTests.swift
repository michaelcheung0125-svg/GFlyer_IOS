import XCTest
@testable import GFlyerIOS

/// 中斷後恢復用被中斷那一趟的到點選項(GFlyer-Suite docs/features/route-arrival-actions.md §3.10、§5.2 I17、§5.4)。
/// `testResumeOptionsMatchTheSharedFixture` 照抄 contracts/fixtures/route/arrival-actions.json 的 resumeOptions;
/// 其餘是 §6 列給 iOS 的單元測試。`resumeInterruptedSession` 在沒有定位授權的測試環境跑不到 `startRoute`,
/// 所以這裡測的是它呼叫的純函式:`ActiveSessionSnapshot.resumedRouteOptions` / `recordedRouteOptions`
/// 與 `RouteArrivalPlan`。
final class ResumeOptionsTests: XCTestCase {
    private let activeSessionKey = "gflyer.active-session.v1"

    /// 要貼近快照的 savedAt(780000000),否則 `load(now:)` 會因為過期(600 秒)而回傳 nil。
    private let snapshotNow = Date(timeIntervalSinceReferenceDate: 780_000_060)

    /// 0.6.9 的路線快照(`PlaybackFeatureTests.testLegacyRouteSnapshotIsUnaffected` 那一份),在 `savedAt`
    /// 前面加上 `extraFields`(例如 `"routeTravelMode":"逐點傳送"`)。沒有 `extraFields` 時就是 0.6.9 寫的樣子。
    private func routeSnapshotJSON(mode: String = "多點", loop: Bool = true, extraFields: [String] = []) -> String {
        let extra = extraFields.map { $0 + "," }.joined()
        return """
        {"mode":"\(mode)","coordinate":{"latitude":22.3,"longitude":114.1},\
        "routePoints":[{"latitude":22.3,"longitude":114.1},{"latitude":22.4,"longitude":114.2}],\
        "remainingPoints":[{"latitude":22.4,"longitude":114.2}],"loop":\(loop),"transition":"直接返回",\
        "speedKilometresPerHour":50,\(extra)"savedAt":780000000}
        """
    }

    private func decodeSnapshot(_ json: String) throws -> ActiveSessionSnapshot {
        try JSONDecoder().decode(ActiveSessionSnapshot.self, from: Data(json.utf8))
    }

    /// 把快照 JSON 放進一個獨立的 UserDefaults,再用它建立 ActiveSessionStore。
    private func withSessionStore(json: String, _ body: (ActiveSessionStore) throws -> Void) throws {
        let suiteName = "gflyer.resume-options-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(json.utf8), forKey: activeSessionKey)
        try body(ActiveSessionStore(defaults: defaults))
    }

    private func settings(
        _ travelMode: RouteTravelMode,
        _ pointAction: RoutePointAction,
        manualAdvance: Bool = false,
        dwellSeconds: Int = 20,
        startDelaySeconds: Int = 10
    ) -> PlaybackSettings {
        var settings = PlaybackSettings()
        settings.travelMode = travelMode
        settings.pointAction = pointAction
        settings.manualAdvance = manualAdvance
        settings.dwellSeconds = dwellSeconds
        settings.startDelaySeconds = startDelaySeconds
        return settings
    }

    private func options(
        _ travelMode: RouteTravelMode,
        _ pointAction: RoutePointAction,
        manualAdvance: Bool,
        dwellSeconds: Int,
        startDelaySeconds: Int = 0
    ) -> RoutePlaybackOptions {
        RoutePlaybackOptions(
            travelMode: travelMode,
            pointAction: pointAction,
            manualAdvance: manualAdvance,
            dwellSeconds: dwellSeconds,
            startDelaySeconds: startDelaySeconds
        )
    }

    // MARK: - contracts/fixtures/route/arrival-actions.json

    /// resumeOptions:快照裡存的四個值(含缺鍵、認不得的值、超出範圍的停留、互相矛盾的組合)→ 恢復時實際用的值。
    /// 每個案例用一份 0.6.9 的路線快照 JSON 加上 `saved` 裡有的鍵,經過 `JSONDecoder`,再用和 `expected` 不同的
    /// 目前設定算 `resumedRouteOptions`:解碼的預設值、「有鍵就不是舊快照」與 §3.10 第 2 步的規則一起驗到。
    /// 跳過只有 android 的 `android-0.8.6-snapshot-without-keys`(四個鍵都沒有的舊快照,iOS 照 0.6.9 的做法,
    /// 由 `testLegacyRouteSnapshotWithoutTheKeysResumesLike069` 驗)。
    func testResumeOptionsMatchTheSharedFixture() throws {
        struct Saved {
            var travelMode: String? = nil
            var pointAction: String? = nil
            var manualAdvance: Bool? = nil
            var dwellSeconds: Int? = nil
        }
        struct ResumeCase {
            let name: String
            let saved: Saved
            let expected: RoutePlaybackOptions
        }
        // fixture 用 Android 的 enum 名稱;iOS 的快照存 rawValue(§5.4)。WARP / DANCE 是認不得的值
        let snapshotValues: [String: String] = [
            "SIMULATE": "模擬移動",
            "TELEPORT": "逐點傳送",
            "WARP": "瞬移",
            "NONE": "無",
            "ORBIT": "繞圈",
            "MICRO_MOVE": "微動",
            "DANCE": "跳舞",
        ]
        // 快照的值就是這兩個 enum 的 rawValue,不可以改(I1)
        XCTAssertEqual(RouteTravelMode.simulate.rawValue, "模擬移動")
        XCTAssertEqual(RouteTravelMode.teleport.rawValue, "逐點傳送")
        XCTAssertEqual(RoutePointAction.none.rawValue, "無")
        XCTAssertEqual(RoutePointAction.orbit.rawValue, "繞圈")
        XCTAssertEqual(RoutePointAction.microMove.rawValue, "微動")
        XCTAssertNil(RouteTravelMode(rawValue: "瞬移"))
        XCTAssertNil(RoutePointAction(rawValue: "跳舞"))

        let cases: [ResumeCase] = [
            ResumeCase(
                name: "teleport-micro-move-dwell-7",
                saved: Saved(travelMode: "TELEPORT", pointAction: "MICRO_MOVE", manualAdvance: false, dwellSeconds: 7),
                expected: options(.teleport, .microMove, manualAdvance: false, dwellSeconds: 7)
            ),
            ResumeCase(
                name: "teleport-orbit-manual-advance",
                saved: Saved(travelMode: "TELEPORT", pointAction: "ORBIT", manualAdvance: true, dwellSeconds: 0),
                expected: options(.teleport, .orbit, manualAdvance: true, dwellSeconds: 0)
            ),
            ResumeCase(
                name: "teleport-legacy-none-keeps-none",
                saved: Saved(travelMode: "TELEPORT", pointAction: "NONE", manualAdvance: false, dwellSeconds: 10),
                expected: options(.teleport, .none, manualAdvance: false, dwellSeconds: 10)
            ),
            ResumeCase(
                name: "plain-walk-from-simulate-single-or-board-route",
                saved: Saved(travelMode: "SIMULATE", pointAction: "NONE", manualAdvance: false, dwellSeconds: 0),
                expected: options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
            ),
            ResumeCase(
                name: "simulate-with-arrival-options-is-cleaned",
                saved: Saved(travelMode: "SIMULATE", pointAction: "ORBIT", manualAdvance: true, dwellSeconds: 10),
                expected: options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
            ),
            ResumeCase(
                name: "teleport-manual-advance-forces-dwell-0",
                saved: Saved(travelMode: "TELEPORT", pointAction: "MICRO_MOVE", manualAdvance: true, dwellSeconds: 10),
                expected: options(.teleport, .microMove, manualAdvance: true, dwellSeconds: 0)
            ),
            ResumeCase(
                name: "teleport-dwell-0-clamped-to-1",
                saved: Saved(travelMode: "TELEPORT", pointAction: "ORBIT", manualAdvance: false, dwellSeconds: 0),
                expected: options(.teleport, .orbit, manualAdvance: false, dwellSeconds: 1)
            ),
            ResumeCase(
                name: "teleport-negative-dwell-clamped-to-1",
                saved: Saved(travelMode: "TELEPORT", pointAction: "ORBIT", manualAdvance: false, dwellSeconds: -5),
                expected: options(.teleport, .orbit, manualAdvance: false, dwellSeconds: 1)
            ),
            ResumeCase(
                name: "teleport-dwell-above-range-clamped-to-300",
                saved: Saved(travelMode: "TELEPORT", pointAction: "ORBIT", manualAdvance: false, dwellSeconds: 999),
                expected: options(.teleport, .orbit, manualAdvance: false, dwellSeconds: 300)
            ),
            ResumeCase(
                name: "unknown-travel-mode-falls-back-to-simulate",
                saved: Saved(travelMode: "WARP", pointAction: "ORBIT", manualAdvance: true, dwellSeconds: 10),
                expected: options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
            ),
            ResumeCase(
                name: "unknown-point-action-falls-back-to-none",
                saved: Saved(travelMode: "TELEPORT", pointAction: "DANCE", manualAdvance: false, dwellSeconds: 10),
                expected: options(.teleport, .none, manualAdvance: false, dwellSeconds: 10)
            ),
            ResumeCase(
                name: "only-travel-mode-saved",
                saved: Saved(travelMode: "TELEPORT"),
                expected: options(.teleport, .none, manualAdvance: false, dwellSeconds: 1)
            ),
            ResumeCase(
                // 只有一個鍵、值認不得:仍然不是舊快照(看鍵在不在,不看值)
                name: "only-unknown-travel-mode-saved",
                saved: Saved(travelMode: "WARP"),
                expected: options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
            ),
        ]
        XCTAssertEqual(cases.count, 13, "fixture 14 個案例,跳過只有 android 的 1 個")

        // 和每個 expected 都不同的目前設定:§6 建議的「模擬移動 + 繞圈 + 停留 20 + 倒數 10」,另加一份定點傳送,
        // 讓 expected 是純模擬移動的案例也驗得出有沒有偷看設定
        let currentSettings = [
            settings(.simulate, .orbit, dwellSeconds: 20, startDelaySeconds: 10),
            settings(.teleport, .orbit, dwellSeconds: 20, startDelaySeconds: 10),
        ]

        for testCase in cases {
            var fields: [String] = []
            if let travelMode = testCase.saved.travelMode {
                let value = try XCTUnwrap(snapshotValues[travelMode], testCase.name)
                fields.append("\"routeTravelMode\":\"\(value)\"")
            }
            if let pointAction = testCase.saved.pointAction {
                let value = try XCTUnwrap(snapshotValues[pointAction], testCase.name)
                fields.append("\"routePointAction\":\"\(value)\"")
            }
            if let manualAdvance = testCase.saved.manualAdvance {
                fields.append("\"routeManualAdvance\":\(manualAdvance)")
            }
            if let dwellSeconds = testCase.saved.dwellSeconds {
                fields.append("\"routeDwellSeconds\":\(dwellSeconds)")
            }
            let snapshot = try decodeSnapshot(routeSnapshotJSON(extraFields: fields))

            // 有鍵的欄位不是 nil(值認不得也一樣),沒有鍵的是 nil
            XCTAssertTrue(snapshot.hasSavedRouteOptions, testCase.name)
            XCTAssertEqual(snapshot.routeTravelMode == nil, testCase.saved.travelMode == nil, testCase.name)
            XCTAssertEqual(snapshot.routePointAction == nil, testCase.saved.pointAction == nil, testCase.name)
            XCTAssertEqual(snapshot.routeManualAdvance == nil, testCase.saved.manualAdvance == nil, testCase.name)
            XCTAssertEqual(snapshot.routeDwellSeconds == nil, testCase.saved.dwellSeconds == nil, testCase.name)

            for current in currentSettings {
                XCTAssertEqual(
                    snapshot.resumedRouteOptions(settings: current),
                    testCase.expected,
                    "\(testCase.name) current=\(current.travelMode)"
                )
            }
        }
    }

    // MARK: - 沒有這幾個鍵的舊快照(§3.10、§6 PlaybackFeatureTests 第 1 點)

    /// 0.6.9 寫的路線快照照樣解得開,四個欄位都是 nil;恢復的選項照 0.6.9 用目前的設定,只是不倒數
    /// (Android 的舊快照是純模擬移動;iOS 照 0.6.9 的做法,不會把定點傳送的路線變成「走」的)。
    func testLegacyRouteSnapshotWithoutTheKeysResumesLike069() throws {
        try withSessionStore(json: routeSnapshotJSON()) { store in
            let snapshot = try XCTUnwrap(store.load(now: snapshotNow))
            XCTAssertEqual(snapshot.mode, .multiRoute)
            XCTAssertEqual(snapshot.routePoints.count, 2)
            XCTAssertNil(snapshot.routeTravelMode)
            XCTAssertNil(snapshot.routePointAction)
            XCTAssertNil(snapshot.routeManualAdvance)
            XCTAssertNil(snapshot.routeDwellSeconds)
            XCTAssertFalse(snapshot.hasSavedRouteOptions)

            let teleportOrbit = settings(.teleport, .orbit, manualAdvance: false, dwellSeconds: 5, startDelaySeconds: 10)
            XCTAssertEqual(
                snapshot.resumedRouteOptions(settings: teleportOrbit),
                options(.teleport, .orbit, manualAdvance: false, dwellSeconds: 5)
            )
            let simulate = settings(.simulate, .orbit, manualAdvance: true, dwellSeconds: 5, startDelaySeconds: 10)
            XCTAssertEqual(
                snapshot.resumedRouteOptions(settings: simulate),
                options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
            )
        }

        // 同一份 JSON 把模式改成單點:純模擬移動,不論目前的設定
        let single = try decodeSnapshot(routeSnapshotJSON(mode: "單點"))
        XCTAssertEqual(single.mode, .singleRoute)
        XCTAssertFalse(single.hasSavedRouteOptions)
        XCTAssertEqual(
            single.resumedRouteOptions(settings: settings(.teleport, .orbit, manualAdvance: true, startDelaySeconds: 10)),
            options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
        )
    }

    // MARK: - 寫快照(§5.4、§6 PlaybackFeatureTests 第 2 點)

    /// 存一份定點傳送 + 繞圈 + 手動前進 + 停留 0 的路線快照再讀回,完全相等;原始 JSON 有四個鍵,
    /// 0.6.8 / 0.6.9 解碼要求的八個鍵也都在(對照 Android `ActiveSessionStoreTest.kt:47-57`)。
    func testRouteSnapshotRoundTripsAndKeepsTheKeysThatOlderVersionsNeed() throws {
        let suiteName = "gflyer.resume-options-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActiveSessionStore(defaults: defaults)
        let a = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        let b = GeoCoordinate(latitude: 22.32, longitude: 114.17)
        let snapshot = ActiveSessionSnapshot(
            mode: .multiRoute,
            coordinate: GeoCoordinate(latitude: 22.3197, longitude: 114.1697),
            routePoints: [a, b],
            remainingPoints: [b],
            loop: true,
            transition: .teleportToStart,
            speedKilometresPerHour: 50,
            routeTravelMode: .teleport,
            routePointAction: .orbit,
            routeManualAdvance: true,
            routeDwellSeconds: 0,
            savedAt: Date(timeIntervalSinceReferenceDate: 780_000_000)
        )
        store.save(snapshot)

        let restored = try XCTUnwrap(store.load(now: snapshotNow))
        XCTAssertEqual(restored, snapshot)

        let data = try XCTUnwrap(defaults.data(forKey: activeSessionKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["routeTravelMode"] as? String, "逐點傳送")
        XCTAssertEqual(object["routePointAction"] as? String, "繞圈")
        XCTAssertEqual(object["routeManualAdvance"] as? Bool, true)
        XCTAssertEqual(object["routeDwellSeconds"] as? Int, 0)
        for key in [
            "mode", "coordinate", "routePoints", "remainingPoints", "loop", "transition",
            "speedKilometresPerHour", "savedAt",
        ] {
            XCTAssertNotNil(object[key], key)
        }

        // 降版:0.6.9 / 0.6.8 只讀自己認得的鍵(八個一律要求存在),多出來的四個鍵被忽略
        let downgraded = try JSONDecoder().decode(Snapshot069.self, from: data)
        XCTAssertEqual(downgraded.mode, .multiRoute)
        XCTAssertEqual(downgraded.routePoints, [a, b])
        XCTAssertEqual(downgraded.remainingPoints, [b])
        XCTAssertTrue(downgraded.loop)
        XCTAssertEqual(downgraded.transition, .teleportToStart)
        XCTAssertEqual(downgraded.speedKilometresPerHour, 50)
    }

    /// 0.6.9 以前的 `ActiveSessionSnapshot` 解碼時一律要求的八個鍵;不認得的鍵忽略(JSONDecoder 的行為)。
    private struct Snapshot069: Decodable {
        let mode: SimulationMode
        let coordinate: GeoCoordinate
        let routePoints: [GeoCoordinate]
        let remainingPoints: [GeoCoordinate]
        let loop: Bool
        let transition: LoopTransitionMode
        let speedKilometresPerHour: Double
        let savedAt: Date
    }

    /// 快照一律寫四個值(I17 第 3 點):路線寫這一趟實際用的;傳送(包括搖桿寫成的傳送快照)、探索,
    /// 或沒有正在播的路線時寫純模擬移動。所以 0.6.10 寫的快照一定不是舊快照。
    func testSnapshotsRecordThisRunsOptionsOnlyForRoutes() throws {
        let playing = options(.teleport, .microMove, manualAdvance: false, dwellSeconds: 7)
        let plainWalk = options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
        XCTAssertEqual(RoutePlaybackOptions.plainWalk, plainWalk)
        XCTAssertEqual(ActiveSessionSnapshot.recordedRouteOptions(mode: .multiRoute, playing: playing), playing)
        XCTAssertEqual(ActiveSessionSnapshot.recordedRouteOptions(mode: .singleRoute, playing: playing), playing)
        XCTAssertEqual(ActiveSessionSnapshot.recordedRouteOptions(mode: .multiRoute, playing: nil), plainWalk)
        XCTAssertEqual(ActiveSessionSnapshot.recordedRouteOptions(mode: .teleport, playing: playing), plainWalk)
        XCTAssertEqual(ActiveSessionSnapshot.recordedRouteOptions(mode: .explore, playing: playing), plainWalk)

        // 傳送快照照樣寫出四個鍵(預設值),JSON 長得和 Android 寫的一樣有這四個鍵
        let recorded = ActiveSessionSnapshot.recordedRouteOptions(mode: .teleport, playing: nil)
        let teleport = ActiveSessionSnapshot(
            mode: .teleport,
            coordinate: GeoCoordinate(latitude: 22.3, longitude: 114.1),
            speedKilometresPerHour: 5,
            routeTravelMode: recorded.travelMode,
            routePointAction: recorded.pointAction,
            routeManualAdvance: recorded.manualAdvance,
            routeDwellSeconds: recorded.dwellSeconds,
            savedAt: Date(timeIntervalSinceReferenceDate: 780_000_000)
        )
        let data = try JSONEncoder().encode(teleport)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["routeTravelMode"] as? String, "模擬移動")
        XCTAssertEqual(object["routePointAction"] as? String, "無")
        XCTAssertEqual(object["routeManualAdvance"] as? Bool, false)
        XCTAssertEqual(object["routeDwellSeconds"] as? Int, 0)
        XCTAssertTrue(try JSONDecoder().decode(ActiveSessionSnapshot.self, from: data).hasSavedRouteOptions)
    }

    // MARK: - 解碼各自寬鬆(§5.4 第 3 點、§6 PlaybackFeatureTests 第 3 點)

    /// 認不得與型別不對:各自退回那一個欄位的預設值(不是 nil),快照沒有丟,其他欄位不變
    /// (對照 Android `ActiveSessionStoreTest.kt:70-78`)。
    func testUnknownOrMistypedRouteOptionsFallBackPerField() throws {
        let fields = [
            "\"routeTravelMode\":\"瞬移\"",
            "\"routePointAction\":7",
            "\"routeManualAdvance\":\"yes\"",
            "\"routeDwellSeconds\":999",
        ]
        try withSessionStore(json: routeSnapshotJSON(extraFields: fields)) { store in
            let snapshot = try XCTUnwrap(store.load(now: snapshotNow), "快照不可以因為一個欄位認不得就整份丟掉")
            XCTAssertEqual(snapshot.routeTravelMode, RouteTravelMode.simulate)
            XCTAssertEqual(snapshot.routePointAction, RoutePointAction.none)
            XCTAssertNotNil(snapshot.routePointAction, "認不得是「無」,不是「沒有這個鍵」")
            XCTAssertEqual(snapshot.routeManualAdvance, false)
            XCTAssertEqual(snapshot.routeDwellSeconds, 300)
            XCTAssertTrue(snapshot.hasSavedRouteOptions)
            // 其他欄位不變
            let legacy = try decodeSnapshot(routeSnapshotJSON())
            XCTAssertEqual(snapshot.mode, legacy.mode)
            XCTAssertEqual(snapshot.coordinate, legacy.coordinate)
            XCTAssertEqual(snapshot.routePoints, legacy.routePoints)
            XCTAssertEqual(snapshot.remainingPoints, legacy.remainingPoints)
            XCTAssertEqual(snapshot.loop, legacy.loop)
            XCTAssertEqual(snapshot.transition, legacy.transition)
            XCTAssertEqual(snapshot.speedKilometresPerHour, legacy.speedKilometresPerHour)
            XCTAssertEqual(snapshot.savedAt, legacy.savedAt)
        }

        // iOS 的 JSONDecoder 不轉換型別(Android 會轉成 true、45,§3.10 第 1 步;實際不會遇到)
        let strings = try decodeSnapshot(
            routeSnapshotJSON(extraFields: ["\"routeManualAdvance\":\"true\"", "\"routeDwellSeconds\":\"45\""])
        )
        XCTAssertEqual(strings.routeManualAdvance, false)
        XCTAssertEqual(strings.routeDwellSeconds, 0)
        XCTAssertNil(strings.routeTravelMode)
        XCTAssertNil(strings.routePointAction)

        // JSON 的 null 也是「鍵在、值認不得」:那一個欄位的預設值
        let nulls = try decodeSnapshot(
            routeSnapshotJSON(extraFields: [
                "\"routeTravelMode\":null",
                "\"routePointAction\":null",
                "\"routeManualAdvance\":null",
                "\"routeDwellSeconds\":null",
            ])
        )
        XCTAssertEqual(nulls.routeTravelMode, RouteTravelMode.simulate)
        XCTAssertEqual(nulls.routePointAction, RoutePointAction.none)
        XCTAssertEqual(nulls.routeManualAdvance, false)
        XCTAssertEqual(nulls.routeDwellSeconds, 0)
        XCTAssertEqual(
            nulls.resumedRouteOptions(settings: settings(.teleport, .orbit)),
            options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
        )

        // 負的停留解碼時夾到 0
        let negative = try decodeSnapshot(routeSnapshotJSON(extraFields: ["\"routeDwellSeconds\":-5"]))
        XCTAssertEqual(negative.routeDwellSeconds, 0)
    }

    // MARK: - 恢復的整圈與第一圈(§6 PlaybackFeatureTests 第 4、5 點)

    /// §5.4 那份 JSON:走回起點循環的 A → B → C,在 B、C 之間中斷,這一趟是定點傳送 + 向東走 20 米、停留 7 秒。
    /// 恢復的選項和目前的設定無關;整圈到第 2、3、1 點,第一圈到第 3、1 點,每一段都停留 7 秒再微動
    /// (對照 Android `SessionResumeTest.kt:53-83`)。
    func testResumedLapUsesTheSnapshotsOptions() throws {
        let json = """
        {"mode":"多點","coordinate":{"latitude":22.3205,"longitude":114.1705},\
        "routePoints":[{"latitude":22.3193,"longitude":114.1694},{"latitude":22.32,"longitude":114.17},\
        {"latitude":22.321,"longitude":114.171}],\
        "remainingPoints":[{"latitude":22.321,"longitude":114.171},{"latitude":22.3193,"longitude":114.1694}],\
        "loop":true,"transition":"走回起點","speedKilometresPerHour":50,\
        "routeTravelMode":"逐點傳送","routePointAction":"微動","routeManualAdvance":false,"routeDwellSeconds":7,\
        "savedAt":780000000}
        """
        let a = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        let b = GeoCoordinate(latitude: 22.32, longitude: 114.17)
        let c = GeoCoordinate(latitude: 22.321, longitude: 114.171)
        let interruption = GeoCoordinate(latitude: 22.3205, longitude: 114.1705)
        try withSessionStore(json: json) { store in
            let snapshot = try XCTUnwrap(store.load(now: snapshotNow))
            XCTAssertEqual(snapshot.routePoints, [a, b, c])
            XCTAssertEqual(snapshot.transition, .walkBack)

            let expected = options(.teleport, .microMove, manualAdvance: false, dwellSeconds: 7)
            for current in [
                settings(.simulate, .orbit, startDelaySeconds: 10),
                settings(.teleport, .orbit, manualAdvance: true, startDelaySeconds: 10),
                PlaybackSettings(),
            ] {
                XCTAssertEqual(snapshot.resumedRouteOptions(settings: current), expected)
            }
            let resumed = snapshot.resumedRouteOptions(settings: settings(.simulate, .orbit, startDelaySeconds: 10))
            let loop = RoutePlaybackOptions.loops(for: snapshot.resumedRouteStartKind, requested: snapshot.loop)
            XCTAssertTrue(loop)

            let lap = RouteArrivalPlan.playbackLap(
                points: snapshot.routePoints,
                loop: loop,
                transition: snapshot.transition,
                options: resumed
            )
            XCTAssertEqual(lap.map(\.leg.to), [2, 3, 1])
            let firstLap = RouteArrivalPlan.resumedLap(
                [snapshot.coordinate] + snapshot.remainingPoints,
                aligningTo: lap
            )
            XCTAssertEqual(firstLap.map(\.leg.to), [3, 1])
            XCTAssertEqual(firstLap.map(\.start), [interruption, c])
            XCTAssertEqual(firstLap.map(\.end), [c, a])
            let teleportStep = RouteArrivalSteps(dwellSeconds: 7, action: .microMove, waitsForManualAdvance: false)
            for leg in lap + firstLap {
                XCTAssertEqual(leg.leg.travelMode, .teleport)
                XCTAssertEqual(leg.leg.steps, teleportStep)
                XCTAssertFalse(leg.leg.isFinalStop)
            }
        }
    }

    /// 最後一段照原路線(對照 Android `SessionResumeTest.kt:85-95`):A → B → C → D 不循環、剩 D,存的是
    /// 定點傳送 + 繞圈 + 手動前進 → 第一圈只有到第 4 點那一段,是最後一段,不等「下一點」。
    func testResumedFinalLegKeepsTheOriginalRoutesNumbering() {
        let a = GeoCoordinate(latitude: 25.0, longitude: 121.5)
        let b = GeoCoordinate(latitude: 25.01, longitude: 121.5)
        let c = GeoCoordinate(latitude: 25.02, longitude: 121.5)
        let d = GeoCoordinate(latitude: 25.03, longitude: 121.5)
        let interruption = GeoCoordinate(latitude: 25.025, longitude: 121.5)
        let snapshot = ActiveSessionSnapshot(
            mode: .multiRoute,
            coordinate: interruption,
            routePoints: [a, b, c, d],
            remainingPoints: [d],
            loop: false,
            transition: .walkBack,
            speedKilometresPerHour: 50,
            routeTravelMode: .teleport,
            routePointAction: .orbit,
            routeManualAdvance: true,
            routeDwellSeconds: 0,
            savedAt: Date(timeIntervalSinceReferenceDate: 780_000_000)
        )
        let resumed = snapshot.resumedRouteOptions(settings: settings(.simulate, .microMove, startDelaySeconds: 10))
        XCTAssertEqual(resumed, options(.teleport, .orbit, manualAdvance: true, dwellSeconds: 0))
        let loop = RoutePlaybackOptions.loops(for: snapshot.resumedRouteStartKind, requested: snapshot.loop)
        XCTAssertFalse(loop)

        let lap = RouteArrivalPlan.playbackLap(points: snapshot.routePoints, loop: loop, transition: .walkBack, options: resumed)
        XCTAssertEqual(lap.map(\.leg.to), [2, 3, 4])
        XCTAssertEqual(lap.map(\.leg.steps.waitsForManualAdvance), [true, true, false])
        let firstLap = RouteArrivalPlan.resumedLap([snapshot.coordinate] + snapshot.remainingPoints, aligningTo: lap)
        XCTAssertEqual(firstLap.count, 1)
        let leg = firstLap.first
        XCTAssertEqual(leg?.leg.to, 4)
        XCTAssertEqual(leg?.leg.isFinalStop, true)
        XCTAssertEqual(leg?.leg.steps, RouteArrivalSteps(dwellSeconds: 0, action: .orbit, waitsForManualAdvance: false))
        XCTAssertEqual(leg?.start, interruption)
        XCTAssertEqual(leg?.end, d)
    }

    // MARK: - 各種開始方式存下的值(§3.10、§6 PlaybackFeatureTests 第 6、7 點)

    /// 留言板路線直接開始:這一趟是純模擬移動(不論使用者的多點設定),快照存的就是它;恢復時目前的設定是
    /// 定點傳送 + 繞圈也仍是純模擬移動、不倒數,而且照快照循環。
    func testBoardRouteDirectStartResumesAsAPlainWalk() throws {
        let teleportOrbit = settings(.teleport, .orbit, manualAdvance: false, dwellSeconds: 5, startDelaySeconds: 10)
        // 按下去的那一刻(`startRoute(kind: .boardRoute)`)用的選項,就是快照要寫的
        let playing = RoutePlaybackOptions.effective(for: .boardRoute, settings: teleportOrbit)
        let recorded = ActiveSessionSnapshot.recordedRouteOptions(mode: .multiRoute, playing: playing)
        XCTAssertEqual(recorded, options(.simulate, .none, manualAdvance: false, dwellSeconds: 0))

        let snapshot = try roundTripped(
            ActiveSessionSnapshot(
                mode: .multiRoute,
                coordinate: GeoCoordinate(latitude: 22.35, longitude: 114.15),
                routePoints: [GeoCoordinate(latitude: 22.3, longitude: 114.1), GeoCoordinate(latitude: 22.4, longitude: 114.2)],
                remainingPoints: [GeoCoordinate(latitude: 22.4, longitude: 114.2)],
                loop: true,
                transition: .walkBack,
                speedKilometresPerHour: 19,
                routeTravelMode: recorded.travelMode,
                routePointAction: recorded.pointAction,
                routeManualAdvance: recorded.manualAdvance,
                routeDwellSeconds: recorded.dwellSeconds,
                savedAt: Date(timeIntervalSinceReferenceDate: 780_000_000)
            )
        )
        XCTAssertEqual(
            snapshot.resumedRouteOptions(settings: teleportOrbit),
            options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
        )
        XCTAssertTrue(RoutePlaybackOptions.loops(for: snapshot.resumedRouteStartKind, requested: snapshot.loop))

        // 只預覽、之後自己按「開始」的照多點模式按「開始」存
        let previewed = RoutePlaybackOptions.effective(for: .multiRoute, settings: teleportOrbit)
        XCTAssertEqual(
            ActiveSessionSnapshot.recordedRouteOptions(mode: .multiRoute, playing: previewed),
            options(.teleport, .orbit, manualAdvance: false, dwellSeconds: 5, startDelaySeconds: 10)
        )
    }

    /// 單點路線的快照(`loop` 是 true、存的是純模擬移動):恢復後不循環、純模擬移動。
    func testSingleRouteSnapshotResumesWithoutLoopingAsAPlainWalk() throws {
        let fields = [
            "\"routeTravelMode\":\"模擬移動\"",
            "\"routePointAction\":\"無\"",
            "\"routeManualAdvance\":false",
            "\"routeDwellSeconds\":0",
        ]
        let snapshot = try decodeSnapshot(routeSnapshotJSON(mode: "單點", loop: true, extraFields: fields))
        XCTAssertEqual(snapshot.mode, .singleRoute)
        XCTAssertTrue(snapshot.loop)
        XCTAssertEqual(snapshot.resumedRouteStartKind, .singleRoute)
        XCTAssertFalse(RoutePlaybackOptions.loops(for: snapshot.resumedRouteStartKind, requested: snapshot.loop))
        XCTAssertEqual(
            snapshot.resumedRouteOptions(settings: settings(.teleport, .orbit, manualAdvance: true, startDelaySeconds: 10)),
            options(.simulate, .none, manualAdvance: false, dwellSeconds: 0)
        )
    }

    // MARK: - 連續中斷兩次(§3.10、I17 第 3 點)

    /// 恢復的那一趟寫的快照存恢復的選項,所以第二次恢復仍是原本的選項;舊快照第一次恢復時用當下的設定算出的
    /// 那一份也寫進之後的快照,第二次恢復不再看設定。
    func testSecondInterruptionKeepsTheOriginalOptions() throws {
        /// 恢復後播放的那一趟寫的下一份快照(`saveSessionSnapshot` 寫 `playingRoute.options`)。
        func nextSnapshot(after snapshot: ActiveSessionSnapshot, playing: RoutePlaybackOptions) throws -> ActiveSessionSnapshot {
            let recorded = ActiveSessionSnapshot.recordedRouteOptions(mode: snapshot.mode, playing: playing)
            var next = snapshot
            next.coordinate = snapshot.routePoints[snapshot.routePoints.count - 1]
            next.routeTravelMode = recorded.travelMode
            next.routePointAction = recorded.pointAction
            next.routeManualAdvance = recorded.manualAdvance
            next.routeDwellSeconds = recorded.dwellSeconds
            return try roundTripped(next)
        }

        // 0.6.10 寫的:定點傳送 + 微動 + 停留 7。兩次恢復之間把設定改成模擬移動、停留 20
        let first = try decodeSnapshot(
            routeSnapshotJSON(extraFields: [
                "\"routeTravelMode\":\"逐點傳送\"",
                "\"routePointAction\":\"微動\"",
                "\"routeManualAdvance\":false",
                "\"routeDwellSeconds\":7",
            ])
        )
        let firstResume = first.resumedRouteOptions(settings: settings(.teleport, .orbit, startDelaySeconds: 10))
        XCTAssertEqual(firstResume, options(.teleport, .microMove, manualAdvance: false, dwellSeconds: 7))
        let second = try nextSnapshot(after: first, playing: firstResume)
        XCTAssertEqual(second.resumedRouteOptions(settings: settings(.simulate, .orbit, startDelaySeconds: 10)), firstResume)

        // 0.6.9 寫的(沒有鍵):第一次照當下的設定(定點傳送 + 繞圈),之後的快照存這一份
        let legacy = try decodeSnapshot(routeSnapshotJSON())
        let legacyResume = legacy.resumedRouteOptions(
            settings: settings(.teleport, .orbit, manualAdvance: false, dwellSeconds: 3, startDelaySeconds: 10)
        )
        XCTAssertEqual(legacyResume, options(.teleport, .orbit, manualAdvance: false, dwellSeconds: 3))
        let afterLegacy = try nextSnapshot(after: legacy, playing: legacyResume)
        XCTAssertTrue(afterLegacy.hasSavedRouteOptions)
        XCTAssertEqual(
            afterLegacy.resumedRouteOptions(settings: settings(.simulate, .none, startDelaySeconds: 5)),
            legacyResume,
            "第二次恢復不再看設定"
        )
    }

    /// 存進 UserDefaults 再讀回的那一份(和 `ActiveSessionStore` 相同的 JSON 編碼)。
    private func roundTripped(_ snapshot: ActiveSessionSnapshot) throws -> ActiveSessionSnapshot {
        try JSONDecoder().decode(ActiveSessionSnapshot.self, from: JSONEncoder().encode(snapshot))
    }

    // MARK: - 恢復提示

    /// 重開 App 時的「恢復上次模擬？」提示拿到的快照帶著這一趟的選項:目前的設定是預設的模擬移動,
    /// 恢復時仍是定點傳送 + 繞圈 + 手動前進,而且不倒數。
    @MainActor
    func testPendingResumeSessionCarriesThisRunsOptions() throws {
        let suiteName = "gflyer.resume-options-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionStore = ActiveSessionStore(defaults: defaults)
        sessionStore.save(
            ActiveSessionSnapshot(
                mode: .multiRoute,
                coordinate: GeoCoordinate(latitude: 22.3, longitude: 114.1),
                routePoints: [GeoCoordinate(latitude: 22.3, longitude: 114.1), GeoCoordinate(latitude: 22.4, longitude: 114.2)],
                remainingPoints: [GeoCoordinate(latitude: 22.4, longitude: 114.2)],
                loop: false,
                transition: .walkBack,
                speedKilometresPerHour: 50,
                routeTravelMode: .teleport,
                routePointAction: .orbit,
                routeManualAdvance: true,
                routeDwellSeconds: 0,
                savedAt: Date()
            )
        )

        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults),
            sessionStore: sessionStore,
            regionLookup: .offline(defaults: defaults)
        )
        XCTAssertEqual(controller.playbackSettings.travelMode, .simulate)
        let pending = try XCTUnwrap(controller.pendingResumeSession)
        XCTAssertEqual(
            pending.resumedRouteOptions(settings: controller.playbackSettings),
            options(.teleport, .orbit, manualAdvance: true, dwellSeconds: 0)
        )
    }
}
