import XCTest
@testable import GFlyerIOS

final class AppUpdateTests: XCTestCase {
    private let bundleID = "com.geopilot.gflyer.ios"

    private func source(versions: String) -> Data {
        Data("""
        {
          "name": "GFlyer iOS",
          "apps": [
            {
              "name": "GFlyer",
              "bundleIdentifier": "\(bundleID)",
              "developerName": "GFlyer",
              "localizedDescription": "測試",
              "iconURL": "https://example.com/icon.png",
              "appPermissions": { "entitlements": [], "privacy": {} },
              "versions": [\(versions)]
            }
          ],
          "news": []
        }
        """.utf8)
    }

    private func version(
        _ version: String,
        build: String,
        url: String = "https://example.com/GFlyer.ipa"
    ) -> String {
        """
        {"version":"\(version)","buildVersion":"\(build)","date":"2026-09-01",
         "localizedDescription":"說明","downloadURL":"\(url)",
         "size":123,"minOSVersion":"17.4"}
        """
    }

    // MARK: - 版本比較

    func testVersionOrdering() {
        XCTAssertTrue(AppVersionOrder.isNewer(
            candidateVersion: "0.4.0", candidateBuild: "6",
            thanVersion: "0.3.0", build: "5"
        ))
        // 行銷版本相同時才比 build
        XCTAssertTrue(AppVersionOrder.isNewer(
            candidateVersion: "0.3.0", candidateBuild: "6",
            thanVersion: "0.3.0", build: "5"
        ))
        XCTAssertFalse(AppVersionOrder.isNewer(
            candidateVersion: "0.3.0", candidateBuild: "5",
            thanVersion: "0.3.0", build: "5"
        ))
        // build 較大也不能讓舊的行銷版本變成新版
        XCTAssertFalse(AppVersionOrder.isNewer(
            candidateVersion: "0.2.9", candidateBuild: "99",
            thanVersion: "0.3.0", build: "5"
        ))
        // 缺少的段視為 0
        XCTAssertTrue(AppVersionOrder.isNewer(
            candidateVersion: "0.4", candidateBuild: "1",
            thanVersion: "0.3.9", build: "1"
        ))
        XCTAssertEqual(AppVersionOrder.compare("1.10.0", "1.9.0"), .orderedDescending)
        XCTAssertEqual(AppVersionOrder.compare("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(AppVersionOrder.compare("1.2.3-beta", "1.2.3"), .orderedSame)
    }

    // MARK: - 來源解析

    func testParserReturnsNewestEntryRegardlessOfOrder() throws {
        let data = source(versions: [
            version("0.3.0", build: "5"),
            version("0.5.0", build: "9"),
            version("0.4.0", build: "7"),
        ].joined(separator: ","))
        let update = try AltStoreSourceParser.latestUpdate(
            from: data, bundleIdentifier: bundleID, currentVersion: "0.3.0", currentBuild: "5"
        )
        XCTAssertEqual(update?.version, "0.5.0")
        XCTAssertEqual(update?.buildVersion, "9")
        XCTAssertEqual(update?.minOSVersion, "17.4")
    }

    func testParserReturnsNilWhenUpToDate() throws {
        let data = source(versions: version("0.3.0", build: "5"))
        XCTAssertNil(try AltStoreSourceParser.latestUpdate(
            from: data, bundleIdentifier: bundleID, currentVersion: "0.3.0", currentBuild: "5"
        ))
        XCTAssertNil(try AltStoreSourceParser.latestUpdate(
            from: data, bundleIdentifier: bundleID, currentVersion: "0.9.0", currentBuild: "20"
        ))
    }

    func testParserIgnoresOtherAppsAndNonHTTPSDownloads() throws {
        let data = source(versions: version("9.9.9", build: "99", url: "http://example.com/a.ipa"))
        // 非 HTTPS 的項目會被略過，於是沒有可用的新版
        XCTAssertNil(try AltStoreSourceParser.latestUpdate(
            from: data, bundleIdentifier: bundleID, currentVersion: "0.3.0", currentBuild: "5"
        ))
        // 找不到對應的 bundle identifier 時回傳 nil 而不是報錯
        XCTAssertNil(try AltStoreSourceParser.latestUpdate(
            from: source(versions: version("0.4.0", build: "6")),
            bundleIdentifier: "com.example.other",
            currentVersion: "0.3.0",
            currentBuild: "5"
        ))
    }

    func testParserRejectsMalformedSource() {
        XCTAssertThrowsError(try AltStoreSourceParser.latestUpdate(
            from: Data("not json".utf8),
            bundleIdentifier: bundleID, currentVersion: "0.3.0", currentBuild: "5"
        )) { XCTAssertEqual($0 as? AppUpdateError, .invalidSource) }
        XCTAssertThrowsError(try AltStoreSourceParser.latestUpdate(
            from: Data("{\"news\":[]}".utf8),
            bundleIdentifier: bundleID, currentVersion: "0.3.0", currentBuild: "5"
        )) { XCTAssertEqual($0 as? AppUpdateError, .invalidSource) }
    }

    /// 對照實際發佈的來源檔結構，避免 schema 改動後才在裝置上發現。
    func testParserAcceptsPublishedSourceShape() throws {
        let published = Data("""
        {
          "name": "GFlyer iOS",
          "subtitle": "GFlyer 個人側載來源",
          "iconURL": "https://michaelcheung0125-svg.github.io/GFlyer-updates/icons/gflyer-ios.png",
          "tintColor": "315C83",
          "apps": [
            {
              "name": "GFlyer",
              "bundleIdentifier": "com.geopilot.gflyer.ios",
              "developerName": "GFlyer",
              "subtitle": "地圖定位模擬與路線播放",
              "localizedDescription": "GFlyer iOS 是供個人側載使用的定位模擬工具。",
              "iconURL": "https://michaelcheung0125-svg.github.io/GFlyer-updates/icons/gflyer-ios.png",
              "category": "utilities",
              "appPermissions": { "entitlements": [], "privacy": {} },
              "versions": [
                {
                  "version": "0.3.0",
                  "buildVersion": "5",
                  "date": "2026-09-01",
                  "localizedDescription": "移植 Android 功能。",
                  "downloadURL": "https://github.com/michaelcheung0125-svg/GFlyer-updates/releases/download/ios-v0.3.0/GFlyerIOS-0.3.0-unsigned.ipa",
                  "size": 5470200,
                  "sha256": "2332a708b2838ae69366c456526e62fb0df997a5de6269f7ad5a49a1a37c0a15",
                  "minOSVersion": "17.4"
                }
              ]
            }
          ],
          "news": []
        }
        """.utf8)
        let update = try AltStoreSourceParser.latestUpdate(
            from: published, bundleIdentifier: bundleID, currentVersion: "0.2.0", currentBuild: "4"
        )
        XCTAssertEqual(update?.displayVersion, "0.3.0 (5)")
        XCTAssertEqual(update?.downloadURL.host, "github.com")
        XCTAssertFalse(update?.releaseNotes.isEmpty ?? true)
    }

    // MARK: - 安裝器連結

    func testInstallerDeepLinks() throws {
        let ipa = try XCTUnwrap(URL(string: "https://example.com/GFlyer%20App.ipa"))
        let install = try XCTUnwrap(SideloadInstaller.sideStore.installURL(for: ipa))
        XCTAssertEqual(install.scheme, "sidestore")
        XCTAssertEqual(install.host, "install")
        let query = try XCTUnwrap(URLComponents(url: install, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "url" })?.value)
        XCTAssertEqual(query, ipa.absoluteString)

        let source = try XCTUnwrap(URL(string: "https://example.com/altstore.json"))
        let add = try XCTUnwrap(SideloadInstaller.altStore.addSourceURL(for: source))
        XCTAssertEqual(add.scheme, "altstore")
        XCTAssertEqual(add.host, "source")
    }

    // MARK: - 檢查器

    @MainActor
    func testCheckerReadsBundleValuesAndSnoozesPerDay() {
        let suiteName = "gflyer.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let checker = AppUpdateChecker(defaults: defaults)
        XCTAssertFalse(checker.displayVersion.isEmpty)
        XCTAssertFalse(checker.isSnoozedToday)
        checker.snoozeForToday()
        XCTAssertTrue(checker.isSnoozedToday)
        XCTAssertFalse(checker.showsPrompt)
        XCTAssertTrue(AppUpdateChecker(defaults: defaults).isSnoozedToday)
    }
}
