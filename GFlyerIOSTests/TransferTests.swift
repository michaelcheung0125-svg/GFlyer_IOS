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
}
