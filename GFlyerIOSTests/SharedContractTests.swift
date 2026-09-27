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

    // MARK: - contracts/fixtures/route/arrival-actions.json

    /// 容差照 fixture 的 tolerance:經緯度 1e-9 度,弧度 1e-12,公尺 1e-12。
    private func assertCoordinate(
        _ actual: GeoCoordinate?,
        _ expected: (latitude: Double, longitude: Double),
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("missing coordinate: \(message)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 1e-9, message, file: file, line: line)
    }

    /// constants
    func testArrivalConstantsMatchTheSharedFixture() {
        XCTAssertEqual(OrbitPlanner.stepsPerLap(stepRadians: 100), 8, "minStepsPerLap")
        XCTAssertEqual(PlaybackSettings.microMoveDistanceMetres, 20.0)
        XCTAssertEqual(MicroMovePlanner.bearingDegrees, 90.0)
        XCTAssertEqual(PlaybackSettings.defaultOrbitRadiiMetres, [20, 30])
        XCTAssertEqual(PlaybackSettings.orbitRadiusRange, 5...500)
        XCTAssertEqual(PlaybackSettings.orbitRadiusStepMetres, 5)
        XCTAssertEqual(PlaybackSettings.addedLapRadiusMetres, 40)
        XCTAssertEqual(PlaybackSettings.maxOrbitLaps, 4)
        XCTAssertEqual(PlaybackSettings.dwellRange, 1...300)
        XCTAssertEqual(PlaybackSettings.startDelayOptions, [0, 3, 5, 10])
        let defaults = PlaybackSettings()
        XCTAssertEqual(defaults.dwellSeconds, 10)
        XCTAssertEqual(defaults.travelMode, .simulate)
        XCTAssertEqual(defaults.pointAction, .orbit)
        XCTAssertFalse(defaults.manualAdvance)
        // 顯示名稱(rawValue 是舊的儲存值,不變)
        XCTAssertEqual(RouteTravelMode.allCases.map(\.label), ["模擬移動", "定點傳送"])
        XCTAssertEqual(RouteTravelMode.teleport.rawValue, "逐點傳送")
        XCTAssertEqual(RoutePointAction.selectableCases.map(\.label), ["繞圈", "向東走 20 米"])
        XCTAssertNil(RoutePointAction.none.label)
        XCTAssertEqual(LoopTransitionMode.allCases.map(\.label), ["走回起點", "瞬間跳轉"])
        XCTAssertEqual(LoopTransitionMode.teleportToStart.rawValue, "直接返回")
    }

    /// offset:等距長方投影位移,緯度夾到 ±90、經度正規化到 [-180, 180)。
    func testOffsetMatchesTheSharedFixture() {
        let cases: [(name: String, origin: (latitude: Double, longitude: Double), east: Double, north: Double,
                     expected: (latitude: Double, longitude: Double))] = [
            ("east-100m", (25.033964, 121.564468), 100.0, 0.0,
             (25.033964, 121.565459450945)),
            ("north-100m", (25.033964, 121.564468), 0.0, 100.0,
             (25.034862311175, 121.564468)),
            ("south-west", (25.033964, 121.564468), -30.0, -40.0,
             (25.03360467553, 121.564170564716)),
            ("crosses-antimeridian-eastward", (-16.8, 179.9999), 20.0, 0.0,
             (-16.8, -179.999912327822)),
            ("crosses-antimeridian-westward", (-16.8, -179.9999), -20.0, 0.0,
             (-16.8, 179.999912327822)),
            ("latitude-clamped-at-north-pole", (89.9999, 10.0), 0.0, 20.0,
             (90.0, 10.0)),
            ("latitude-clamped-at-south-pole", (-89.9999, 10.0), 0.0, -20.0,
             (-90.0, 10.0)),
            ("cos-floor-at-pole", (90.0, 0.0), 10.0, 0.0,
             (90.0, 89.831117499102)),
        ]
        for testCase in cases {
            let origin = GeoCoordinate(latitude: testCase.origin.latitude, longitude: testCase.origin.longitude)
            let actual = GeoMath.offset(from: origin, eastMetres: testCase.east, northMetres: testCase.north)
            assertCoordinate(actual, testCase.expected, testCase.name)
        }
    }

    /// orbit:每一圈的步數與每步弧度、跨圈累加的最後角度、每一步的座標。
    func testOrbitMatchesTheSharedFixture() {
        // two-laps-fast
        do {
            let center = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let laps = OrbitPlanner.laps(
                center: center,
                radiiMetres: [20, 30],
                speedMetresPerSecond: 40.0,
                tickSeconds: 0.25
            )
            XCTAssertEqual(laps.map(\.radiusMetres), [20, 30], "two-laps-fast")
            XCTAssertEqual(laps.map(\.waypoints.count), [13, 19], "two-laps-fast")
            let expectedStepRadians: [Double] = [0.5, 0.3333333333333333]
            for (lap, stepRadians) in zip(laps, expectedStepRadians) {
                XCTAssertEqual(lap.stepRadians, stepRadians, accuracy: 1e-12, "two-laps-fast")
            }
            XCTAssertEqual(laps.last?.endAngleRadians ?? 0, 12.833333333333341, accuracy: 1e-12, "two-laps-fast")
            let waypoints = laps.flatMap(\.waypoints)
            XCTAssertEqual(waypoints.count, 32, "two-laps-fast")
            let expected: [(latitude: Double, longitude: Double)] = [
                (25.034050134664, 121.564642016012),
                (25.034115180558, 121.564575136646),
                (25.034143212179, 121.564482026493),
                (25.034127366408, 121.564385482165),
                (25.034071522843, 121.564309141081),
                (25.033989353936, 121.564271694201),
                (25.033900977501, 121.564282309826),
                (25.033828031172, 121.564338388883),
                (25.033788374754, 121.564426201261),
                (25.033791717522, 121.564524247428),
                (25.033837241048, 121.564608522264),
                (25.033913799587, 121.564658392348),
                (25.034002648938, 121.564661647745),
                (25.034104894741, 121.564721547857),
                (25.034172305522, 121.564656712),
                (25.034216784758, 121.564571101574),
                (25.034233435905, 121.564474141097),
                (25.034220425902, 121.56437650457),
                (25.034179186969, 121.564288940419),
                (25.03411425894, 121.56422108824),
                (25.03403278949, 121.564180417616),
                (25.033943747273, 121.564171405817),
                (25.033856934599, 121.564195044917),
                (25.033781908339, 121.56424873258),
                (25.03372692784, 121.564326558539),
                (25.033698045693, 121.564419955238),
                (25.033698441421, 121.564518640998),
                (25.033728071458, 121.564611751888),
                (25.033783673951, 121.564689037692),
                (25.033859127836, 121.564741990317),
                (25.03394612669, 121.564764780414),
                (25.034035093146, 121.564754899111),
            ]
            XCTAssertEqual(waypoints.count, expected.count)
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "two-laps-fast #\(index)")
            }
        }
        // default-radii-slow
        do {
            let center = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let laps = OrbitPlanner.laps(
                center: center,
                radiiMetres: [20, 30],
                speedMetresPerSecond: 2.5,
                tickSeconds: 0.25
            )
            XCTAssertEqual(laps.map(\.radiusMetres), [20, 30], "default-radii-slow")
            XCTAssertEqual(laps.map(\.waypoints.count), [202, 302], "default-radii-slow")
            let expectedStepRadians: [Double] = [0.03125, 0.020833333333333332]
            for (lap, stepRadians) in zip(laps, expectedStepRadians) {
                XCTAssertEqual(lap.stepRadians, stepRadians, accuracy: 1e-12, "default-radii-slow")
            }
            XCTAssertEqual(laps.last?.endAngleRadians ?? 0, 12.604166666666773, accuracy: 1e-12, "default-radii-slow")
            let waypoints = laps.flatMap(\.waypoints)
            XCTAssertEqual(waypoints.count, 504, "default-radii-slow")
            let samples: [(index: Int, latitude: Double, longitude: Double)] = [
                (0, 25.033969613531, 121.564666193376),
                (1, 25.033975221581, 121.56466590303),
                (201, 25.033969265989, 121.564666204995),
                (202, 25.033977508896, 121.564765061363),
                (503, 25.03397418336, 121.56476522286),
            ]
            for sample in samples {
                assertCoordinate(
                    waypoints.indices.contains(sample.index) ? waypoints[sample.index] : nil,
                    (sample.latitude, sample.longitude),
                    "default-radii-slow #\(sample.index)"
                )
            }
        }
        // minimum-eight-steps
        do {
            let center = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let laps = OrbitPlanner.laps(
                center: center,
                radiiMetres: [5],
                speedMetresPerSecond: 250.0,
                tickSeconds: 0.25
            )
            XCTAssertEqual(laps.map(\.radiusMetres), [5], "minimum-eight-steps")
            XCTAssertEqual(laps.map(\.waypoints.count), [8], "minimum-eight-steps")
            let expectedStepRadians: [Double] = [12.5]
            for (lap, stepRadians) in zip(laps, expectedStepRadians) {
                XCTAssertEqual(lap.stepRadians, stepRadians, accuracy: 1e-12, "minimum-eight-steps")
            }
            XCTAssertEqual(laps.last?.endAngleRadians ?? 0, 100.0, accuracy: 1e-12, "minimum-eight-steps")
            let waypoints = laps.flatMap(\.waypoints)
            XCTAssertEqual(waypoints.count, 8, "minimum-eight-steps")
            let expected: [(latitude: Double, longitude: Double)] = [
                (25.033961021115, 121.564517463402),
                (25.033958055347, 121.564517136448),
                (25.033955115756, 121.564516593125),
                (25.033952215287, 121.564515835824),
                (25.033949366711, 121.564514867881),
                (25.033946582571, 121.564513693558),
                (25.033943875128, 121.564512318027),
                (25.033941256304, 121.564510747343),
            ]
            XCTAssertEqual(waypoints.count, expected.count)
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "minimum-eight-steps #\(index)")
            }
        }
        // crosses-antimeridian
        do {
            let center = GeoCoordinate(latitude: -16.8, longitude: 179.9999)
            let laps = OrbitPlanner.laps(
                center: center,
                radiiMetres: [20],
                speedMetresPerSecond: 40.0,
                tickSeconds: 0.25
            )
            XCTAssertEqual(laps.map(\.radiusMetres), [20], "crosses-antimeridian")
            XCTAssertEqual(laps.map(\.waypoints.count), [13], "crosses-antimeridian")
            let expectedStepRadians: [Double] = [0.5]
            for (lap, stepRadians) in zip(laps, expectedStepRadians) {
                XCTAssertEqual(lap.stepRadians, stepRadians, accuracy: 1e-12, "crosses-antimeridian")
            }
            XCTAssertEqual(laps.last?.endAngleRadians ?? 0, 6.5, accuracy: 1e-12, "crosses-antimeridian")
            let waypoints = laps.flatMap(\.waypoints)
            XCTAssertEqual(waypoints.count, 13, "crosses-antimeridian")
            let expected: [(latitude: Double, longitude: Double)] = [
                (-16.799913865336, -179.999935302169),
                (-16.799848819442, -179.99999860029),
                (-16.799820787821, 179.999913275405),
                (-16.799836633592, 179.999821900817),
                (-16.799892477157, 179.999749647633),
                (-16.799974646064, 179.999714205952),
                (-16.800063022499, 179.999724253134),
                (-16.800135968828, 179.999777329278),
                (-16.800175625246, 179.999860439493),
                (-16.800172282478, 179.9999532355),
                (-16.800126758952, -179.9999670024),
                (-16.800050200413, -179.999919802751),
                (-16.799961351062, -179.999916721673),
            ]
            XCTAssertEqual(waypoints.count, expected.count)
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "crosses-antimeridian #\(index)")
            }
        }
    }

    /// microMove:往正東走 20 公尺,步數、步長與每一步的座標(停在終點,不走回路線點)。
    func testMicroMoveMatchesTheSharedFixture() {
        // five-metres-per-second
        do {
            let origin = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let speed = 5.0
            XCTAssertEqual(MicroMovePlanner.steps(speedMetresPerSecond: speed, tickSeconds: 0.25), 16, "five-metres-per-second")
            let waypoints = MicroMovePlanner.waypoints(origin: origin, speedMetresPerSecond: speed, tickSeconds: 0.25)
            XCTAssertEqual(waypoints.count, 16, "five-metres-per-second")
            XCTAssertEqual(PlaybackSettings.microMoveDistanceMetres / Double(waypoints.count), 1.25, accuracy: 1e-12, "five-metres-per-second")
            let expected: [(latitude: Double, longitude: Double)] = [
                (25.033963999999, 121.564480407077),
                (25.033963999999, 121.564492814153),
                (25.033963999998, 121.56450522123),
                (25.033963999998, 121.564517628307),
                (25.033963999997, 121.564530035384),
                (25.033963999997, 121.56454244246),
                (25.033963999996, 121.564554849537),
                (25.033963999996, 121.564567256614),
                (25.033963999995, 121.564579663691),
                (25.033963999995, 121.564592070767),
                (25.033963999994, 121.564604477844),
                (25.033963999994, 121.564616884921),
                (25.033963999993, 121.564629291998),
                (25.033963999993, 121.564641699074),
                (25.033963999992, 121.564654106151),
                (25.033963999992, 121.564666513228),
            ]
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "five-metres-per-second #\(index)")
            }
        }
        // forty-metres-per-second
        do {
            let origin = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let speed = 40.0
            XCTAssertEqual(MicroMovePlanner.steps(speedMetresPerSecond: speed, tickSeconds: 0.25), 2, "forty-metres-per-second")
            let waypoints = MicroMovePlanner.waypoints(origin: origin, speedMetresPerSecond: speed, tickSeconds: 0.25)
            XCTAssertEqual(waypoints.count, 2, "forty-metres-per-second")
            XCTAssertEqual(PlaybackSettings.microMoveDistanceMetres / Double(waypoints.count), 10.0, accuracy: 1e-12, "forty-metres-per-second")
            let expected: [(latitude: Double, longitude: Double)] = [
                (25.033963999967, 121.564567256614),
                (25.033963999934, 121.564666513228),
            ]
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "forty-metres-per-second #\(index)")
            }
        }
        // fast-single-step
        do {
            let origin = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let speed = 250.0
            XCTAssertEqual(MicroMovePlanner.steps(speedMetresPerSecond: speed, tickSeconds: 0.25), 1, "fast-single-step")
            let waypoints = MicroMovePlanner.waypoints(origin: origin, speedMetresPerSecond: speed, tickSeconds: 0.25)
            XCTAssertEqual(waypoints.count, 1, "fast-single-step")
            XCTAssertEqual(PlaybackSettings.microMoveDistanceMetres / Double(waypoints.count), 20.0, accuracy: 1e-12, "fast-single-step")
            let expected: [(latitude: Double, longitude: Double)] = [
                (25.033963999868, 121.564666513228),
            ]
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "fast-single-step #\(index)")
            }
        }
        // minimum-speed
        do {
            let origin = GeoCoordinate(latitude: 25.033964, longitude: 121.564468)
            let speed = 0.5
            XCTAssertEqual(MicroMovePlanner.steps(speedMetresPerSecond: speed, tickSeconds: 0.25), 160, "minimum-speed")
            let waypoints = MicroMovePlanner.waypoints(origin: origin, speedMetresPerSecond: speed, tickSeconds: 0.25)
            XCTAssertEqual(waypoints.count, 160, "minimum-speed")
            XCTAssertEqual(PlaybackSettings.microMoveDistanceMetres / Double(waypoints.count), 0.125, accuracy: 1e-12, "minimum-speed")
            let samples: [(index: Int, latitude: Double, longitude: Double)] = [
                (0, 25.033964, 121.564469240708),
                (80, 25.033963999999, 121.564568497321),
                (159, 25.033963999999, 121.564666513226),
            ]
            for sample in samples {
                assertCoordinate(
                    waypoints.indices.contains(sample.index) ? waypoints[sample.index] : nil,
                    (sample.latitude, sample.longitude),
                    "minimum-speed #\(sample.index)"
                )
            }
        }
        // crosses-antimeridian
        do {
            let origin = GeoCoordinate(latitude: -16.8, longitude: 179.9999)
            let speed = 5.0
            XCTAssertEqual(MicroMovePlanner.steps(speedMetresPerSecond: speed, tickSeconds: 0.25), 16, "crosses-antimeridian")
            let waypoints = MicroMovePlanner.waypoints(origin: origin, speedMetresPerSecond: speed, tickSeconds: 0.25)
            XCTAssertEqual(waypoints.count, 16, "crosses-antimeridian")
            XCTAssertEqual(PlaybackSettings.microMoveDistanceMetres / Double(waypoints.count), 1.25, accuracy: 1e-12, "crosses-antimeridian")
            let expected: [(latitude: Double, longitude: Double)] = [
                (-16.8, 179.999911742705),
                (-16.799999999999, 179.999923485409),
                (-16.799999999999, 179.999935228114),
                (-16.799999999999, 179.999946970818),
                (-16.799999999998, 179.999958713523),
                (-16.799999999998, 179.999970456228),
                (-16.799999999998, 179.999982198932),
                (-16.799999999997, 179.999993941637),
                (-16.799999999997, -179.999994315659),
                (-16.799999999997, -179.999982572954),
                (-16.799999999996, -179.999970830249),
                (-16.799999999996, -179.999959087545),
                (-16.799999999996, -179.99994734484),
                (-16.799999999995, -179.999935602136),
                (-16.799999999995, -179.999923859431),
                (-16.799999999995, -179.999912116726),
            ]
            for (index, point) in expected.enumerated() where index < waypoints.count {
                assertCoordinate(waypoints[index], point, "crosses-antimeridian #\(index)")
            }
        }
    }

    /// orbitRadii:範圍外丟掉(不夾限)→ 去重 → 取前 4 個 → 空的用 [20, 30]。
    func testOrbitRadiiNormalizationMatchesTheSharedFixture() {
        let cases: [(name: String, input: [Int], expected: [Int])] = [
            ("default-kept", [20, 30], [20, 30]),
            ("empty-falls-back-to-default", [], [20, 30]),
            ("out-of-range-dropped-not-clamped", [4, 20, 501], [20]),
            ("all-out-of-range-falls-back", [3, 600], [20, 30]),
            ("bounds-inclusive", [5, 500], [5, 500]),
            ("duplicates-removed", [20, 20, 30], [20, 30]),
            ("order-kept", [30, 20], [30, 20]),
            ("at-most-four-laps", [20, 25, 30, 35, 40], [20, 25, 30, 35]),
            ("dedupe-before-taking-four", [20, 30, 20, 40, 50], [20, 30, 40, 50]),
        ]
        for testCase in cases {
            XCTAssertEqual(PlaybackSettings.normalizedOrbitRadii(testCase.input), testCase.expected, testCase.name)
            var settings = PlaybackSettings()
            settings.orbitRadiiMetres = testCase.input
            XCTAssertEqual(settings.sanitized().orbitRadiiMetres, testCase.expected, "sanitized: \(testCase.name)")
        }
    }

    /// orbitRadiiEdits:設定頁的 −、+、刪除、新增;nil 表示按鈕不存在或停用。
    func testOrbitRadiusEditsMatchTheSharedFixture() {
        let cases: [(name: String, radii: [Int], edit: PlaybackSettings.OrbitRadiusEdit, expected: [Int]?)] = [
            ("decrease", [20, 30], .decrease(index: 1), [20, 25]),
            ("decrease-stops-at-5", [5, 30], .decrease(index: 0), [5, 30]),
            ("increase-stops-at-500", [20, 500], .increase(index: 1), [20, 500]),
            ("decrease-into-duplicate-removes-lap", [20, 25], .decrease(index: 1), [20]),
            ("add-appends-40", [20, 30], .add, [20, 30, 40]),
            ("add-when-40-exists-changes-nothing", [20, 30, 40], .add, [20, 30, 40]),
            ("add-hidden-at-four-laps", [20, 30, 40, 50], .add, nil),
            ("delete-middle-lap", [20, 30, 40], .delete(index: 1), [20, 40]),
            ("delete-disabled-with-one-lap", [20], .delete(index: 0), nil),
        ]
        for testCase in cases {
            XCTAssertEqual(PlaybackSettings.editedOrbitRadii(testCase.radii, testCase.edit), testCase.expected, testCase.name)
        }
    }

    /// dwellSeconds:夾到 1〜300。
    func testDwellSecondsMatchTheSharedFixture() {
        let cases: [(input: Int, expected: Int)] = [(-5, 1), (0, 1), (1, 1), (10, 10), (300, 300), (301, 300)]
        for testCase in cases {
            XCTAssertEqual(PlaybackSettings.clampedDwellSeconds(testCase.input), testCase.expected, "input=\(testCase.input)")
            var settings = PlaybackSettings()
            settings.dwellSeconds = testCase.input
            XCTAssertEqual(settings.sanitized().dwellSeconds, testCase.expected, "sanitized input=\(testCase.input)")
        }
    }

    /// arrivalPlan:這次播放實際採用的值(effective)與一圈裡每一段的到點步驟。points 的代號只用來數點數,
    /// 路線點照位置編號,同一個座標出現兩次也一樣(repeated-point-numbered-by-position)。
    func testArrivalPlanMatchesTheSharedFixture() {
        struct PlanCase {
            let name: String
            let kind: RouteStartKind
            let pointCount: Int
            let stored: PlaybackSettings
            let loop: Bool
            let transition: LoopTransitionMode
            let effective: RoutePlaybackOptions
            let lap: [RouteLeg]
            let repeats: Bool
        }
        func stored(
            _ travelMode: RouteTravelMode,
            _ pointAction: RoutePointAction,
            manualAdvance: Bool,
            dwellSeconds: Int,
            startDelaySeconds: Int
        ) -> PlaybackSettings {
            var settings = PlaybackSettings()
            settings.travelMode = travelMode
            settings.pointAction = pointAction
            settings.manualAdvance = manualAdvance
            settings.dwellSeconds = dwellSeconds
            settings.startDelaySeconds = startDelaySeconds
            return settings
        }
        func leg(
            _ from: Int,
            _ to: Int,
            _ travelMode: RouteTravelMode,
            dwell: Int,
            _ action: RoutePointAction,
            waitManual: Bool,
            isFinal: Bool
        ) -> RouteLeg {
            RouteLeg(
                from: from,
                to: to,
                travelMode: travelMode,
                steps: RouteArrivalSteps(dwellSeconds: dwell, action: action, waitsForManualAdvance: waitManual),
                isFinalStop: isFinal
            )
        }
        let cases: [PlanCase] = [
            PlanCase(
                name: "simulate-ignores-arrival-options",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.simulate, .orbit, manualAdvance: true, dwellSeconds: 10, startDelaySeconds: 5),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .simulate,
                    pointAction: .none,
                    manualAdvance: false,
                    dwellSeconds: 0,
                    startDelaySeconds: 5
                ),
                lap: [
                    leg(1, 2, .simulate, dwell: 0, .none, waitManual: false, isFinal: false),
                    leg(2, 3, .simulate, dwell: 0, .none, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "teleport-orbit-with-dwell",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .orbit, manualAdvance: false, dwellSeconds: 10, startDelaySeconds: 0),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .orbit,
                    manualAdvance: false,
                    dwellSeconds: 10,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 10, .orbit, waitManual: false, isFinal: false),
                    leg(2, 3, .teleport, dwell: 10, .orbit, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "teleport-manual-advance-forces-dwell-0",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .microMove, manualAdvance: true, dwellSeconds: 10, startDelaySeconds: 3),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .microMove,
                    manualAdvance: true,
                    dwellSeconds: 0,
                    startDelaySeconds: 3
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 0, .microMove, waitManual: true, isFinal: false),
                    leg(2, 3, .teleport, dwell: 0, .microMove, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "teleport-loop-walk-back",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .orbit, manualAdvance: false, dwellSeconds: 5, startDelaySeconds: 0),
                loop: true,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .orbit,
                    manualAdvance: false,
                    dwellSeconds: 5,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 5, .orbit, waitManual: false, isFinal: false),
                    leg(2, 3, .teleport, dwell: 5, .orbit, waitManual: false, isFinal: false),
                    leg(3, 1, .teleport, dwell: 5, .orbit, waitManual: false, isFinal: false),
                ],
                repeats: true
            ),
            PlanCase(
                name: "teleport-loop-teleport-to-start-never-revisits-point-1",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .microMove, manualAdvance: true, dwellSeconds: 5, startDelaySeconds: 0),
                loop: true,
                transition: .teleportToStart,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .microMove,
                    manualAdvance: true,
                    dwellSeconds: 0,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 0, .microMove, waitManual: true, isFinal: false),
                    leg(2, 3, .teleport, dwell: 0, .microMove, waitManual: true, isFinal: false),
                ],
                repeats: true
            ),
            PlanCase(
                name: "simulate-loop-teleport-to-start",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.simulate, .microMove, manualAdvance: false, dwellSeconds: 5, startDelaySeconds: 10),
                loop: true,
                transition: .teleportToStart,
                effective: RoutePlaybackOptions(
                    travelMode: .simulate,
                    pointAction: .none,
                    manualAdvance: false,
                    dwellSeconds: 0,
                    startDelaySeconds: 10
                ),
                lap: [
                    leg(1, 2, .simulate, dwell: 0, .none, waitManual: false, isFinal: false),
                    leg(2, 3, .simulate, dwell: 0, .none, waitManual: false, isFinal: false),
                ],
                repeats: true
            ),
            PlanCase(
                name: "teleport-legacy-none-with-dwell",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .none, manualAdvance: false, dwellSeconds: 10, startDelaySeconds: 0),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .none,
                    manualAdvance: false,
                    dwellSeconds: 10,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 10, .none, waitManual: false, isFinal: false),
                    leg(2, 3, .teleport, dwell: 10, .none, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "teleport-legacy-none-manual",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .none, manualAdvance: true, dwellSeconds: 10, startDelaySeconds: 0),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .none,
                    manualAdvance: true,
                    dwellSeconds: 0,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 0, .none, waitManual: true, isFinal: false),
                    leg(2, 3, .teleport, dwell: 0, .none, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "teleport-stored-dwell-0-clamped-to-1",
                kind: .multiRoute,
                pointCount: 2,
                stored: stored(.teleport, .orbit, manualAdvance: false, dwellSeconds: 0, startDelaySeconds: 0),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .orbit,
                    manualAdvance: false,
                    dwellSeconds: 1,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 1, .orbit, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "repeated-point-numbered-by-position",
                kind: .multiRoute,
                pointCount: 3,
                stored: stored(.teleport, .orbit, manualAdvance: true, dwellSeconds: 10, startDelaySeconds: 0),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .teleport,
                    pointAction: .orbit,
                    manualAdvance: true,
                    dwellSeconds: 0,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .teleport, dwell: 0, .orbit, waitManual: true, isFinal: false),
                    leg(2, 3, .teleport, dwell: 0, .orbit, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "single-route-ignores-all-options",
                kind: .singleRoute,
                pointCount: 2,
                stored: stored(.teleport, .orbit, manualAdvance: true, dwellSeconds: 10, startDelaySeconds: 10),
                loop: false,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .simulate,
                    pointAction: .none,
                    manualAdvance: false,
                    dwellSeconds: 0,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .simulate, dwell: 0, .none, waitManual: false, isFinal: true),
                ],
                repeats: false
            ),
            PlanCase(
                name: "board-route-start-ignores-all-options",
                kind: .boardRoute,
                pointCount: 3,
                stored: stored(.teleport, .orbit, manualAdvance: true, dwellSeconds: 10, startDelaySeconds: 10),
                loop: true,
                transition: .walkBack,
                effective: RoutePlaybackOptions(
                    travelMode: .simulate,
                    pointAction: .none,
                    manualAdvance: false,
                    dwellSeconds: 0,
                    startDelaySeconds: 0
                ),
                lap: [
                    leg(1, 2, .simulate, dwell: 0, .none, waitManual: false, isFinal: false),
                    leg(2, 3, .simulate, dwell: 0, .none, waitManual: false, isFinal: false),
                    leg(3, 1, .simulate, dwell: 0, .none, waitManual: false, isFinal: false),
                ],
                repeats: true
            ),
        ]
        XCTAssertEqual(cases.count, 12)
        for testCase in cases {
            let effective = RoutePlaybackOptions.effective(for: testCase.kind, settings: testCase.stored)
            XCTAssertEqual(effective, testCase.effective, testCase.name)
            let loop = RoutePlaybackOptions.loops(for: testCase.kind, requested: testCase.loop)
            XCTAssertEqual(loop, testCase.repeats, testCase.name)
            let lap = RouteArrivalPlan.lap(
                pointCount: testCase.pointCount,
                loop: loop,
                transition: testCase.transition,
                options: effective
            )
            XCTAssertEqual(lap, testCase.lap, testCase.name)
        }
    }
}
