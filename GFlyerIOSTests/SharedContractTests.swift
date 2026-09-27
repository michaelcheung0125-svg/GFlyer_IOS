import XCTest
@testable import GFlyerIOS

/// 三平台共用的規則。期望值照抄 GFlyer-Suite 的 golden fixture —— iOS 的 CI 拿不到那個 repo,
/// 所以改 fixture 時這裡要跟著改;Android 的測試直接讀同一份 JSON。
final class SharedContractTests: XCTestCase {

    /// contracts/fixtures/text/truncate-names.json(DRIFT D14)
    func testNameTruncationCountsCodePoints() {
        let walker = "\u{1F6B6}"
        let flag = "\u{1F1F9}\u{1F1FC}"
        let cases: [(name: String, input: String, limit: Int, expected: String)] = [
            ("ascii", "abcdefghij", 5, "abcde"),
            ("cjk", "台北一日遊路線", 4, "台北一日"),
            ("emoji-is-one-code-point", "走" + String(repeating: walker, count: 10), 6,
             "走" + String(repeating: walker, count: 5)),
            ("flag-is-two-code-points-and-may-be-split", flag + flag, 3, flag + "\u{1F1F9}"),
            ("combining-mark-is-its-own-code-point", "e\u{0301}e\u{0301}e\u{0301}", 3, "e\u{0301}e"),
            ("shorter-than-limit-is-unchanged", "短", 80, "短"),
            ("exactly-at-limit-is-unchanged", "五個字名稱", 5, "五個字名稱"),
        ]
        for testCase in cases {
            let actual = testCase.input.prefixCodePoints(testCase.limit)
            // String 的 == 用正規等價比較,"e\u{0301}" 和 "é" 會被當成相同;這裡要逐個 code point 比
            XCTAssertEqual(
                actual.unicodeScalars.map(\.value),
                testCase.expected.unicodeScalars.map(\.value),
                testCase.name
            )
        }
        XCTAssertEqual("abc".prefixCodePoints(0), "")
        XCTAssertEqual("abc".prefixCodePoints(-1), "")
    }

    /// contracts/fixtures/settings/auto-stop-minutes.json(DRIFT D15)
    func testAutoStopRoundsToNearestOptionPreferringTheLargerOne() {
        XCTAssertEqual(PlaybackSettings.autoStopOptions, [0, 30, 60, 120])
        let cases: [(minutes: Int, expected: Int)] = [
            (-5, 0), (0, 0), (10, 0), (15, 30), (29, 30), (30, 30), (45, 60),
            (60, 60), (89, 60), (90, 120), (120, 120), (200, 120), (1440, 120), (5000, 120),
        ]
        for testCase in cases {
            XCTAssertEqual(
                PlaybackSettings.nearestAutoStopOption(to: testCase.minutes),
                testCase.expected,
                "minutes=\(testCase.minutes)"
            )
        }
        // 極端值不可以在 abs 裡溢位
        XCTAssertEqual(PlaybackSettings.nearestAutoStopOption(to: .max), 120)
        XCTAssertEqual(PlaybackSettings.nearestAutoStopOption(to: .min), 0)
    }

    /// contracts/fixtures/settings/auto-stop-minutes.json 的 backupValues:備份裡的原始 JSON 值
    /// 還原之後存下來的分鐘數(DRIFT D12、D13、D15)。
    @MainActor
    func testAutoStopValuesInABackupRestoreToTheSharedExpectedMinutes() throws {
        let cases: [(json: String, expected: Int)] = [
            ("15", 30), ("15.0", 30), ("14.9", 0), ("45.5", 60), ("2147483648", 120),
            ("4294967326", 120), ("-2147483649", 0), ("1e20", 120), ("true", 0), ("\"30\"", 0), ("null", 0),
        ]
        for testCase in cases {
            let suiteName = "gflyer.auto-stop-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = LocalDataStore(defaults: defaults)
            var playback = PlaybackSettings()
            playback.autoStopMinutes = 60
            store.savePlaybackSettings(playback)

            let json = #"{"format": "GFlyer Backup", "version": 1, "settings": {"autoStopMinutes": \#(testCase.json)}}"#
            let payload = try AppBackupCodec.decode(Data(json.utf8))
            store.applyBackup(payload)

            XCTAssertEqual(store.snapshot.playback.autoStopMinutes, testCase.expected, "json=\(testCase.json)")
        }
    }

    /// contracts/fixtures/gpx/import-names.json(DRIFT D18)
    @MainActor
    func testGpxImportNamesMatchTheSharedFixture() {
        XCTAssertEqual(SimulationController.gpxImportFallbackName, "匯入路線")
        let road80 = String(repeating: "路", count: 80)
        let road85 = String(repeating: "路", count: 85)
        let road78Numbered = String(repeating: "路", count: 78) + " 2"
        let cases: [(name: String, existing: [String], gpxNames: [String?], expected: [String])] = [
            ("names-come-from-the-gpx", [], ["台北一日遊", "需要 & 跳脫的 <名稱>"], ["台北一日遊", "需要 & 跳脫的 <名稱>"]),
            ("missing-names-use-the-fallback", [], [nil, nil, nil], ["匯入路線", "匯入路線 2", "匯入路線 3"]),
            ("never-overwrites-an-existing-route", ["台北一日遊", "匯入路線"], ["台北一日遊", nil], ["台北一日遊 2", "匯入路線 2"]),
            ("same-name-twice-in-one-import", [], ["Loop", "Loop"], ["Loop", "Loop 2"]),
            ("comparison-ignores-case", ["harbour"], ["Harbour", "HARBOUR"], ["Harbour 2", "HARBOUR 3"]),
            ("long-name-is-truncated", [], [road85], [road80]),
            ("long-name-makes-room-for-the-number", [road80], [road85], [road78Numbered]),
        ]
        for testCase in cases {
            let names = SimulationController.importedRouteNames(
                for: testCase.gpxNames,
                existingLowercased: Set(testCase.existing.map { $0.lowercased() })
            )
            XCTAssertEqual(names, testCase.expected, testCase.name)
        }
    }

    /// contracts/fixtures/gpx/route-names.gpx 與 truncated.gpx(expected.json,DRIFT D18)
    func testGpxParsingMatchesTheSharedFixtures() {
        let routeNames = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GFlyer" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name><![CDATA[Orux Track]]></name>
            <trkseg>
              <trkpt lat="25.0" lon="121.0"><name>點的名稱,不是路線名稱</name></trkpt>
              <trkpt lat="25.1" lon="121.1"></trkpt>
            </trkseg>
          </trk>
          <trk>
            <name>  A &amp; <![CDATA[B]]>  </name>
            <trkseg>
              <trkpt lat="25.2" lon="121.2"></trkpt>
              <trkpt lat="25.3" lon="121.3"></trkpt>
            </trkseg>
          </trk>
          <trk>
            <name>A<b>B</b></name>
            <trkseg>
              <trkpt lat="25.4" lon="121.4"></trkpt>
              <trkpt lat="25.5" lon="121.5"></trkpt>
            </trkseg>
          </trk>
          <trk>
            <name>   </name>
            <trkseg>
              <trkpt lat="25.6" lon="121.6"></trkpt>
              <trkpt lat="25.7" lon="121.7"></trkpt>
            </trkseg>
          </trk>
          <rte>
            <rtept lat="25.8" lon="121.8"></rtept>
            <rtept lat="25.9" lon="121.9"></rtept>
            <name>點之後才出現的名稱不算</name>
          </rte>
        </gpx>
        """
        let named = GpxCodec.readRoutes(from: Data(routeNames.utf8))
        XCTAssertEqual(named.map(\.name), ["Orux Track", "A & B", "AB", nil, nil])
        XCTAssertEqual(named.map(\.points.count), [2, 2, 2, 2, 2])

        // 寫到一半就結束的檔案:保留錯誤之前已經完整讀完的路線
        let truncated = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GFlyer" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>完整的路線</name>
            <trkseg>
              <trkpt lat="25.0" lon="121.0"></trkpt>
              <trkpt lat="25.1" lon="121.1"></trkpt>
            </trkseg>
          </trk>
          <trk>
            <name>沒寫完的路線</name>
            <trkseg>
              <trkpt lat="26.0" lon="122.0"></trkpt>
              <trkpt lat="26.1" lon="122.1"></trkpt>
              <trkpt lat="26.2"
        """
        let partial = GpxCodec.readRoutes(from: Data(truncated.utf8))
        XCTAssertEqual(partial.map(\.name), ["完整的路線"])
        XCTAssertEqual(partial.first?.points, [
            GeoCoordinate(latitude: 25.0, longitude: 121.0),
            GeoCoordinate(latitude: 25.1, longitude: 121.1),
        ])
    }

    /// 產生名稱與儲存時用同一條大小寫規則,不會把不同名的路線當成同名覆蓋掉(DRIFT D18)
    @MainActor
    func testSavingARouteUsesTheSameCaseRuleAsNaming() {
        let suiteName = "gflyer.route-case-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let points = [GeoCoordinate(latitude: 1, longitude: 1), GeoCoordinate(latitude: 2, longitude: 2)]

        store.saveRoute(name: "STRASSE", points: points, loop: false)
        store.saveRoute(name: "Straße", points: points, loop: false)
        store.saveRoute(name: "Harbour", points: points, loop: false)
        store.saveRoute(name: "HARBOUR", points: points, loop: false)

        XCTAssertEqual(Set(store.snapshot.routes.map(\.name)), ["STRASSE", "Straße", "HARBOUR"])
    }

    // MARK: - contracts/fixtures/speed/preset-speed-values.json

    /// builtInPresets:iOS 內建預設的匯出值,以及讀入 Android 匯出值之後仍然認得是內建預設
    /// (原本用 == 比,還原 Android 備份後「正常走路」「腳踏車」「汽車」會出現刪除鈕)。
    func testBuiltInPresetsMatchTheSharedSpeedFixture() {
        let cases: [(name: String, kilometresPerHour: Double, iosExport: Double, androidExport: Double,
                     iosReadsAndroidExport: Double)] = [
            ("正常走路", 5.0, 1.3888888888888888, 1.388888955116272, 5.000000238418579),
            ("跑步", 10.8, 3.0, 3.0, 10.8),
            ("腳踏車", 19.0, 5.277777777777778, 5.277778148651123, 19.000001335144045),
            ("汽車", 50.0, 13.88888888888889, 13.88888931274414, 50.00000152587891),
            ("飛機", 900.0, 250.0, 250.0, 900.0),
        ]
        XCTAssertEqual(SpeedScale.defaultPresets.map(\.name), cases.map { $0.name })
        XCTAssertEqual(SpeedScale.sameSpeedTolerance, 0.01)
        for (preset, testCase) in zip(SpeedScale.defaultPresets, cases) {
            XCTAssertEqual(preset.kilometresPerHour, testCase.kilometresPerHour, testCase.name)
            // 備份匯出的就是 km/h ÷ 3.6(AppBackupCodec.export),兩邊重做同一個運算,可以用 == 比
            XCTAssertEqual(preset.kilometresPerHour / 3.6, testCase.iosExport, testCase.name)
            XCTAssertEqual(testCase.androidExport * 3.6, testCase.iosReadsAndroidExport, testCase.name)
            XCTAssertTrue(preset.isBuiltIn, testCase.name)
            let restored = QuickSpeedPreset(name: testCase.name, kilometresPerHour: testCase.androidExport * 3.6)
            XCTAssertTrue(restored.isBuiltIn, "還原 Android 備份後仍是內建預設:\(testCase.name)")
        }
        XCTAssertFalse(QuickSpeedPreset(name: "正常走路 ", kilometresPerHour: 5).isBuiltIn, "名稱要完全相同")
        XCTAssertFalse(QuickSpeedPreset(name: "正常走路", kilometresPerHour: 5.04).isBuiltIn)
    }

    /// sameSpeedCases:輸入是 m/s(備份裡的單位),iOS 先乘 3.6 再比。
    func testSameSpeedMatchesTheSharedSpeedFixture() {
        let cases: [(name: String, a: Double, b: Double, expected: Bool)] = [
            ("android-walk-vs-ios-walk", 1.388888955116272, 1.3888888888888888, true),
            ("android-bicycle-vs-ios-bicycle", 5.277778148651123, 5.277777777777778, true),
            ("android-car-vs-ios-car", 13.88888931274414, 13.88888888888889, true),
            ("ios-walk-read-back-by-android", 1.3888888359069824, 1.388888955116272, true),
            ("legacy-walk-is-not-walk", 1.399999976158142, 1.388888955116272, false),
            ("inside-tolerance", 1.391388888888889, 1.388888955116272, true),
            ("outside-tolerance", 1.392222222222222, 1.388888955116272, false),
            ("slider-5.1-is-not-walk", 1.4166666666666665, 1.388888955116272, false),
        ]
        for testCase in cases {
            XCTAssertEqual(SpeedScale.isSameSpeed(testCase.a * 3.6, testCase.b * 3.6), testCase.expected, testCase.name)
        }
    }

    /// thresholdCases:種花警告是 above(v, 20)。懸浮鈕圖示是 Android 專屬,這裡只拿它的分段
    /// 驗證 isBelow / isAtMost 的邊界。
    func testThresholdsMatchTheSharedSpeedFixture() {
        let cases: [(name: String, metresPerSecond: Double, icon: String, exceedsFlowerLimit: Bool)] = [
            ("android-walk-constant", 1.388888955116272, "5to19", false),
            ("ios-walk-read-back-by-android", 1.3888888359069824, "5to19", false),
            ("floating-plus-one-up-to-19", 5.277776718139648, "19to50", false),
            ("floating-minus-one-down-to-19", 5.2777814865112305, "19to50", false),
            ("android-bicycle-constant", 5.277778148651123, "19to50", false),
            ("clearly-below-5", 1.3833333333333335, "under5", false),
            ("within-tolerance-below-19", 5.2763888888888895, "19to50", false),
            ("clearly-below-19", 5.273611111111111, "5to19", false),
            ("android-car-constant", 13.88888931274414, "19to50", true),
            ("within-tolerance-above-50", 13.890277777777778, "19to50", true),
            ("clearly-above-50", 13.894444444444446, "over50", true),
            ("floating-minus-one-down-to-20", 5.555559158325195, "19to50", false),
            ("ios-20-read-back-by-android", 5.55555534362793, "19to50", false),
            ("within-tolerance-above-20", 5.5569444444444445, "19to50", false),
            ("clearly-above-20", 5.561111111111111, "19to50", true),
        ]
        for testCase in cases {
            let speed = testCase.metresPerSecond * 3.6
            let icon: String
            if SpeedScale.isBelow(speed, 5) {
                icon = "under5"
            } else if SpeedScale.isBelow(speed, 19) {
                icon = "5to19"
            } else if SpeedScale.isAtMost(speed, 50) {
                icon = "19to50"
            } else {
                icon = "over50"
            }
            XCTAssertEqual(icon, testCase.icon, testCase.name)
            XCTAssertEqual(SpeedScale.exceedsFlowerLimit(speed), testCase.exceedsFlowerLimit, testCase.name)
        }
    }

    // MARK: - contracts/fixtures/backup/legacy-walk-preset.json

    /// 還原備份時,舊版 Android 的「正常走路」1.4 m/s 換成 5.0 km/h;名稱完全相同才換,不看 id。
    func testLegacyWalkPresetMatchesTheSharedFixture() throws {
        let cases: [(name: String, id: String, presetName: String, metresPerSecond: String,
                     expectedKilometresPerHour: Double, replaced: Bool, matchesBuiltInWalk: Bool)] = [
            ("old-android-export", "1", "正常走路", "1.399999976158142", 5.0, true, true),
            ("exact-1.4", "1", "正常走路", "1.4", 5.0, true, true),
            ("id-does-not-matter", "5846229133072385071", "正常走路", "1.399999976158142", 5.0, true, true),
            ("inside-window", "1", "正常走路", "1.4009", 5.0, true, true),
            ("outside-window", "1", "正常走路", "1.402", 5.0472, false, false),
            ("other-name-keeps-1.4", "7", "走路", "1.4", 5.04, false, false),
            ("name-must-match-exactly", "1", "正常走路 ", "1.4", 5.04, false, false),
            ("faster-walk-keeps-its-speed", "1", "正常走路", "1.5", 5.4, false, false),
            ("current-android-export-is-untouched", "1", "正常走路", "1.388888955116272", 5.0, false, true),
            ("current-ios-export-is-untouched", "5846229133072385071", "正常走路", "1.3888888888888888", 5.0, false, true),
        ]
        for testCase in cases {
            let json = #"{"format": "GFlyer Backup", "version": 1, "quickSpeedPresets": [{"id": \#(testCase.id), "name": "\#(testCase.presetName)", "metresPerSecond": \#(testCase.metresPerSecond)}]}"#
            let preset = try XCTUnwrap(AppBackupCodec.decode(Data(json.utf8)).presets.first, testCase.name)

            XCTAssertEqual(preset.kilometresPerHour, testCase.expectedKilometresPerHour, accuracy: 0.01, testCase.name)
            if testCase.replaced {
                XCTAssertEqual(preset.kilometresPerHour, SpeedScale.walkKilometresPerHour, testCase.name)
            }
            XCTAssertEqual(preset.name, testCase.presetName, testCase.name)
            XCTAssertEqual(preset.isBuiltIn, testCase.matchesBuiltInWalk, testCase.name)
        }
    }

    /// 裝置上已經存著的 5.04 km/h(0.6.8 以前還原舊 Android 備份)在載入時換成 5.0,
    /// id 與順序不變;其他預設不動。
    func testStoredLegacyWalkPresetIsReplacedWhenLoading() throws {
        let walkID = UUID()
        let fasterID = UUID()
        let otherID = UUID()
        let json = """
        {"presets": [
          {"id": "\(walkID.uuidString)", "name": "正常走路", "kilometresPerHour": 5.039999914169312},
          {"id": "\(fasterID.uuidString)", "name": "正常走路", "kilometresPerHour": 5.4},
          {"id": "\(otherID.uuidString)", "name": "走路", "kilometresPerHour": 5.04}
        ]}
        """
        let snapshot = try JSONDecoder().decode(LocalDataSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.presets.map(\.id), [walkID, fasterID, otherID])
        XCTAssertEqual(snapshot.presets.map(\.kilometresPerHour), [5.0, 5.4, 5.04])
        // 冪等:再跑一次不變
        XCTAssertEqual(snapshot.presets.map { $0.replacingLegacyWalk() }, snapshot.presets)
    }

    // MARK: - contracts/fixtures/text/message-board-limits.json

    /// fields[].maxLength 與 clientInputCaps[].maxLength,以 fixture 的 id 為鍵。
    func testBoardTextLimitsMatchTheSharedFixture() {
        let expected: [String: Int] = [
            "auth.inviteCode": 32,
            "auth.adminCode": 4,
            "auth.username": 30,
            "auth.deviceLabel": 80,
            "coordReport.clientRequestId": 80,
            "coordReport.coordinateId": 60,
            "coordReport.coordinateName": 80,
            "coordReport.reason": 40,
            "coordReport.message": 300,
            "post.clientRequestId": 80,
            "post.remark": 300,
            "post.tag": 20,
            "post.coordinate.name": 80,
            "post.route.name": 80,
            "reply.message": 300,
            "invite.code": 32,
            "ui.tagsInput": 120,
            "ui.boardSearch": 80,
        ]
        XCTAssertEqual(BoardTextLimits.maxLengthByFixtureID, expected)
        XCTAssertEqual(BoardTextLimits.inviteCodeMinimum, 4)
        XCTAssertEqual(BoardTextLimits.maxTags, 5)
    }

    /// boundaryCases:去掉前後空白之後的 code point / UTF-16 / 字素數量,和截斷後的結果。
    func testBoardBoundaryCasesCountCodePoints() {
        let walker = "\u{1F6B6}"
        let flag = "\u{1F1F9}\u{1F1FC}"
        let combining = "e\u{0301}"
        let cases: [(name: String, leading: String, text: String, repeatCount: Int, trailing: String,
                     codePoints: Int, utf16Units: Int, graphemes: Int)] = [
            ("username-30-emoji-passes", "", walker, 30, "", 30, 60, 30),
            ("username-31-emoji-fails", "", walker, 31, "", 31, 62, 31),
            ("username-15-flags-is-30-code-points-and-passes", "", flag, 15, "", 30, 60, 15),
            ("username-16-flags-fails-although-only-16-graphemes", "", flag, 16, "", 32, 64, 16),
            ("username-surrounding-spaces-are-trimmed-before-counting", "  ", "名", 30, "  ", 30, 30, 30),
            ("reply-300-emoji-passes", "", walker, 300, "", 300, 600, 300),
            ("reply-301-cjk-fails", "", "字", 301, "", 301, 301, 301),
            ("reply-whitespace-only-is-missing", "", " ", 3, "", 0, 0, 0),
            ("remark-150-combining-pairs-is-300-code-points-and-passes", "", combining, 150, "", 300, 300, 150),
            ("remark-151-combining-pairs-fails-although-only-151-graphemes", "", combining, 151, "", 302, 302, 151),
            ("tag-20-emoji-passes", "", walker, 20, "", 20, 40, 20),
            ("tag-hash-is-counted-before-it-is-stripped", "#", "a", 20, "", 21, 21, 21),
            ("tag-whitespace-only-is-missing", "", " ", 2, "", 0, 0, 0),
            ("coordinate-name-80-emoji-passes", "", walker, 80, "", 80, 160, 80),
            ("coordinate-name-81-emoji-fails", "", walker, 81, "", 81, 162, 81),
            ("route-name-80-emoji-passes", "", walker, 80, "", 80, 160, 80),
            ("invite-code-4-ascii-passes-length", "", "ab-1", 1, "", 4, 4, 4),
            ("invite-code-two-emoji-is-too-short", "", walker, 2, "", 2, 4, 2),
            ("admin-code-fullwidth-digits-fail-pattern", "", "\u{FF11}", 4, "", 4, 4, 4),
            ("report-message-300-emoji-passes", "", walker, 300, "", 300, 600, 300),
            ("report-message-empty-is-allowed", "", "", 0, "", 0, 0, 0),
        ]
        for testCase in cases {
            let input = testCase.leading + String(repeating: testCase.text, count: testCase.repeatCount) + testCase.trailing
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(trimmed.unicodeScalars.count, testCase.codePoints, testCase.name)
            XCTAssertEqual(trimmed.utf16.count, testCase.utf16Units, testCase.name)
            XCTAssertEqual(trimmed.count, testCase.graphemes, testCase.name)
        }

        // 截斷到上限:emoji 不被切成一半,國旗可能被切開(D14 已接受的取捨)
        let username = String(repeating: walker, count: 31).codePointsCapped(at: BoardTextLimits.username)
        XCTAssertEqual(username, String(repeating: walker, count: 30))
        XCTAssertEqual(
            String(repeating: flag, count: 16).codePointsCapped(at: BoardTextLimits.username),
            String(repeating: flag, count: 15)
        )
        let remark = String(repeating: combining, count: 151).codePointsCapped(at: BoardTextLimits.remark)
        XCTAssertEqual(remark?.unicodeScalars.map(\.value), String(repeating: combining, count: 150).unicodeScalars.map(\.value))
        XCTAssertNil(String(repeating: walker, count: 300).codePointsCapped(at: BoardTextLimits.reply), "沒超過時不改寫")
    }

    func testStartDelayKeepsPreferringTheSmallerOptionOnTie() {
        var settings = PlaybackSettings()
        settings.startDelaySeconds = 4
        XCTAssertEqual(settings.sanitized().startDelaySeconds, 3, "開始延遲不是跨平台設定,維持原本的規則")
    }
}
