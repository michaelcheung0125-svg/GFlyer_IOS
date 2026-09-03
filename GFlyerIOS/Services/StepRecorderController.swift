import Combine
import Foundation
import UIKit

/// 透過使用者自建的「捷徑」把步數寫入健康 App。
///
/// GFlyer 本身不要求 HealthKit entitlement——免費 Apple ID 拿不到它，而且
/// SideStore 重簽時會把它剝離。改由捷徑用它自己的權限寫入，所以免費與付費
/// 帳號都能用。App 只負責帶出步數、接回結果並保留最近七天的紀錄。
@MainActor
final class StepRecorderController: ObservableObject {
    @Published private(set) var entries: [StepRecordEntry] = []
    @Published private(set) var lastMessage: String?
    @Published var lastError: String?
    @Published var shortcutName: String {
        didSet {
            let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: shortcutNameKey)
        }
    }

    static let defaultShortcutName = "GFlyer 補錄步數"
    /// x-callback-url 回呼用的自訂 scheme，需與 Info.plist 的 CFBundleURLTypes 一致。
    static let callbackScheme = "gflyer"

    private let defaults: UserDefaults
    private let entriesKey = "gflyer.step-records.v1"
    private let shortcutNameKey = "gflyer.step-shortcut-name"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcutName = (defaults.string(forKey: shortcutNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultShortcutName
        entries = StepRecordHistory.pruned(loadEntries())
    }

    var isShortcutsInstalled: Bool {
        guard let url = URL(string: "shortcuts://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    var days: [StepRecordDay] {
        StepRecordHistory.groupedByDay(entries)
    }

    var todaySteps: Int {
        days.first(where: { Calendar.current.isDateInToday($0.date) })?.confirmedSteps ?? 0
    }

    var sevenDaySteps: Int {
        days.reduce(0) { $0 + $1.confirmedSteps }
    }

    // MARK: - 送出

    /// 建立待確認紀錄並算出要開啟的捷徑網址。`record` 與測試共用這條路徑，
    /// 所以不需要測試專用的後門。名稱或網址有問題時回傳 nil 並設定 lastError。
    func prepareRecord(steps rawSteps: Int) -> (entry: StepRecordEntry, url: URL)? {
        let steps = StepRecordHistory.clampSteps(rawSteps)
        let trimmedName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = "請先在下方填寫你的捷徑名稱。"
            return nil
        }
        let entry = StepRecordEntry(steps: steps)
        guard let url = Self.runShortcutURL(name: trimmedName, steps: steps, entryID: entry.id) else {
            lastError = "無法組出捷徑連結，請確認捷徑名稱。"
            return nil
        }
        entries.insert(entry, at: 0)
        persist()
        return (entry, url)
    }

    func record(steps rawSteps: Int, application: UIApplication = .shared) {
        lastError = nil
        lastMessage = nil
        guard isShortcutsInstalled else {
            lastError = "找不到「捷徑」App。請先從 App Store 安裝，並建立一個接收步數並寫入健康的捷徑。"
            return
        }
        guard let prepared = prepareRecord(steps: rawSteps) else { return }
        application.open(prepared.url, options: [:]) { [weak self] opened in
            guard let self, !opened else { return }
            Task { @MainActor in
                self.updateStatus(id: prepared.entry.id, to: .failed)
                self.lastError = "無法開啟捷徑 App。"
            }
        }
    }

    // MARK: - 回呼

    /// 處理 `gflyer://steps/done`、`gflyer://steps/failed` 兩種回呼。
    /// 回傳是否為本控制器負責的網址。
    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == Self.callbackScheme,
              url.host?.lowercased() == "steps" else { return false }
        let action = url.lastPathComponent.lowercased()
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value
            .flatMap(UUID.init(uuidString:))

        switch action {
        case "done":
            if let id { updateStatus(id: id, to: .confirmed) }
            let steps = id.flatMap { target in entries.first(where: { $0.id == target })?.steps }
            lastMessage = steps.map { "已透過捷徑寫入 \($0) 步。" } ?? "捷徑已完成寫入。"
        case "failed":
            if let id { updateStatus(id: id, to: .failed) }
            lastError = "捷徑回報寫入失敗，請檢查捷徑內容。"
        default:
            return false
        }
        return true
    }

    // MARK: - 紀錄管理

    func clearHistory() {
        entries = []
        persist()
    }

    private func updateStatus(id: UUID, to status: StepRecordEntry.Status) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        persist()
    }

    private func persist() {
        entries = StepRecordHistory.pruned(entries)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: entriesKey)
    }

    private func loadEntries() -> [StepRecordEntry] {
        guard let data = defaults.data(forKey: entriesKey),
              let stored = try? JSONDecoder().decode([StepRecordEntry].self, from: data) else {
            return []
        }
        return stored
    }

    // MARK: - 網址

    /// 用 x-callback-url 呼叫捷徑：捷徑跑完會回到 GFlyer，讓紀錄能標成已寫入。
    static func runShortcutURL(name: String, steps: Int, entryID: UUID) -> URL? {
        let success = "\(callbackScheme)://steps/done?id=\(entryID.uuidString)"
        let failure = "\(callbackScheme)://steps/failed?id=\(entryID.uuidString)"
        let query = [
            "name=\(escape(name))",
            "input=text",
            "text=\(steps)",
            "x-success=\(escape(success))",
            "x-error=\(escape(failure))",
        ].joined(separator: "&")
        return URL(string: "shortcuts://x-callback-url/run-shortcut?\(query)")
    }

    /// 逐字元編碼：巢狀網址裡的 `?`、`&`、`=` 一定要編碼，否則會被外層網址吃掉。
    private static func escape(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
