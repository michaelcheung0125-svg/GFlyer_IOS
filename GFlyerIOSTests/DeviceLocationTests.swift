import XCTest
@testable import GFlyerIOS

@MainActor
final class DeviceLocationTests: XCTestCase {
    /// 定位請求只接受「按下按鈕之後」產生的定位，避免 requestLocation 先回
    /// 一筆快取的舊定位——模擬剛結束時，那筆快取正是殘留的模擬座標。
    func testFreshFixRejectsCachedBeforeRequest() {
        let started = Date(timeIntervalSince1970: 1_000_000)
        // 請求開始前 5 秒產生的快取定位：拒絕
        XCTAssertFalse(DeviceLocationService.isFreshFix(
            timestamp: started.addingTimeInterval(-5),
            requestStartedAt: started
        ))
        // 請求開始後產生的新定位：接受
        XCTAssertTrue(DeviceLocationService.isFreshFix(
            timestamp: started.addingTimeInterval(0.5),
            requestStartedAt: started
        ))
        // 剛好在請求開始瞬間：接受
        XCTAssertTrue(DeviceLocationService.isFreshFix(
            timestamp: started,
            requestStartedAt: started
        ))
        // 請求開始前 0.5 秒仍接受（留 1 秒時鐘誤差），前 2 秒則拒絕
        XCTAssertTrue(DeviceLocationService.isFreshFix(
            timestamp: started.addingTimeInterval(-0.5),
            requestStartedAt: started
        ))
        XCTAssertFalse(DeviceLocationService.isFreshFix(
            timestamp: started.addingTimeInterval(-2),
            requestStartedAt: started
        ))
    }
}
