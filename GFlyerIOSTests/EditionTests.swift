import XCTest
@testable import GFlyerIOS

/// 兩個版本的 test target 都跑：每個版本的 Info.plist 要和它自己的 `Edition` 一致。
final class EditionTests: XCTestCase {
    func testInfoPlistRegistersTheEditionCallbackScheme() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(schemes, [Edition.callbackScheme])
        XCTAssertEqual(ShortcutBridge.callbackScheme, Edition.callbackScheme)
    }

    /// 版本號寫在 `project.yml`，Info.plist 的 `$(MARKETING_VERSION)` 要在建置時展開。
    func testVersionComesFromTheBuildSettings() throws {
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertNotNil(version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression), version)
        XCTAssertNotNil(Int(build), build)
    }
}
