import XCTest
@testable import GFlyerIOS

@MainActor
final class AirplaneAssistTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "gflyer.airplane-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    /// 測試要自己控制連線狀態，所以不啟動 NWPathMonitor。
    private func makeController(_ defaults: UserDefaults) -> AirplaneAssistController {
        AirplaneAssistController(defaults: defaults, startsMonitoring: false)
    }

    // MARK: - 步驟推導

    func testStepDerivesFromConnectionAndSimulationState() {
        func step(_ connection: AirplaneAssistController.Connection, _ isSimulating: Bool)
            -> AirplaneAssistController.Step {
            AirplaneAssistController.step(connection: connection, isSimulating: isSimulating)
        }
        XCTAssertEqual(step(.cellular, false), .turnOnAirplane)
        XCTAssertEqual(step(.wifi, false), .turnOnAirplane)
        XCTAssertEqual(step(.unknown, false), .turnOnAirplane)
        XCTAssertEqual(step(.offline, false), .startSimulation)
        XCTAssertEqual(step(.offline, true), .turnOffAirplane)
        XCTAssertEqual(step(.cellular, true), .finished)
        XCTAssertEqual(step(.wifi, true), .finished)
    }

    func testConnectionClassification() {
        func classify(_ satisfied: Bool, wifi: Bool, cellular: Bool)
            -> AirplaneAssistController.Connection {
            AirplaneAssistController.connection(
                isSatisfied: satisfied, usesWiFi: wifi, usesCellular: cellular
            )
        }
        XCTAssertEqual(classify(false, wifi: false, cellular: false), .offline)
        XCTAssertEqual(classify(true, wifi: true, cellular: false), .wifi)
        XCTAssertEqual(classify(true, wifi: false, cellular: true), .cellular)
        // 兩者都在時以 Wi-Fi 為準：這時候不需要飛行模式那串操作
        XCTAssertEqual(classify(true, wifi: true, cellular: true), .wifi)
        // 只剩 VPN 之類的介面時不要猜成行動網絡，寧可顯示偵測中
        XCTAssertEqual(classify(true, wifi: false, cellular: false), .unknown)
        XCTAssertTrue(AirplaneAssistController.Connection.cellular.needsAssist)
        XCTAssertFalse(AirplaneAssistController.Connection.wifi.needsAssist)
    }

    // MARK: - 捷徑網址

    func testAirplaneShortcutURLCarriesStateAndCallbacks() throws {
        let url = try XCTUnwrap(
            AirplaneAssistController.airplaneShortcutURL(name: "GFlyer 飛航切換", turnOn: true)
        )
        XCTAssertEqual(url.scheme, "shortcuts")
        XCTAssertEqual(url.host, "x-callback-url")
        XCTAssertEqual(url.path, "/run-shortcut")

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        XCTAssertEqual(value("name"), "GFlyer 飛航切換")
        XCTAssertEqual(value("input"), "text")
        XCTAssertEqual(value("text"), "on")
        XCTAssertEqual(value("x-success"), "gflyer://airplane/on")
        XCTAssertEqual(value("x-error"), "gflyer://airplane/failed")

        let off = try XCTUnwrap(
            AirplaneAssistController.airplaneShortcutURL(name: "GFlyer 飛航切換", turnOn: false)
        )
        let offItems = try XCTUnwrap(URLComponents(url: off, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(offItems.first(where: { $0.name == "text" })?.value, "off")
        XCTAssertEqual(offItems.first(where: { $0.name == "x-success" })?.value, "gflyer://airplane/off")
    }

    // MARK: - 回呼

    func testCallbackHandlesOwnURLsOnly() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let assist = makeController(defaults)

        XCTAssertTrue(assist.handleCallback(try XCTUnwrap(URL(string: "gflyer://airplane/on"))))
        XCTAssertNotNil(assist.lastMessage)
        XCTAssertTrue(assist.handleCallback(try XCTUnwrap(URL(string: "gflyer://airplane/off"))))

        for text in [
            "gflyer://steps/done",
            "gflyer://airplane/unknown",
            "https://example.com/airplane/on",
        ] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertFalse(assist.handleCallback(url), text)
        }
    }

    func testFailedCallbackDisarmsAutoDisable() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let assist = makeController(defaults)
        assist.armAutoDisable()

        XCTAssertTrue(assist.handleCallback(try XCTUnwrap(URL(string: "gflyer://airplane/failed"))))
        XCTAssertNotNil(assist.lastError)

        // 切換失敗後就不該還等著自動關閉，否則之後會莫名其妙跳去捷徑
        assist.updateConnection(.offline)
        XCTAssertFalse(assist.simulationDidActivate())
    }

    // MARK: - 自動關閉

    func testAutoDisableRequiresArmingAndOfflineState() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let assist = makeController(defaults)
        assist.isAutomationEnabled = true
        assist.updateConnection(.offline)

        // 沒按過輔助畫面的「開始模擬」時，任何模擬開始都不該去動飛行模式
        XCTAssertFalse(assist.simulationDidActivate())

        assist.armAutoDisable()
        assist.autoDisableAfterStart = false
        XCTAssertFalse(assist.simulationDidActivate(), "使用者關掉自動關閉時不應觸發")

        assist.armAutoDisable()
        assist.autoDisableAfterStart = true
        assist.updateConnection(.wifi)
        XCTAssertFalse(assist.simulationDidActivate(), "已經有網絡時沒有東西要關")
    }

    func testAutoDisableIsConsumedAfterOneActivation() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let assist = makeController(defaults)
        assist.isAutomationEnabled = true
        assist.armAutoDisable()

        assist.updateConnection(.wifi)
        XCTAssertFalse(assist.simulationDidActivate())

        // 上一次已經把武裝狀態消耗掉，之後每次模擬開始都不該再嘗試切換
        assist.updateConnection(.offline)
        XCTAssertFalse(assist.simulationDidActivate())
    }

    // MARK: - 保存

    func testSettingsSurviveRelaunch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let assist = makeController(defaults)
        XCTAssertEqual(assist.turnOnShortcutName, AirplaneAssistController.defaultTurnOnShortcutName)
        XCTAssertEqual(assist.turnOffShortcutName, AirplaneAssistController.defaultTurnOffShortcutName)
        XCTAssertFalse(assist.isAutomationEnabled, "預設不啟用：使用者要先自己建好捷徑")
        XCTAssertTrue(assist.autoDisableAfterStart)

        assist.turnOnShortcutName = "我的飛航開"
        assist.turnOffShortcutName = "我的飛航關"
        assist.isAutomationEnabled = true
        assist.autoDisableAfterStart = false

        let restored = makeController(defaults)
        XCTAssertEqual(restored.turnOnShortcutName, "我的飛航開")
        XCTAssertEqual(restored.turnOffShortcutName, "我的飛航關")
        XCTAssertEqual(restored.shortcutName(turnOn: true), "我的飛航開")
        XCTAssertEqual(restored.shortcutName(turnOn: false), "我的飛航關")
        XCTAssertTrue(restored.isAutomationEnabled)
        XCTAssertFalse(restored.autoDisableAfterStart)
    }

    /// 0.6.0 用單一捷徑加「如果」判斷。已經建好的人升級後不該被要求重建：
    /// 同一個名稱填進兩個方向，那個捷徑照樣能處理開與關。
    func testLegacySingleShortcutNameMigratesToBothDirections() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("GFlyer 飛航切換", forKey: "gflyer.airplane-shortcut-name")

        let assist = makeController(defaults)
        XCTAssertEqual(assist.shortcutName(turnOn: true), "GFlyer 飛航切換")
        XCTAssertEqual(assist.shortcutName(turnOn: false), "GFlyer 飛航切換")

        // 之後個別改過的名稱要蓋過舊值
        assist.turnOffShortcutName = "只改關閉"
        let restored = makeController(defaults)
        XCTAssertEqual(restored.shortcutName(turnOn: true), "GFlyer 飛航切換")
        XCTAssertEqual(restored.shortcutName(turnOn: false), "只改關閉")
    }

    func testBlankNameIsNotTreatedAsConfigured() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let assist = makeController(defaults)
        assist.isAutomationEnabled = true
        assist.turnOffShortcutName = "   "
        XCTAssertEqual(assist.shortcutName(turnOn: false), "")
        XCTAssertFalse(assist.isAutomationReady, "少一個方向就不算設定完成")
    }
}
