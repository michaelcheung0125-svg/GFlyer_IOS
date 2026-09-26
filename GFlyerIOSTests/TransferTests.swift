import XCTest
@testable import GFlyerIOS

final class TransferTests: XCTestCase {
    // MARK: - GPX

    func testGpxWriteReadRoundTrip() throws {
        let routes = [
            GpxCodec.ExportRoute(name: "維港路線", points: [
                GeoCoordinate(latitude: 22.3193, longitude: 114.1694),
                GeoCoordinate(latitude: 22.2988, longitude: 114.1722),
            ]),
            GpxCodec.ExportRoute(name: "A & B <測試>", points: [
                GeoCoordinate(latitude: 25.0330, longitude: 121.5654),
                GeoCoordinate(latitude: 25.0478, longitude: 121.5319),
                GeoCoordinate(latitude: 25.0340, longitude: 121.5645),
            ]),
        ]
        let data = GpxCodec.write(routes: routes)
        let imported = GpxCodec.readRoutes(from: data)
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].name, "維港路線")
        XCTAssertEqual(imported[0].points, routes[0].points)
        XCTAssertEqual(imported[1].name, "A & B <測試>")
        XCTAssertEqual(imported[1].points.count, 3)
    }

    func testGpxReadUsesWaypointFallbackAndSkipsInvalidPoints() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Other" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="22.3" lon="114.1"><name>甲</name></wpt>
          <wpt lat="999" lon="114.2"></wpt>
          <wpt lat="22.4" lon="114.2"></wpt>
        </gpx>
        """
        let routes = GpxCodec.readRoutes(from: Data(xml.utf8))
        XCTAssertEqual(routes.count, 1)
        XCTAssertNil(routes[0].name)
        XCTAssertEqual(routes[0].points.count, 2)
    }

    func testGpxReadIgnoresSinglePointTrack() {
        let xml = """
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>短</name><trkseg><trkpt lat="22.3" lon="114.1"></trkpt></trkseg></trk>
        </gpx>
        """
        XCTAssertTrue(GpxCodec.readRoutes(from: Data(xml.utf8)).isEmpty)
    }

    // MARK: - Backup

    func testBackupExportDecodeRoundTripKeepsFolderRelations() throws {
        var snapshot = LocalDataSnapshot()
        let folder = FavoriteFolder(name: "香港")
        snapshot.folders = [folder]
        snapshot.favorites = [
            SavedPlace(
                name: "中環",
                coordinate: GeoCoordinate(latitude: 22.2819, longitude: 114.1582),
                folderID: folder.id
            ),
            SavedPlace(name: "未分類", coordinate: GeoCoordinate(latitude: 22.3, longitude: 114.2)),
        ]
        snapshot.routes = [
            SavedRoute(
                name: "上班路線",
                points: [
                    GeoCoordinate(latitude: 22.28, longitude: 114.15),
                    GeoCoordinate(latitude: 22.29, longitude: 114.16),
                ],
                loop: true,
                folderID: folder.id
            ),
        ]
        snapshot.presets = [QuickSpeedPreset(name: "慢走", kilometresPerHour: 3.6)]
        snapshot.playback.crossDateWarningEnabled = false
        snapshot.playback.autoStopMinutes = 60

        let data = try AppBackupCodec.export(snapshot: snapshot)
        let payload = try AppBackupCodec.decode(data)

        XCTAssertEqual(payload.folders.count, 1)
        XCTAssertEqual(payload.folders.first?.name, "香港")
        XCTAssertEqual(payload.favorites.count, 2)
        XCTAssertEqual(payload.favorites.first?.folderID, payload.folders.first?.id)
        XCTAssertNil(payload.favorites.last?.folderID)
        XCTAssertEqual(payload.routes.first?.folderID, payload.folders.first?.id)
        XCTAssertEqual(payload.routes.first?.loop, true)
        XCTAssertEqual(payload.presets.first?.kilometresPerHour ?? 0, 3.6, accuracy: 0.01)
        XCTAssertEqual(payload.crossDateWarningEnabled, false)
        XCTAssertEqual(payload.autoStopMinutes, 60)
    }

    func testBackupDecodeAcceptsAndroidFixture() throws {
        let json = """
        {
          "format": "GFlyer Backup",
          "version": 1,
          "exportedAt": 1756694400000,
          "folders": [{"id": 3, "name": "活動", "createdAt": 1756694400000}],
          "favorites": [
            {"id": 11, "name": "純點", "latitude": 35.6, "longitude": 139.7,
             "createdAt": 1756694400000, "folderId": 3},
            {"id": 12, "name": "孤兒", "latitude": 34.0, "longitude": 135.0,
             "createdAt": 1756694400000, "folderId": 99}
          ],
          "history": [],
          "routes": [
            {"id": 21, "name": "巡迴", "loop": false, "createdAt": 1756694400000,
             "folderId": null,
             "points": [
               {"latitude": 35.6, "longitude": 139.7},
               {"latitude": 35.7, "longitude": 139.8}
             ]}
          ],
          "quickSpeedPresets": [
            {"id": 31, "name": "跑步", "metresPerSecond": 3.0}
          ],
          "settings": {"crossDateWarningEnabled": true, "autoStopMinutes": 30}
        }
        """
        let payload = try AppBackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(payload.folders.count, 1)
        XCTAssertEqual(payload.favorites.count, 2)
        XCTAssertEqual(payload.favorites[0].folderID, payload.folders[0].id)
        XCTAssertEqual(payload.routes.count, 1)
        XCTAssertEqual(payload.presets.first?.kilometresPerHour ?? 0, 10.8, accuracy: 0.01)
        XCTAssertEqual(payload.autoStopMinutes, 30)

        // An orphan folder reference is dropped when the payload is applied.
        let suiteName = "gflyer.backup-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let result = store.applyBackup(payload)
        XCTAssertEqual(result.favoriteCount, 2)
        XCTAssertNil(store.snapshot.favorites.last?.folderID)
        XCTAssertEqual(store.snapshot.playback.autoStopMinutes, 30)
    }

    func testBackupDecodeRejectsWrongFormatAndVersion() {
        XCTAssertThrowsError(try AppBackupCodec.decode(Data("{\"format\":\"別的\"}".utf8))) { error in
            XCTAssertEqual(error as? AppBackupError, .invalidFormat)
        }
        let future = "{\"format\":\"GFlyer Backup\",\"version\":99}"
        XCTAssertThrowsError(try AppBackupCodec.decode(Data(future.utf8))) { error in
            XCTAssertEqual(error as? AppBackupError, .unsupportedVersion)
        }
    }

    @MainActor
    func testControllerImportsGpxWithUniqueNames() {
        let suiteName = "gflyer.gpx-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        store.saveRoute(
            name: "維港路線",
            points: [
                GeoCoordinate(latitude: 1, longitude: 1),
                GeoCoordinate(latitude: 2, longitude: 2),
            ],
            loop: false
        )
        let controller = SimulationController(backend: PreviewLocationSimulationBackend(), dataStore: store)

        let gpx = GpxCodec.write(routes: [
            GpxCodec.ExportRoute(name: "維港路線", points: [
                GeoCoordinate(latitude: 22.3, longitude: 114.1),
                GeoCoordinate(latitude: 22.4, longitude: 114.2),
            ]),
        ])
        XCTAssertEqual(controller.importGpxData(gpx), 1)
        XCTAssertEqual(controller.savedRoutes.count, 2)
        XCTAssertTrue(controller.savedRoutes.contains { $0.name == "維港路線 2" })
        XCTAssertEqual(controller.mode, .multiRoute)
        XCTAssertEqual(controller.routePoints.count, 2)
    }

    // MARK: - 跨平台 settings 透傳（DRIFT D1）

    /// Android 匯出 -> iOS 匯入 -> iOS 匯出 之後，Android 專屬的設定必須還在。
    /// 沒有這個行為的話，使用者的懸浮視窗位置、地圖供應商、循環模式等等
    /// 會在往返一次之後被靜默重設成預設值。
    func testBackupPreservesForeignSettingsAcrossRoundTrip() throws {
        let androidExport = """
        {
          "format": "GFlyer Backup",
          "version": 1,
          "exportedAt": 1758585600000,
          "folders": [],
          "favorites": [],
          "history": [],
          "routes": [],
          "quickSpeedPresets": [],
          "settings": {
            "crossDateWarningEnabled": false,
            "autoStopMinutes": 30,
            "loopRoute": true,
            "loopTransitionMode": "TELEPORT_TO_START",
            "floatingControlsEnabled": false,
            "floatingStatusBarAnchor": "TOP_RIGHT",
            "floatingStatusBarOffsetX": 120,
            "floatingStatusBarTextSizeSp": 14,
            "manualStepCount": 5,
            "mapProvider": "OPEN_STREET_MAP"
          }
        }
        """

        let payload = try AppBackupCodec.decode(Data(androidExport.utf8))
        XCTAssertEqual(payload.crossDateWarningEnabled, false)
        XCTAssertEqual(payload.autoStopMinutes, 30)
        XCTAssertNotNil(payload.foreignSettings, "Android 專屬的鍵必須被保留下來")

        var snapshot = LocalDataSnapshot()
        snapshot.playback.crossDateWarningEnabled = try XCTUnwrap(payload.crossDateWarningEnabled)
        snapshot.playback.autoStopMinutes = try XCTUnwrap(payload.autoStopMinutes)
        snapshot.foreignSettings = payload.foreignSettings

        let exported = try AppBackupCodec.export(snapshot: snapshot)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])

        // Android 專屬的鍵原封不動
        XCTAssertEqual(settings["loopRoute"] as? Bool, true)
        XCTAssertEqual(settings["loopTransitionMode"] as? String, "TELEPORT_TO_START")
        XCTAssertEqual(settings["floatingControlsEnabled"] as? Bool, false)
        XCTAssertEqual(settings["floatingStatusBarAnchor"] as? String, "TOP_RIGHT")
        XCTAssertEqual(settings["floatingStatusBarOffsetX"] as? Int, 120)
        XCTAssertEqual(settings["floatingStatusBarTextSizeSp"] as? Int, 14)
        XCTAssertEqual(settings["manualStepCount"] as? Int, 5)
        XCTAssertEqual(settings["mapProvider"] as? String, "OPEN_STREET_MAP")

        // 本平台的鍵也還在
        XCTAssertEqual(settings["crossDateWarningEnabled"] as? Bool, false)
        XCTAssertEqual(settings["autoStopMinutes"] as? Int, 30)
        XCTAssertEqual(settings.count, 10, "不該多出或少掉任何鍵")
    }

    /// 保留下來的副本不可以蓋掉本平台目前的設定。
    func testOwnSettingsWinOverPreservedCopy() throws {
        let stale = """
        {
          "format": "GFlyer Backup",
          "version": 1,
          "settings": { "crossDateWarningEnabled": false, "autoStopMinutes": 30, "loopRoute": true }
        }
        """
        let payload = try AppBackupCodec.decode(Data(stale.utf8))

        var snapshot = LocalDataSnapshot()
        snapshot.foreignSettings = payload.foreignSettings
        // 使用者之後在 iOS 上改了這兩項
        snapshot.playback.crossDateWarningEnabled = true
        snapshot.playback.autoStopMinutes = 90

        let exported = try AppBackupCodec.export(snapshot: snapshot)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])

        XCTAssertEqual(settings["crossDateWarningEnabled"] as? Bool, true)
        XCTAssertEqual(settings["autoStopMinutes"] as? Int, 90)
        XCTAssertEqual(settings["loopRoute"] as? Bool, true, "外來鍵仍然保留")
    }

    /// 沒有 settings 區塊時不該憑空生出外來鍵。
    func testNoForeignSettingsWhenBackupHasNone() throws {
        let minimal = """
        {
          "format": "GFlyer Backup",
          "version": 1,
          "settings": { "crossDateWarningEnabled": true, "autoStopMinutes": 0 }
        }
        """
        let payload = try AppBackupCodec.decode(Data(minimal.utf8))
        XCTAssertNil(payload.foreignSettings)
    }

    // MARK: - 單一筆壞掉只略過那一筆(DRIFT D4)

    /// 陣列裡混進一個不是物件的元素,原本會讓整個集合被丟掉;現在只略過那一個。
    func testBackupDecodeSkipsNonObjectEntriesInsteadOfDroppingTheList() throws {
        let json = """
        {
          "format": "GFlyer Backup",
          "version": 1,
          "favorites": [
            {"id": 1, "name": "第一個", "latitude": 25.0, "longitude": 121.5, "createdAt": 10},
            42,
            "不是物件",
            {"id": 2, "name": "第二個", "latitude": 25.1, "longitude": 121.6, "createdAt": 10},
            {"id": 3, "latitude": 25.2, "longitude": 121.7, "createdAt": 10}
          ],
          "routes": [
            {"id": 4, "name": "路線", "points": [
              {"latitude": 25.0, "longitude": 121.5},
              "不是點",
              {"latitude": 25.1, "longitude": 121.6}
            ]}
          ]
        }
        """
        let payload = try AppBackupCodec.decode(Data(json.utf8))

        XCTAssertEqual(payload.favorites.map(\.name), ["第一個", "第二個"])
        XCTAssertEqual(payload.routes.first?.points.count, 2, "不是點的元素只略過那一個,路線仍然保留")
    }

    // MARK: - 速度預設上限統一為 6(DRIFT D2)

    func testBackupDecodeKeepsAtMostSixPresets() throws {
        let presets = (1...8)
            .map { #"{"id": \#($0), "name": "p\#($0)", "metresPerSecond": 2.0}"# }
            .joined(separator: ",")
        let json = #"{"format": "GFlyer Backup", "version": 1, "quickSpeedPresets": [\#(presets)]}"#
        let payload = try AppBackupCodec.decode(Data(json.utf8))

        XCTAssertEqual(QuickSpeedPreset.maxCount, 6)
        XCTAssertEqual(payload.presets.map(\.name), ["p1", "p2", "p3", "p4", "p5", "p6"])
    }

    @MainActor
    func testApplyBackupKeepsAtMostSixPresets() {
        let suiteName = "gflyer.preset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)

        var payload = BackupPayload()
        payload.presets = (1...8).map { QuickSpeedPreset(name: "p\($0)", kilometresPerHour: 10) }
        let result = store.applyBackup(payload)

        XCTAssertEqual(store.snapshot.presets.count, 6)
        XCTAssertEqual(result.presetCount, 6)
    }

    /// 舊版允許 12 個。已經存了超過 6 個的人,刪掉一個只會少一個,不會被一次截到 6 個。
    @MainActor
    func testExistingPresetsAboveSixSurviveRemovingOne() {
        let suiteName = "gflyer.preset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let ten = (1...10).map { QuickSpeedPreset(name: "p\($0)", kilometresPerHour: 10) }
        store.savePresets(ten)

        let controller = SimulationController(backend: PreviewLocationSimulationBackend(), dataStore: store)
        XCTAssertEqual(controller.quickSpeedPresets.count, 10)

        controller.removeQuickSpeedPreset(ten[9].id)
        XCTAssertEqual(controller.quickSpeedPresets.count, 9)
    }

    @MainActor
    func testControllerRefusesToAddBeyondSixPresets() {
        let suiteName = "gflyer.preset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalDataStore(defaults: defaults)
        let controller = SimulationController(backend: PreviewLocationSimulationBackend(), dataStore: store)
        XCTAssertEqual(controller.quickSpeedPresets.count, SpeedScale.defaultPresets.count)

        controller.saveQuickSpeedPreset(name: "第六個", speed: 30)
        XCTAssertEqual(controller.quickSpeedPresets.count, 6)

        controller.saveQuickSpeedPreset(name: "第七個", speed: 40)
        XCTAssertEqual(controller.quickSpeedPresets.count, 6, "滿 6 個時不可再新增")
        XCTAssertFalse(controller.quickSpeedPresets.contains { $0.name == "第七個" })
    }
}
