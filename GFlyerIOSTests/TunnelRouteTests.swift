import XCTest
@testable import GFlyerIOS

/// 本機通道的路由檢查（`TunnelRoute`），兩個版本共用。
final class TunnelRouteTests: XCTestCase {
    func testTunnelInterfaceNames() {
        XCTAssertTrue(TunnelRoute.isTunnelInterface("utun4"))
        XCTAssertTrue(TunnelRoute.isTunnelInterface("ipsec0"))
        XCTAssertFalse(TunnelRoute.isTunnelInterface("en0"))
        XCTAssertFalse(TunnelRoute.isTunnelInterface("pdp_ip0"))
        XCTAssertFalse(TunnelRoute.isTunnelInterface("lo0"))
    }

    func testRouteCheckRejectsInvalidAndNonTunnelDestinations() {
        XCTAssertFalse(TunnelRoute.routesThroughTunnel(deviceIP: "not an ip"))
        XCTAssertFalse(TunnelRoute.routesThroughTunnel(deviceIP: ""))
        // 本機回送位址一定走 lo0，不是 VPN 介面
        XCTAssertFalse(TunnelRoute.routesThroughTunnel(deviceIP: "127.0.0.1"))
    }
}
