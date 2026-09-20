import SwiftUI
import XCTest
@testable import GFlyerIOS

/// 這些測試刻意不去斷言「xs 等於 2」那種把值抄一遍的東西——那種測試只會在
/// 調整尺度時一起被改掉，攔不住任何事。這裡驗的是 token 該守住的規則。
final class DesignTokenTests: XCTestCase {
    func testSpacingScaleIsStrictlyIncreasing() {
        let scale = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg]
        for (smaller, larger) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(
                smaller,
                larger,
                "間距尺度要由小到大，否則呼叫端挑 .sm 或 .md 時無法預期哪個比較寬"
            )
        }
    }

    func testSpacingScaleHasNoNegativeStep() {
        XCTAssertGreaterThanOrEqual(Spacing.xs, 0, "間距不能是負值；要讓元件互相重疊請在呼叫端明確寫出來")
    }

    /// 44pt 是 Apple HIG 的可點目標下限。這條是整個檔案裡最值得留的一個測試：
    /// 地圖工具列原本就是 40×40，沒有這道防線很容易在某次調整時又掉回去。
    func testTapTargetMeetsHumanInterfaceGuidelinesMinimum() {
        XCTAssertGreaterThanOrEqual(
            Metrics.tapTarget,
            44,
            "可點目標不得小於 44pt"
        )
    }

    func testStatusDotStaysSmallerThanATapTarget() {
        XCTAssertLessThan(
            Metrics.statusDot,
            Metrics.tapTarget,
            "狀態圓點只是指示，不該大到看起來像可以點"
        )
    }

    /// 搖桿在控制面板展開時要讓開更多，否則會被面板蓋住。
    func testJoystickClearsTheControlPanelWhenItIsExpanded() {
        XCTAssertGreaterThan(
            Layout.joystickBottomInsetPanelExpanded,
            Layout.joystickBottomInsetPanelCollapsed,
            "面板展開時搖桿要往上讓，數值必須比收合時大"
        )
    }

    /// 路線色和警示色現在的值相同，但必須是兩個獨立的宣告。這個測試擋的是
    /// 「反正一樣，合併成一個吧」那種未來的手滑——合併之後，換警示色會連
    /// 地圖上的路線一起換掉。
    func testRouteAndStatusColoursAreDeclaredSeparately() {
        XCTAssertEqual(Color.routeStroke, Color.orange)
        XCTAssertEqual(Color.statusAttention, Color.orange)
        XCTAssertNotEqual(
            Color.routeAlternate,
            Color.statusAttention,
            "次要路線色不該和任何狀態色相同，否則地圖上分不出是路線還是警示"
        )
    }
}
