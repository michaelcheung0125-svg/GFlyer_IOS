import Foundation

struct BackupImportResult: Equatable {
    let favoriteCount: Int
    let routeCount: Int
    let folderCount: Int
    let presetCount: Int
}

struct BackupPayload: Equatable {
    var folders: [FavoriteFolder] = []
    var favorites: [SavedPlace] = []
    var history: [SavedPlace] = []
    var routes: [SavedRoute] = []
    var presets: [QuickSpeedPreset] = []
    var crossDateWarningEnabled: Bool?
    var autoStopMinutes: Int?
}

enum AppBackupError: LocalizedError {
    case tooLarge
    case invalidFormat
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "備份檔案過大。"
        case .invalidFormat: return "這不是 GFlyer 備份檔案。"
        case .unsupportedVersion: return "不支援這個備份版本。"
        }
    }
}

/// Reads and writes the cross-platform `GFlyer Backup` v1 JSON format shared
/// with GFlyer Android. Android identifies records with 64-bit integers while
/// iOS uses UUIDs, so exporting derives a stable integer from each UUID and
/// importing assigns fresh UUIDs while preserving folder relationships.
enum AppBackupCodec {
    static let formatName = "GFlyer Backup"
    static let formatVersion = 1
    static let maxBackupBytes = 5 * 1024 * 1024

    // MARK: - Export

    static func export(snapshot: LocalDataSnapshot, now: Date = Date()) throws -> Data {
        var usedIDs = Set<Int64>()
        var folderLongIDs: [UUID: Int64] = [:]
        let folders = snapshot.folders.map { folder -> [String: Any] in
            let longID = stableLongID(for: folder.id, used: &usedIDs)
            folderLongIDs[folder.id] = longID
            return [
                "id": longID,
                "name": folder.name,
                "createdAt": millis(folder.createdAt),
            ]
        }

        func folderIDValue(_ folderID: UUID?) -> Any {
            if let folderID, let longID = folderLongIDs[folderID] { return longID }
            return NSNull()
        }

        func placeJSON(_ place: SavedPlace) -> [String: Any] {
            [
                "id": stableLongID(for: place.id, used: &usedIDs),
                "name": place.name,
                "latitude": place.coordinate.latitude,
                "longitude": place.coordinate.longitude,
                "createdAt": millis(place.createdAt),
                "folderId": folderIDValue(place.folderID),
            ]
        }

        func routeJSON(_ route: SavedRoute) -> [String: Any] {
            [
                "id": stableLongID(for: route.id, used: &usedIDs),
                "name": route.name,
                "points": route.points.map { ["latitude": $0.latitude, "longitude": $0.longitude] },
                "loop": route.loop,
                "createdAt": millis(route.createdAt),
                "folderId": folderIDValue(route.folderID),
            ]
        }

        let root: [String: Any] = [
            "format": formatName,
            "version": formatVersion,
            "exportedAt": millis(now),
            "folders": folders,
            "favorites": snapshot.favorites.map(placeJSON),
            "history": snapshot.history.map(placeJSON),
            "routes": snapshot.routes.map(routeJSON),
            "quickSpeedPresets": snapshot.presets.map { preset -> [String: Any] in
                [
                    "id": stableLongID(for: preset.id, used: &usedIDs),
                    "name": preset.name,
                    "metresPerSecond": preset.kilometresPerHour / 3.6,
                ]
            },
            "settings": [
                "crossDateWarningEnabled": snapshot.playback.crossDateWarningEnabled,
                "autoStopMinutes": snapshot.playback.autoStopMinutes,
            ] as [String: Any],
        ]
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - Import

    static func decode(_ data: Data) throws -> BackupPayload {
        guard data.count <= maxBackupBytes else { throw AppBackupError.tooLarge }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AppBackupError.invalidFormat
        }
        guard root["format"] as? String == formatName else { throw AppBackupError.invalidFormat }
        let version = intValue(root["version"]) ?? 0
        guard (1...formatVersion).contains(version) else { throw AppBackupError.unsupportedVersion }

        var payload = BackupPayload()
        var folderUUIDs: [Int64: UUID] = [:]

        for item in objectArray(root["folders"]).prefix(30) {
            guard let longID = intValue(item["id"]).map(Int64.init),
                  let name = item["name"] as? String,
                  folderUUIDs[longID] == nil else { continue }
            let folder = FavoriteFolder(
                name: String(name.prefix(40)),
                createdAt: date(fromMillis: item["createdAt"])
            )
            folderUUIDs[longID] = folder.id
            payload.folders.append(folder)
        }

        func place(from item: [String: Any], keepFolder: Bool) -> SavedPlace? {
            guard let name = item["name"] as? String,
                  let coordinate = coordinate(from: item) else { return nil }
            let folderID = keepFolder
                ? intValue(item["folderId"]).map(Int64.init).flatMap { folderUUIDs[$0] }
                : nil
            return SavedPlace(
                name: String(name.prefix(80)),
                coordinate: coordinate,
                createdAt: date(fromMillis: item["createdAt"]),
                folderID: folderID
            )
        }

        payload.favorites = objectArray(root["favorites"]).prefix(100)
            .compactMap { place(from: $0, keepFolder: true) }
        payload.history = objectArray(root["history"]).prefix(30)
            .compactMap { place(from: $0, keepFolder: false) }

        for item in objectArray(root["routes"]).prefix(50) {
            guard let name = item["name"] as? String else { continue }
            let points = objectArray(item["points"])
                .prefix(GpxCodec.maxPointsPerRoute)
                .compactMap(coordinate(from:))
            guard points.count >= 2 else { continue }
            payload.routes.append(
                SavedRoute(
                    name: String(name.prefix(80)),
                    points: points,
                    loop: item["loop"] as? Bool ?? false,
                    createdAt: date(fromMillis: item["createdAt"]),
                    folderID: intValue(item["folderId"]).map(Int64.init).flatMap { folderUUIDs[$0] }
                )
            )
        }

        payload.presets = objectArray(root["quickSpeedPresets"]).prefix(12).compactMap { item in
            guard let name = item["name"] as? String,
                  let metresPerSecond = doubleValue(item["metresPerSecond"]) else { return nil }
            return QuickSpeedPreset(
                name: String(name.prefix(20)),
                kilometresPerHour: metresPerSecond * 3.6
            )
        }

        if let settings = root["settings"] as? [String: Any] {
            payload.crossDateWarningEnabled = settings["crossDateWarningEnabled"] as? Bool
            payload.autoStopMinutes = intValue(settings["autoStopMinutes"])
        }
        return payload
    }

    // MARK: - Helpers

    private static func millis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func date(fromMillis value: Any?) -> Date {
        guard let millis = intValue(value).map(Int64.init), millis > 0 else { return .now }
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private static func coordinate(from item: [String: Any]) -> GeoCoordinate? {
        guard let latitude = doubleValue(item["latitude"]),
              let longitude = doubleValue(item["longitude"]) else { return nil }
        return GeoCoordinate.validated(latitude: latitude, longitude: longitude)
    }

    private static func objectArray(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, !(number is NSNull) { return number.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !(number is NSNull) { return number.doubleValue }
        return nil
    }

    /// FNV-1a over the UUID bytes, masked positive; bumped on collision so
    /// every exported record keeps a unique Android-style integer id.
    private static func stableLongID(for uuid: UUID, used: inout Set<Int64>) -> Int64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x1_0000_0000_01b3
            }
        }
        var value = Int64(bitPattern: hash & 0x7fff_ffff_ffff_ffff)
        while used.contains(value) || value == 0 { value &+= 1 }
        used.insert(value)
        return value
    }
}
