import SwiftUI
import XCTest
@testable import GFlyerIOS

final class AppAppearanceTests: XCTestCase {
    /// `.system` 必須對應 `nil`，因為 `preferredColorScheme(nil)` 的意思是
    /// 「不要覆寫」。給它一個具體的 ColorScheme 會把整個 App 釘死在那一邊，
    /// 而且從使用者的角度看會像是「跟隨系統」壞掉了。
    func testSystemMeansNoOverride() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    /// 舊版沒寫過這個鍵，升上來時讀到的是 nil。
    func testMissingPreferenceFallsBackToSystem() {
        XCTAssertEqual(AppAppearance.stored(nil), .system)
    }

    /// 設定值被改壞時不該讓畫面異常，退回跟隨系統就好。
    func testUnknownPreferenceFallsBackToSystem() {
        XCTAssertEqual(AppAppearance.stored("neon"), .system)
        XCTAssertEqual(AppAppearance.stored(""), .system)
    }

    func testEveryCaseSurvivesAStorageRoundTrip() {
        for appearance in AppAppearance.allCases {
            XCTAssertEqual(
                AppAppearance.stored(appearance.rawValue),
                appearance,
                "\(appearance.rawValue) 存進 UserDefaults 之後讀不回原本的選項"
            )
        }
    }

    func testEveryCaseHasALabel() {
        for appearance in AppAppearance.allCases {
            XCTAssertFalse(appearance.label.isEmpty, "\(appearance.rawValue) 沒有可以顯示的名稱")
        }
    }
}
