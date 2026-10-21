import XCTest
@testable import GFlyerIOS

/// 超過 20 km/h 的種花提示，對照共用的 contracts/fixtures/speed/preset-speed-values.json 的
/// thresholdCases。照 Android 親友版的 `FlowerSpeedLimitTest`。
final class FlowerSpeedLimitTests: XCTestCase {
    func testWarningStartsAboveTwentyKilometresPerHour() {
        XCTAssertFalse(FlowerSpeedLimit.exceeds(20))
        XCTAssertTrue(FlowerSpeedLimit.exceeds(20.1))
        // 從汽車按 -1 三十次(Android 以 Float 累加)得到 20.000013 km/h,畫面顯示 20.0,不該警告
        XCTAssertFalse(FlowerSpeedLimit.exceeds(20.000013))
    }

    func testSpeedHintIsShownOnlyAboveTheLimit() {
        XCTAssertNil(Edition.speedHint(kilometresPerHour: 20))
        XCTAssertEqual(Edition.speedHint(kilometresPerHour: 50), "注意: 超過 20 km/h 將無法種花")
    }

    /// thresholdCases 的 expectedExceedsFlowerLimit。懸浮鈕圖示的分段在共用的 `SharedContractTests`。
    func testThresholdsMatchTheSharedSpeedFixture() {
        let cases: [(name: String, metresPerSecond: Double, exceeds: Bool)] = [
            ("android-walk-constant", 1.388888955116272, false),
            ("ios-walk-read-back-by-android", 1.3888888359069824, false),
            ("floating-plus-one-up-to-19", 5.277776718139648, false),
            ("floating-minus-one-down-to-19", 5.2777814865112305, false),
            ("android-bicycle-constant", 5.277778148651123, false),
            ("clearly-below-5", 1.3833333333333335, false),
            ("within-tolerance-below-19", 5.2763888888888895, false),
            ("clearly-below-19", 5.273611111111111, false),
            ("android-car-constant", 13.88888931274414, true),
            ("within-tolerance-above-50", 13.890277777777778, true),
            ("clearly-above-50", 13.894444444444446, true),
            ("floating-minus-one-down-to-20", 5.555559158325195, false),
            ("ios-20-read-back-by-android", 5.55555534362793, false),
            ("within-tolerance-above-20", 5.5569444444444445, false),
            ("clearly-above-20", 5.561111111111111, true),
        ]
        for testCase in cases {
            XCTAssertEqual(FlowerSpeedLimit.exceeds(testCase.metresPerSecond * 3.6), testCase.exceeds, testCase.name)
        }
    }
}
