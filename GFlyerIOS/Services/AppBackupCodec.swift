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

    /// 這個平台不認識的 settings 鍵,序列化後原樣保留,匯出時寫回。
    ///
    /// 沒有這一步的話,Android 匯出的 15 個設定(懸浮視窗位置、地圖供應商、
    /// 循環模式等)會在「Android 匯出 -> iOS 匯入 -> iOS 匯出 -> Android 匯入」
    /// 這一輪之後全部被重設成預設值,而且沒有任何提示。
    /// 見 GFlyer-Suite 的 docs/DRIFT.md D1。
    var foreignSettings: Data?
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
            "settings": settingsJSON(for: snapshot),
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

        for item in objectArray(root["folders"], limit: 30) {
            guard let longID = intValue(item["id"]).map(Int64.init),
                  let name = item["name"] as? String,
                  folderUUIDs[longID] == nil else { continue }
            let folder = FavoriteFolder(
                name: name.prefixCodePoints(40),
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
                name: name.prefixCodePoints(80),
                coordinate: coordinate,
                createdAt: date(fromMillis: item["createdAt"]),
                folderID: folderID
            )
        }

        payload.favorites = objectArray(root["favorites"], limit: 100)
            .compactMap { place(from: $0, keepFolder: true) }
        payload.history = objectArray(root["history"], limit: 30)
            .compactMap { place(from: $0, keepFolder: false) }

        for item in objectArray(root["routes"], limit: 50) {
            guard let name = item["name"] as? String else { continue }
            let points = objectArray(item["points"], limit: GpxCodec.maxPointsPerRoute)
                .compactMap(coordinate(from:))
            guard points.count >= 2 else { continue }
            payload.routes.append(
                SavedRoute(
                    name: name.prefixCodePoints(80),
                    points: points,
                    loop: boolValue(item["loop"]) ?? false,
                    createdAt: date(fromMillis: item["createdAt"]),
                    folderID: intValue(item["folderId"]).map(Int64.init).flatMap { folderUUIDs[$0] }
                )
            )
        }

        payload.presets = objectArray(root["quickSpeedPresets"], limit: QuickSpeedPreset.maxCount).compactMap { item in
            guard let name = item["name"] as? String,
                  let metresPerSecond = doubleValue(item["metresPerSecond"]) else { return nil }
            return QuickSpeedPreset(
                name: name.prefixCodePoints(QuickSpeedPreset.maxNameLength),
                kilometresPerHour: metresPerSecond * 3.6
            )
        }

        if let settings = root["settings"] as? [String: Any] {
            payload.crossDateWarningEnabled = boolValue(settings["crossDateWarningEnabled"])
            payload.autoStopMinutes = intValue(settings["autoStopMinutes"])
            payload.foreignSettings = encodeForeignSettings(from: settings)
        }
        return payload
    }

    // MARK: - Settings 透傳

    /// 這個平台實際會讀寫的 settings 鍵。不在這裡面的一律視為別的平台的,
    /// 原樣保留。新增本平台支援的設定時,記得同步加進這個集合,
    /// 否則它會被當成外來鍵而不會被自己讀到。
    private static let ownedSettingKeys: Set<String> = [
        "crossDateWarningEnabled",
        "autoStopMinutes",
    ]

    private static func encodeForeignSettings(from settings: [String: Any]) -> Data? {
        let foreign = settings.filter { !ownedSettingKeys.contains($0.key) }
        guard !foreign.isEmpty, JSONSerialization.isValidJSONObject(foreign) else { return nil }
        return try? JSONSerialization.data(withJSONObject: foreign, options: [.sortedKeys])
    }

    private static func settingsJSON(for snapshot: LocalDataSnapshot) -> [String: Any] {
        var settings: [String: Any] = [:]
        if let data = snapshot.foreignSettings,
           let restored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            settings = restored
        }
        // 本平台的值一律覆寫,避免保留下來的舊副本蓋掉現在的設定。
        settings["crossDateWarningEnabled"] = snapshot.playback.crossDateWarningEnabled
        settings["autoStopMinutes"] = snapshot.playback.autoStopMinutes
        return settings
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

    /// 取原始陣列的前 `limit` 個元素(不是物件的也算一個),只保留其中是物件的。
    ///
    /// 和 Android 的 `BackupDecoder` 同一條規則:上限套在原始前 N 個元素上,其中不是物件的
    /// 元素與不合法的項目一律略過(GFlyer-Suite docs/DRIFT.md D4)。原本用
    /// `value as? [[String: Any]]`,只要混進一個非物件元素,整個集合都會被丟掉。
    private static func objectArray(_ value: Any?, limit: Int) -> [[String: Any]] {
        guard let array = value as? [Any] else { return [] }
        return array.prefix(limit).compactMap { $0 as? [String: Any] }
    }

    // JSONSerialization 把 true / false 解析成 NSNumber,`as? NSNumber` 分不出布林和數字,
    // `as? Bool` 也會把數字 0 / 1 橋接成布林。和 Android 的 `as? Number` / `as? Boolean`
    // 一樣嚴格區分:布林不是數字,數字也不是布林(GFlyer-Suite docs/DRIFT.md D12)。

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.intValue
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
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
