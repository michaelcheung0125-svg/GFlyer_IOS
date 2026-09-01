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
                    icon: trimmedString(item["icon"]) ?? "",
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
                    name: String(name.prefix(maxNameLength)),
                    latitude: latitude,
                    longitude: longitude,
                    note: String((trimmedString(item["note"]) ?? "").prefix(300)),
                    period: trimmedString(item["period"]) ?? "",
                    remindDays: intValue(item["remindDays"]).flatMap { $0 > 0 ? $0 : nil },
                    thumbnailURL: httpsURL(trimmedString(item["thumbnail"])),
                    icon: trimmedString(item["icon"]).map { String($0.prefix(8)) },
                    enabled: item["enabled"] as? Bool ?? true,
                    updatedAt: trimmedString(item["updatedAt"])
                )
            )
        }

        return CoordinateLibrary(
            schemaVersion: schemaVersion,
            revision: revision,
            updatedAt: trimmedString(root["updatedAt"]) ?? "",
            source: trimmedString(root["source"]) ?? "皮克敏純點明信片地圖 pikmin.talllkai.com",
            categories: categories,
            coordinates: coordinates
        )
    }

    private static func objectArray(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
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

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:00"
        return formatter
    }()

    static func format(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
}
