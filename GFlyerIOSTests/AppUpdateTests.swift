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

    /// SideStore／AltStore 用免費 Apple ID 安裝時會在 bundle identifier
    /// 後面加上 team id，執行時的 id 因此比來源檔長一截。0.4.0 用完全相等
    /// 比對，結果永遠回報「已是最新版本」。
    func testParserMatchesResignedBundleIdentifierWithSuffix() throws {
        let data = source(versions: version("0.4.1", build: "7"))
        let update = try AltStoreSourceParser.latestUpdate(
            from: data,
            bundleIdentifier: "\(bundleID).A1B2C3D4E5",
            currentVersion: "0.4.0",
            currentBuild: "6"
        )
        XCTAssertEqual(update?.version, "0.4.1")
    }

    func testMatchingAppPrefersExactThenPrefixThenSoleApp() {
        let target: [String: Any] = ["bundleIdentifier": bundleID]
        let other: [String: Any] = ["bundleIdentifier": "com.example.other"]
        let lookalike: [String: Any] = ["bundleIdentifier": "com.geopilot.gflyer.iosextra"]

        let exact = AltStoreSourceParser.matchingApp(in: [other, target], bundleIdentifier: bundleID)
        XCTAssertEqual(exact?["bundleIdentifier"] as? String, bundleID)

        let prefixed = AltStoreSourceParser.matchingApp(
            in: [other, target],
            bundleIdentifier: "\(bundleID).TEAMID1234"
        )
        XCTAssertEqual(prefixed?["bundleIdentifier"] as? String, bundleID)

        // 點號邊界：com.geopilot.gflyer.iosextra 不可以被當成前綴命中
        XCTAssertNil(AltStoreSourceParser.matchingApp(
            in: [other, lookalike],
            bundleIdentifier: "\(bundleID).TEAMID1234"
        ))

        // 單一 App 的來源檔即使 id 完全對不上也用那一個
        let sole = AltStoreSourceParser.matchingApp(
            in: [target],
            bundleIdentifier: "com.something.totally.different"
        )
        XCTAssertEqual(sole?["bundleIdentifier"] as? String, bundleID)

        // 多個 App 又都對不上時不猜
        XCTAssertNil(AltStoreSourceParser.matchingApp(
            in: [other, lookalike],
            bundleIdentifier: "com.something.totally.different"
        ))
    }

    func testParserIgnoresOtherAppsAndNonHTTPSDownloads() throws {
        let data = source(versions: version("9.9.9", build: "99", url: "http://example.com/a.ipa"))
        // 非 HTTPS 的項目會被略過，於是沒有可用的新版
        XCTAssertNil(try AltStoreSourceParser.latestUpdate(
            from: data, bundleIdentifier: bundleID, currentVersion: "0.3.0", currentBuild: "5"
        ))
        // 多個 App 且都對不上時回傳 nil 而不是報錯。
        // 單一 App 的來源檔會走「就用那一個」的後備，見 matchingApp 的測試。
        let twoApps = Data("""
        {
          "apps": [
            {"bundleIdentifier": "com.example.one", "versions": [\(version("9.9.9", build: "99"))]},
            {"bundleIdentifier": "com.example.two", "versions": [\(version("9.9.9", build: "99"))]}
          ],
          "news": []
        }
        """.utf8)
        XCTAssertNil(try AltStoreSourceParser.latestUpdate(
            from: twoApps,
            bundleIdentifier: bundleID,
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
