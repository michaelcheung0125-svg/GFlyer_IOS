import Foundation

/// 在圖鑑按「傳送」的紀錄:最後一次前往時間(epoch 毫秒)與累計次數。
struct LibraryTeleportRecord: Equatable {
    let lastAtEpochMs: Int64
    let count: Int
}

/// 一個分頁的清單結果:「隱藏已前往」之後的座標,加上隱藏之前算的「已前往 N / 總數」。
struct LibraryTeleportListing {
    /// 畫面要列出的座標,保持原本的順序。
    let visible: [LibraryCoordinate]
    let teleportedCount: Int
    let total: Int
    /// 「⏲ 提醒中」分頁是 false:不隱藏,也不顯示開關列。
    let hideApplies: Bool
    /// 實際有隱藏 = 開關開著而且這個分頁套用。
    let hidesTeleported: Bool

    /// 開關旁的文字;開關列不顯示時是 nil。
    var countLabel: String? {
        hideApplies ? LibraryTeleportHistory.countLabel(teleported: teleportedCount, total: total) : nil
    }

    /// 清單是空的,而且是因為全部都前往過被藏起來(不是本來就沒有符合的座標)。
    var isEmptyBecauseAllTeleported: Bool {
        visible.isEmpty && hidesTeleported && teleportedCount > 0
    }

    /// 清單為空時的標題;清單不為空時是 nil。
    var emptyMessage: String? {
        guard visible.isEmpty else { return nil }
        return isEmptyBecauseAllTeleported ? LibraryTeleportHistory.allTeleportedEmpty : LibraryTeleportHistory.noMatchEmpty
    }
}

/// 座標圖鑑「前往紀錄」的純函式:記錄、序列化、時間文字與「隱藏已前往」篩選,照 Android
/// `model/LibraryTeleportHistory.kt`(GFlyer-Suite docs/features/library-teleport-history.md)。
/// 和造訪提醒標記(`VisitReminder`)分開 —— 按傳送不代表真的拿到東西,所以不會自動開始提醒倒數。
enum LibraryTeleportHistory {
    static let hideToggleOff = "隱藏已前往"
    static let hideToggleOn = "✓ 隱藏已前往"
    static let allTeleportedEmpty = "這裡的點都前往過了；關閉「隱藏已前往」就會再列出來。"
    static let noMatchEmpty = "沒有符合的座標"
    static let clearButton = "清除紀錄"

    /// 次數加 1、時間換成這次的(不比較新舊,時鐘倒退也直接覆寫),其他座標不動。
    static func record(
        _ records: [String: LibraryTeleportRecord],
        id: String,
        nowEpochMs: Int64
    ) -> [String: LibraryTeleportRecord] {
        let previousCount = records[id]?.count ?? 0
        var next = records
        // 次數沒有上限;只防 Int 溢位讓 App 當掉(App 自己寫不出這麼大的數)
        next[id] = LibraryTeleportRecord(
            lastAtEpochMs: nowEpochMs,
            count: previousCount < Int.max ? previousCount + 1 : Int.max
        )
        return next
    }

    /// 開關開著時拿掉有紀錄的座標,不看次數與時間;其餘保持原本順序。
    static func filter(
        _ coordinates: [LibraryCoordinate],
        records: [String: LibraryTeleportRecord],
        hideTeleported: Bool
    ) -> [LibraryCoordinate] {
        hideTeleported ? coordinates.filter { records[$0.id] == nil } : coordinates
    }

    /// `matching` 是分頁、子分類、搜尋與排序之後、隱藏之前的清單。計數一律用它算,
    /// 所以開著隱藏時仍是「已前往 2 / 5」;records 裡不在清單中的 id 不算。
    static func listing(
        _ matching: [LibraryCoordinate],
        records: [String: LibraryTeleportRecord],
        hideTeleported: Bool,
        hideApplies: Bool
    ) -> LibraryTeleportListing {
        let hides = hideTeleported && hideApplies
        return LibraryTeleportListing(
            visible: filter(matching, records: records, hideTeleported: hides),
            teleportedCount: matching.reduce(0) { $0 + (records[$1.id] == nil ? 0 : 1) },
            total: matching.count,
            hideApplies: hideApplies,
            hidesTeleported: hides
        )
    }

    // MARK: - 存放

    /// 和 Android `teleported_map` 同一個形狀:`{"<id>": {"at": <epoch 毫秒>, "n": <次數>}}`。
    private struct StoredRecord: Encodable {
        let at: Int64
        let n: Int
    }

    static func encode(_ records: [String: LibraryTeleportRecord]) -> Data {
        let stored = records.mapValues { StoredRecord(at: $0.lastAtEpochMs, n: $0.count) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(stored)) ?? Data("{}".utf8)
    }

    /// 寬鬆解析,和 Android 相同:整份讀不出來是空的;逐筆壞掉只略過那一筆(值不是物件、at 缺少 /
    /// 不是數字 / ≤ 0);n 缺少、不是數字或 < 1 當成 1。不用 Codable:自動合成的字典解碼只要有一筆
    /// 壞掉就整份失敗。
    static func decode(_ data: Data?) -> [String: LibraryTeleportRecord] {
        guard let data, !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var result: [String: LibraryTeleportRecord] = [:]
        for (id, value) in root {
            guard let item = value as? [String: Any],
                  let at = number(item["at"])?.int64Value, at > 0 else { continue }
            let count = number(item["n"]).map { max($0.intValue, 1) } ?? 1
            result[id] = LibraryTeleportRecord(lastAtEpochMs: at, count: count)
        }
        return result
    }

    /// JSONSerialization 把 true / false 也解析成 NSNumber;布林不算數字,和圖鑑解析、備份同一條規則。
    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }

    // MARK: - 時間文字

    /// 四捨五入到毫秒:用毫秒整數建出來的 `Date` 乘回去可能差一點浮點誤差,取整數部分會少 1 毫秒。
    static func epochMs(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    /// 列表用:at 與 now 在 `timeZone` 裡是同一個西元年時省略年份,否則(包括比 now 晚的年份)寫年份。
    static func formatShort(
        epochMs: Int64,
        nowEpochMs: Int64 = LibraryTeleportHistory.epochMs(Date()),
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let at = date(epochMs)
        let sameYear = calendar.component(.year, from: at) == calendar.component(.year, from: date(nowEpochMs))
        return formatter(sameYear ? shortPattern : fullPattern, timeZone: timeZone).string(from: at)
    }

    /// 「⋯」選單用:一律寫年份。
    static func formatFull(epochMs: Int64, timeZone: TimeZone = .current) -> String {
        formatter(fullPattern, timeZone: timeZone).string(from: date(epochMs))
    }

    /// 紀錄那一行「➤ 已前往 09/19 14:32 · 3 次」;只去過一次就不寫次數。`time` 是 `formatShort` 或 `formatFull`。
    static func summary(_ record: LibraryTeleportRecord, time: String) -> String {
        record.count > 1 ? "➤ 已前往 \(time) · \(record.count) 次" : "➤ 已前往 \(time)"
    }

    /// 「隱藏已前往」開關旁的進度;兩個數字都用隱藏之前的清單算。
    static func countLabel(teleported: Int, total: Int) -> String {
        "已前往 \(teleported) / \(total)"
    }

    private static let shortPattern = "MM/dd HH:mm"
    private static let fullPattern = "yyyy/MM/dd HH:mm"

    /// 格式器照格式與時區快取。清單每次重繪都要格式化看得到的每一列,每次新建 DateFormatter 太貴;
    /// NSCache 可以跨執行緒使用,建好之後不再修改的 DateFormatter 也可以。
    private static let formatters = NSCache<NSString, DateFormatter>()

    /// 一定要明確設定 en_US_POSIX、西元曆與時區:不設的話,佛曆 / 日本曆的 iPhone 會顯示 2569 年或令和年,
    /// 12 小時制的地區也可能蓋掉 HH。Android 的 DateTimeFormatter 本來就不看裝置語系與曆法。
    private static func formatter(_ pattern: String, timeZone: TimeZone) -> DateFormatter {
        let key = NSString(string: "\(pattern)|\(timeZone.identifier)")
        if let cached = formatters.object(forKey: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        formatters.setObject(formatter, forKey: key)
        return formatter
    }

    private static func date(_ epochMs: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epochMs) / 1_000)
    }
}
