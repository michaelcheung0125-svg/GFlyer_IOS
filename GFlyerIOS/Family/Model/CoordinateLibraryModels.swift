import Foundation

/// 座標圖鑑分類（活動／純點／明信片）。
struct LibraryCategory: Equatable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let subcategories: [LibrarySubcategory]
}

struct LibrarySubcategory: Equatable, Identifiable {
    let id: String
    let name: String
    let startDate: String?
    let endDate: String?
    let defaultRemindDays: Int?
    let defaultNote: String?
}

/// 圖鑑座標。內容由作者維護，使用者不可編輯；`remindDays` 為 nil 時不提供造訪提醒。
struct LibraryCoordinate: Equatable, Identifiable {
    let id: String
    let categoryID: String
    let subcategoryID: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let note: String
    let period: String
    let remindDays: Int?
    let thumbnailURL: URL?
    let icon: String?
    let enabled: Bool
    let updatedAt: String?

    var geoCoordinate: GeoCoordinate? {
        GeoCoordinate.validated(latitude: latitude, longitude: longitude)
    }

    /// 只有明信片可以回報資料已過時,和 Android 相同。`"postcard"` 是圖鑑資料與兩個 App 之間
    /// 的約定,圖鑑改分類代號時兩邊都要跟著改。
    var canReportOutdated: Bool { categoryID == OutdatedReport.categoryID }
}

/// 座標圖鑑「回報資料已過時」的選項與訊息,三個平台一字不差
/// (GFlyer-Suite docs/features/coordinate-stale-report.md)。
enum OutdatedReport {
    static let categoryID = "postcard"
    static let reasons = ["座標位置錯誤", "地點已消失", "資訊過時"]
    static let successMessage = "已送出回報，謝謝你！"
    /// 任何失敗(網路、400、409、429、留言板未設定)都是這一句,不附伺服器的錯誤文字。
    static let failureMessage = "回報送出失敗，請稍後再試"
}

struct LibraryFormatError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// 線上／快取的座標庫資料。解析規則與 GFlyer Android 相同：
/// 寬鬆解析，略過缺欄位的項目；缺 revision 或版本不支援時擲回錯誤。
struct CoordinateLibrary: Equatable {
    static let maxSupportedSchemaVersion = 1
    static let maxNameLength = 80
    static let maxThumbnailURLLength = 400

    let schemaVersion: Int
    let revision: Int64
    let updatedAt: String
    let source: String
    let categories: [LibraryCategory]
    let coordinates: [LibraryCoordinate]

    var enabledCoordinates: [LibraryCoordinate] { coordinates.filter(\.enabled) }

    func category(id: String) -> LibraryCategory? {
        categories.first { $0.id == id }
    }

    static func parse(_ data: Data) throws -> CoordinateLibrary {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw LibraryFormatError(message: "座標庫資料格式不正確。")
        }
        let schemaVersion = intValue(root["schemaVersion"]) ?? 0
        guard (1...maxSupportedSchemaVersion).contains(schemaVersion) else {
            throw LibraryFormatError(message: "座標庫資料版本不支援（\(schemaVersion)）。")
        }
        guard let revision = intValue(root["revision"]).map(Int64.init), revision >= 1 else {
            throw LibraryFormatError(message: "座標庫資料缺少有效的 revision。")
        }

        var categories: [LibraryCategory] = []
        for item in objectArray(root["categories"]) {
            guard let id = trimmedString(item["id"]), let name = trimmedString(item["name"]) else { continue }
            var subcategories: [LibrarySubcategory] = []
            for sub in objectArray(item["subcategories"]) {
                guard let subID = trimmedString(sub["id"]), let subName = trimmedString(sub["name"]) else { continue }
                subcategories.append(
                    LibrarySubcategory(
                        id: subID,
                        name: subName,
                        startDate: trimmedString(sub["startDate"]),
                        endDate: trimmedString(sub["endDate"]),
                        defaultRemindDays: intValue(sub["defaultRemindDays"]).flatMap { $0 > 0 ? $0 : nil },
                        defaultNote: trimmedString(sub["defaultNote"])
                    )
                )
            }
            categories.append(
                LibraryCategory(
                    id: id,
                    name: name,
                    // 分類圖示、頂層的 updatedAt 與 source 原樣保留、不去空白,和 Android 相同
                    // (GFlyer-Suite contracts/fixtures/coordinate-library/type-strictness.expected.json)
                    icon: item["icon"] as? String ?? "",
                    subcategories: subcategories
                )
            )
        }

        let validCategoryIDs = Set(categories.map(\.id))
        var coordinates: [LibraryCoordinate] = []
        for item in objectArray(root["coordinates"]) {
            guard let id = trimmedString(item["id"]),
                  let categoryID = trimmedString(item["categoryId"]),
                  let name = trimmedString(item["name"]),
                  let latitude = doubleValue(item["lat"]),
                  let longitude = doubleValue(item["lng"]),
                  validCategoryIDs.contains(categoryID) else { continue }
            coordinates.append(
                LibraryCoordinate(
                    id: id,
                    categoryID: categoryID,
                    subcategoryID: trimmedString(item["subcategoryId"]),
                    name: name.prefixCodePoints(maxNameLength),
                    latitude: latitude,
                    longitude: longitude,
                    note: (trimmedString(item["note"]) ?? "").prefixCodePoints(300),
                    period: trimmedString(item["period"]) ?? "",
                    remindDays: intValue(item["remindDays"]).flatMap { $0 > 0 ? $0 : nil },
                    thumbnailURL: httpsURL(trimmedString(item["thumbnail"])),
                    icon: trimmedString(item["icon"]).map { $0.prefixCodePoints(8) },
                    enabled: boolValue(item["enabled"]) ?? true,
                    updatedAt: trimmedString(item["updatedAt"])
                )
            )
        }

        return CoordinateLibrary(
            schemaVersion: schemaVersion,
            revision: revision,
            updatedAt: root["updatedAt"] as? String ?? "",
            source: root["source"] as? String ?? "皮克敏純點明信片地圖 pikmin.talllkai.com",
            categories: categories,
            coordinates: coordinates
        )
    }

    /// 逐元素略過不是物件的項目。原本用 `value as? [[String: Any]]`,只要混進一個非物件元素,
    /// 整個集合都會被丟掉;Android 用 `optJSONObject(index) ?: continue`,只略過那一個
    /// (GFlyer-Suite docs/DRIFT.md D17,和備份的 D4 同一個問題)。
    private static func objectArray(_ value: Any?) -> [[String: Any]] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // JSONSerialization 把 true / false 解析成 NSNumber,`as? NSNumber` 分不出布林和數字,
    // `as? Bool` 也會把數字 0 / 1 橋接成布林。和備份(AppBackupCodec)同一條規則:布林不是數字,
    // 數字也不是布林(GFlyer-Suite docs/DRIFT.md D12、coordinate-library/type-strictness.*.json)。

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

    private static func httpsURL(_ text: String?) -> URL? {
        guard let text,
              text.count <= maxThumbnailURLLength,
              text.lowercased().hasPrefix("https://"),
              let url = URL(string: text) else { return nil }
        return url
    }
}

/// 「提醒中」狀態：已到期可再去，或還要等多久（進位到小時）。
enum VisitReminderState: Equatable {
    case ready(nextAvailableAt: Date)
    case waiting(nextAvailableAt: Date, daysLeft: Int, hoursLeft: Int)
}

enum VisitReminder {
    static func nextAvailableAt(markedAt: Date, remindDays: Int) -> Date {
        markedAt.addingTimeInterval(Double(remindDays) * 86_400)
    }

    static func state(markedAt: Date, remindDays: Int, now: Date = Date()) -> VisitReminderState {
        let next = nextAvailableAt(markedAt: markedAt, remindDays: remindDays)
        guard now < next else { return .ready(nextAvailableAt: next) }
        let wholeHours = max(Int(ceil(next.timeIntervalSince(now) / 3_600)), 1)
        return .waiting(
            nextAvailableAt: next,
            daysLeft: wholeHours / 24,
            hoursLeft: wholeHours % 24
        )
    }

    /// 「下次可去時間」的顯示文字，和 Android `DateTimeFormatter.ofPattern("yyyy/MM/dd HH:00")` 一樣：
    /// 西元曆、24 小時制、ASCII 數字；`HH:` 後面的 00 是字面文字，15:59 也寫 15:00，不四捨五入。
    /// `timeZone` 預設在每次呼叫時讀當下的 `TimeZone.current`，和 Android 每次用 `ZoneId.systemDefault()` 一樣。
    /// 期望值見 GFlyer-Suite `contracts/fixtures/reminder/visit-reminder.json` 的 `format`（DRIFT D27）。
    static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        displayFormatter(timeZone: timeZone).string(from: date)
    }

    private static let displayPattern = "yyyy/MM/dd HH:00"

    /// 格式器照時區快取，和 `LibraryTeleportHistory` 的時間文字同一個做法：清單每次重繪都要格式化，
    /// 每次新建 DateFormatter 太貴；NSCache 可以跨執行緒使用，建好之後不再修改的 DateFormatter 也可以。
    private static let displayFormatters = NSCache<NSString, DateFormatter>()

    /// 一定要明確設定 en_US_POSIX、西元曆與時區：不設的話，佛曆／日本曆的 iPhone 會顯示 2569 年或令和年，
    /// 12 小時制的地區也可能蓋掉 HH，部分語系還會換成非 ASCII 數字。Android 的 DateTimeFormatter 本來就不看這些。
    private static func displayFormatter(timeZone: TimeZone) -> DateFormatter {
        let key = NSString(string: timeZone.identifier)
        if let cached = displayFormatters.object(forKey: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = displayPattern
        displayFormatters.setObject(formatter, forKey: key)
        return formatter
    }
}
