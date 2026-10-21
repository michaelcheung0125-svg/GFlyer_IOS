import UIKit
import XCTest
@testable import GFlyerIOS

/// 公開版的 `LocalTunnel`。iOS 的 VPN 設定和路由都換成假的，測試不碰真正的網卡。
@MainActor
final class LocalTunnelTests: XCTestCase {
    private struct Failure: LocalizedError {
        var errorDescription: String? { "權限被拒" }
    }

    @MainActor
    private final class FakeSystem: TunnelSystem {
        var connectError: Error?
        var connectedAddresses: [String] = []
        var disconnects = 0
        var onConnect: () -> Void = {}
        var onDisconnect: () -> Void = {}
        /// 設了的話，`connect` 等到它被呼叫才返回。
        var heldConnect: CheckedContinuation<Void, Never>?
        var holdsConnect = false

        func connect(targetAddress: String) async throws {
            connectedAddresses.append(targetAddress)
            if holdsConnect {
                await withCheckedContinuation { heldConnect = $0 }
            }
            if let connectError { throw connectError }
            onConnect()
        }

        func disconnect() async {
            disconnects += 1
            onDisconnect()
        }
    }

    @MainActor
    private final class Harness {
        var tunnelUp = false
        let system = FakeSystem()
        let center = NotificationCenter()
        let defaults: UserDefaults
        private let suite: String

        init() {
            let suite = "gflyer.local-tunnel-tests.\(UUID().uuidString)"
            self.suite = suite
            defaults = UserDefaults(suiteName: suite)!
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    private func makeTunnel(pollAttempts: Int = 3) -> (LocalTunnel, Harness) {
        let harness = Harness()
        let tunnel = LocalTunnel(
            system: harness.system,
            defaults: harness.defaults,
            notificationCenter: harness.center,
            routeCheck: { _ in harness.tunnelUp },
            pollAttempts: pollAttempts,
            pollIntervalNanoseconds: 1_000_000
        )
        return (tunnel, harness)
    }

    func testStartsDirectlyWhenTheTunnelIsUp() {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        harness.tunnelUp = true
        XCTAssertNil(tunnel.statusWhileConnectingBeforeStart())
        harness.tunnelUp = false
        XCTAssertEqual(tunnel.statusWhileConnectingBeforeStart(), "正在開啟本機通道…")
    }

    func testConnectBeforeStartOpensTheTunnelForTheTargetIP() async {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        tunnel.deviceIP = "10.7.0.9"
        harness.system.onConnect = { harness.tunnelUp = true }
        let failure = await tunnel.connectBeforeStart()
        XCTAssertNil(failure)
        XCTAssertEqual(harness.system.connectedAddresses, ["10.7.0.9"])
        XCTAssertTrue(tunnel.isTunnelUp)
        XCTAssertNil(tunnel.switching)
    }

    func testConnectBeforeStartReportsTheSystemError() async throws {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        harness.system.connectError = Failure()
        let failureResult = await tunnel.connectBeforeStart()
        let failure = try XCTUnwrap(failureResult)
        XCTAssertEqual(failure.status, "本機通道尚未連線")
        XCTAssertTrue(failure.message.hasPrefix("無法開啟本機通道：權限被拒\n"), failure.message)
        XCTAssertNil(tunnel.switching)
    }

    func testConnectBeforeStartTimesOutWhenTheRouteNeverChanges() async throws {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        let failureResult = await tunnel.connectBeforeStart()
        let failure = try XCTUnwrap(failureResult)
        XCTAssertEqual(failure.message, LocalTunnel.connectTimeoutMessage)
        XCTAssertFalse(tunnel.isTunnelUp)
    }

    func testRefusesASecondSwitchWhileOneIsRunning() async {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        harness.system.holdsConnect = true
        harness.system.onConnect = { harness.tunnelUp = true }
        let first = Task { await tunnel.perform(connect: true) }
        while harness.system.heldConnect == nil { await Task.yield() }
        XCTAssertEqual(tunnel.switching, true)
        let second = await tunnel.perform(connect: false)
        XCTAssertEqual(second, LocalTunnel.busyMessage)
        XCTAssertEqual(harness.system.disconnects, 0)
        harness.system.heldConnect?.resume()
        let firstResult = await first.value
        XCTAssertNil(firstResult)
    }

    func testDisconnectAfterFullClearOnlyWhenWantedAndUp() async throws {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        harness.tunnelUp = true
        let notWanted = await tunnel.disconnectAfterFullClearIfWanted()
        XCTAssertNil(notWanted)
        XCTAssertEqual(harness.system.disconnects, 0)

        tunnel.disconnectAfterFullClear = true
        harness.system.onDisconnect = { harness.tunnelUp = false }
        let closingResult = await tunnel.disconnectAfterFullClearIfWanted()
        let closing = try XCTUnwrap(closingResult)
        XCTAssertTrue(closing.closed)
        XCTAssertEqual(closing.message, "本機通道已關閉。")

        let alreadyClosed = await tunnel.disconnectAfterFullClearIfWanted()
        XCTAssertNil(alreadyClosed)
        XCTAssertEqual(harness.system.disconnects, 1)
    }

    func testDisconnectAfterFullClearReportsATunnelThatStaysUp() async throws {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        harness.tunnelUp = true
        tunnel.disconnectAfterFullClear = true
        let closingResult = await tunnel.disconnectAfterFullClearIfWanted()
        let closing = try XCTUnwrap(closingResult)
        XCTAssertFalse(closing.closed)
        XCTAssertEqual(closing.message, LocalTunnel.disconnectFailureMessage)
    }

    func testRemembersDisconnectAfterFullClear() {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        XCTAssertFalse(tunnel.disconnectAfterFullClear)
        tunnel.disconnectAfterFullClear = true
        let reopened = LocalTunnel(
            system: harness.system,
            defaults: harness.defaults,
            notificationCenter: harness.center,
            routeCheck: { _ in false }
        )
        XCTAssertTrue(reopened.disconnectAfterFullClear)
    }

    func testRechecksTheRouteWhenGFlyerBecomesActive() {
        let (tunnel, harness) = makeTunnel()
        defer { harness.cleanUp() }
        XCTAssertFalse(tunnel.isTunnelUp)
        harness.tunnelUp = true
        harness.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(tunnel.isTunnelUp)
    }

    func testUsageStepsFollowThePairingFileSteps() {
        XCTAssertEqual(LocalTunnel.usageSteps.map { $0.prefix(2) }, ["3.", "4."])
    }
}
