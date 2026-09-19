import UIKit
import XCTest
@testable import GFlyerIOS

@MainActor
final class OneHandedZoomDisablerTests: XCTestCase {
    /// 名字和 MapKit 的 `_MKOneHandedZoomGestureRecognizer` 一樣含 OneHandedZoom。
    private final class FakeOneHandedZoomRecognizer: UIGestureRecognizer { }

    func testDisablesOnlyOneHandedZoomAnywhereInTheHierarchy() {
        let root = UIView()
        let map = UIView()
        let content = UIView()
        root.addSubview(map)
        map.addSubview(content)

        let oneHanded = FakeOneHandedZoomRecognizer()
        let pan = UIPanGestureRecognizer()
        let pinch = UIPinchGestureRecognizer()
        let doubleTap = UITapGestureRecognizer()
        doubleTap.numberOfTapsRequired = 2
        content.addGestureRecognizer(oneHanded)
        content.addGestureRecognizer(pan)
        map.addGestureRecognizer(pinch)
        map.addGestureRecognizer(doubleTap)

        XCTAssertEqual(OneHandedZoomDisabler.disableOneHandedZoom(in: root), 1)
        XCTAssertFalse(oneHanded.isEnabled)
        XCTAssertTrue(pan.isEnabled, "拖動地圖不能被關掉")
        XCTAssertTrue(pinch.isEnabled, "雙指縮放不能被關掉")
        XCTAssertTrue(doubleTap.isEnabled, "雙擊放大不能被關掉")

        // 再掃一次不會重複計算
        XCTAssertEqual(OneHandedZoomDisabler.disableOneHandedZoom(in: root), 0)

        // 地圖自己重建版面時會把手勢啟用回來，之後每次掃描都要再關一次
        oneHanded.isEnabled = true
        XCTAssertEqual(OneHandedZoomDisabler.disableOneHandedZoom(in: root), 1)
        XCTAssertFalse(oneHanded.isEnabled)
    }

    func testCollectFindsEveryOneHandedZoomRecognizer() {
        let root = UIView()
        let branch = UIView()
        root.addSubview(branch)
        root.addGestureRecognizer(FakeOneHandedZoomRecognizer())
        branch.addGestureRecognizer(FakeOneHandedZoomRecognizer())
        branch.addGestureRecognizer(UIPinchGestureRecognizer())

        var found: [UIGestureRecognizer] = []
        OneHandedZoomDisabler.collectOneHandedZoom(in: root, into: &found)
        XCTAssertEqual(found.count, 2)
    }

    func testNothingHappensWhenTheGestureIsAbsent() {
        let root = UIView()
        let pan = UIPanGestureRecognizer()
        root.addGestureRecognizer(pan)
        XCTAssertEqual(OneHandedZoomDisabler.disableOneHandedZoom(in: root), 0)
        XCTAssertTrue(pan.isEnabled)
    }
}
