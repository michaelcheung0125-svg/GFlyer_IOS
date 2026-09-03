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
        XCTAssertEqual(assist.shortcutName, AirplaneAssistController.defaultShortcutName)
        XCTAssertFalse(assist.isAutomationEnabled, "預設不啟用：使用者要先自己建好捷徑")
        XCTAssertTrue(assist.autoDisableAfterStart)

        assist.shortcutName = "我的飛航切換"
        assist.isAutomationEnabled = true
        assist.autoDisableAfterStart = false

        let restored = makeController(defaults)
        XCTAssertEqual(restored.shortcutName, "我的飛航切換")
        XCTAssertTrue(restored.isAutomationEnabled)
        XCTAssertFalse(restored.autoDisableAfterStart)
    }
}
