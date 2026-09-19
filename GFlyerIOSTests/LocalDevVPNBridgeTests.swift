import UIKit
import XCTest
@testable import GFlyerIOS

@MainActor
final class LocalDevVPNBridgeTests: XCTestCase {
    /// 路由查詢與 App 切換都換成可控制的假物件，測試不碰真正的網卡或 LocalDevVPN。
    private final class Harness {
        var tunnelUp = false
        var installed = true
        var openSucceeds = true
        var openedURLs: [URL] = []
        let center = NotificationCenter()
        let defaults: UserDefaults
        private let suite: String

        init() {
            let suite = "gflyer.localdevvpn-tests.\(UUID().uuidString)"
            self.suite = suite
            defaults = UserDefaults(suiteName: suite)!
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suite) }

        /// 模擬「切去 LocalDevVPN，再回到 GFlyer」。
        func leaveAndReturn() {
            center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }

    private func makeBridge(_ harness: Harness, pollAttempts: Int = 3) -> LocalDevVPNBridge {
        LocalDevVPNBridge(
            defaults: harness.defaults,
            notificationCenter: harness.center,
            routeCheck: { _ in harness.tunnelUp },
            canOpen: { _ in harness.installed },
            openURL: { url in
                harness.openedURLs.append(url)
                return harness.openSucceeds
            },
            pollAttempts: pollAttempts,
            pollIntervalNanoseconds: 1_000_000
        )
    }

    /// 等 perform 真的送出要求（已跳去 LocalDevVPN）再模擬回到前景。
    private func waitUntilSwitching(_ bridge: LocalDevVPNBridge, _ harness: Harness) async {
        var spins = 0
        while !(bridge.isSwitching && !harness.openedURLs.isEmpty), spins < 100 {
            spins += 1
            await Task.yield()
        }
        XCTAssertTrue(bridge.isSwitching)
    }

    // MARK: - 網址

    func testURLsAskLocalDevVPNToReturnToGFlyer() throws {
        let enable = try XCTUnwrap(LocalDevVPNBridge.url(for: .connect))
        XCTAssertEqual(enable.absoluteString, "localdevvpn://enable?scheme=gflyer")
        let disable = try XCTUnwrap(LocalDevVPNBridge.url(for: .disconnect))
        XCTAssertEqual(disable.absoluteString, "localdevvpn://disable?scheme=gflyer")
    }

    // MARK: - 路由檢查

    func testTunnelInterfaceNames() {
        XCTAssertTrue(LocalDevVPNBridge.isTunnelInterface("utun4"))
        XCTAssertTrue(LocalDevVPNBridge.isTunnelInterface("ipsec0"))
        XCTAssertFalse(LocalDevVPNBridge.isTunnelInterface("en0"))
        XCTAssertFalse(LocalDevVPNBridge.isTunnelInterface("pdp_ip0"))
        XCTAssertFalse(LocalDevVPNBridge.isTunnelInterface("lo0"))
    }

    func testRouteCheckRejectsInvalidAndNonTunnelDestinations() {
        XCTAssertFalse(LocalDevVPNBridge.routesThroughTunnel(deviceIP: "not an ip"))
        XCTAssertFalse(LocalDevVPNBridge.routesThroughTunnel(deviceIP: ""))
        // 本機回送位址一定走 lo0，不是 VPN 介面
        XCTAssertFalse(LocalDevVPNBridge.routesThroughTunnel(deviceIP: "127.0.0.1"))
    }

    // MARK: - 設定

    func testSettingsDefaultsAndPersistence() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let bridge = makeBridge(harness)
        XCTAssertTrue(bridge.autoConnectOnStart, "預設要自動開啟，使用者才不用做任何設定")
        XCTAssertFalse(bridge.disconnectAfterFullClear, "預設不關 VPN，避免下次開始又要重建通道")

        bridge.autoConnectOnStart = false
        bridge.disconnectAfterFullClear = true
        let restored = makeBridge(harness)
        XCTAssertFalse(restored.autoConnectOnStart)
        XCTAssertTrue(restored.disconnectAfterFullClear)
    }

    func testNeedsConnectOnlyWhenTunnelDownInstalledAndEnabled() {
        let harness = Harness()
        defer { harness.cleanUp() }
        let bridge = makeBridge(harness)
        XCTAssertTrue(bridge.needsConnectBeforeStart())

        harness.tunnelUp = true
        XCTAssertFalse(bridge.needsConnectBeforeStart(), "VPN 已開就直接開始")
        XCTAssertTrue(bridge.isTunnelUp)

        harness.tunnelUp = false
        harness.installed = false
        XCTAssertFalse(bridge.needsConnectBeforeStart(), "沒裝 LocalDevVPN 時照舊開始，由連線錯誤提示接手")

        harness.installed = true
        bridge.autoConnectOnStart = false
        XCTAssertFalse(bridge.needsConnectBeforeStart())
    }

    // MARK: - 開關流程

    func testConnectSucceedsAfterReturningWithTunnelUp() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let bridge = makeBridge(harness)
        let result = Task { await bridge.perform(.connect) }
        await waitUntilSwitching(bridge, harness)
        XCTAssertEqual(harness.openedURLs.last?.absoluteString, "localdevvpn://enable?scheme=gflyer")

        harness.tunnelUp = true
        harness.leaveAndReturn()

        let reached = await result.value
        XCTAssertTrue(reached)
        XCTAssertTrue(bridge.isTunnelUp)
        XCTAssertFalse(bridge.isSwitching)
    }

    func testDisconnectSucceedsAfterReturningWithTunnelDown() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.tunnelUp = true
        let bridge = makeBridge(harness)
        let result = Task { await bridge.perform(.disconnect) }
        await waitUntilSwitching(bridge, harness)
        XCTAssertEqual(harness.openedURLs.last?.absoluteString, "localdevvpn://disable?scheme=gflyer")

        harness.tunnelUp = false
        harness.leaveAndReturn()

        let reached = await result.value
        XCTAssertTrue(reached)
        XCTAssertFalse(bridge.isTunnelUp)
    }

    func testReturningWithoutChangeTimesOut() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let bridge = makeBridge(harness, pollAttempts: 2)
        let result = Task { await bridge.perform(.connect) }
        await waitUntilSwitching(bridge, harness)

        harness.leaveAndReturn()

        let reached = await result.value
        XCTAssertFalse(reached)
        XCTAssertFalse(bridge.isSwitching)
    }

    func testFailedOpenEndsImmediately() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.openSucceeds = false
        let bridge = makeBridge(harness)
        let reached = await bridge.perform(.connect)
        XCTAssertFalse(reached)
        XCTAssertFalse(bridge.isSwitching)
    }

    func testBecomingActiveWithoutLeavingDoesNotSettle() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let bridge = makeBridge(harness)
        let result = Task { await bridge.perform(.connect) }
        await waitUntilSwitching(bridge, harness)

        // 例如拉下控制中心再收起：沒有進背景，不算從 LocalDevVPN 回來
        harness.tunnelUp = true
        harness.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(bridge.isSwitching)

        harness.leaveAndReturn()
        let reached = await result.value
        XCTAssertTrue(reached)
    }

    func testNewRequestEndsThePreviousOne() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let bridge = makeBridge(harness)
        let first = Task { await bridge.perform(.connect) }
        await waitUntilSwitching(bridge, harness)

        let second = Task { await bridge.perform(.connect) }
        // 舊要求只會在新要求開始時結束，所以等到這裡新要求一定已經在等結果
        let firstReached = await first.value
        XCTAssertFalse(firstReached, "被新要求取代的舊要求要以失敗結束，不能永遠等下去")

        harness.tunnelUp = true
        harness.leaveAndReturn()
        let secondReached = await second.value
        XCTAssertTrue(secondReached)
    }
}
