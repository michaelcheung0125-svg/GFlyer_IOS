import Foundation

/// 一次補錄步數的紀錄。
///
/// GFlyer 沒有 HealthKit 權限（免費 Apple ID 拿不到該 entitlement），寫入是
/// 交給使用者自建的「捷徑」完成的。所以這裡記的是「GFlyer 送出的補錄」，
/// 不是從健康 App 讀回來的實際步數；`status` 說明捷徑有沒有回報完成。
struct StepRecordEntry: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        /// 已呼叫捷徑，但還沒收到回呼（使用者可能取消了）。
        case pending
        /// 捷徑回報執行成功。
        case confirmed
        /// 捷徑回報失敗。
        case failed

        var label: String {
            switch self {
            case .pending: return "未確認"
            case .confirmed: return "已寫入"
            case .failed: return "失敗"
            }
        }
    }

    let id: UUID
    let steps: Int
    let requestedAt: Date
    var status: Status

    init(id: UUID = UUID(), steps: Int, requestedAt: Date = .now, status: Status = .pending) {
        self.id = id
        self.steps = steps
        self.requestedAt = requestedAt
        self.status = status
    }
}

/// 依日期分組後的一天。
struct StepRecordDay: Identifiable, Equatable {
    let date: Date
    let entries: [StepRecordEntry]

    var id: Date { date }

    /// 只計入捷徑確認寫入的步數，未確認與失敗不列入總數。
    var confirmedSteps: Int {
        entries.filter { $0.status == .confirmed }.reduce(0) { $0 + $1.steps }
    }

    var hasUnconfirmed: Bool {
        entries.contains { $0.status != .confirmed }
    }
}

enum StepRecordHistory {
    static let retainedDays = 7
    static let minimumSteps = 1
    static let maximumSteps = 100_000
    static let presetStepCounts = [1_000, 3_000, 5_000]

    static func clampSteps(_ steps: Int) -> Int {
        min(max(steps, minimumSteps), maximumSteps)
    }

    /// 只保留最近七天（含今天）的紀錄。
    static func pruned(
        _ entries: [StepRecordEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [StepRecordEntry] {
        guard let cutoff = calendar.date(
            byAdding: .day,
            value: -(retainedDays - 1),
            to: calendar.startOfDay(for: now)
        ) else { return entries }
        return entries.filter { $0.requestedAt >= cutoff }
    }

    /// 依日期由新到舊分組；同一天內也是新的在前。
    static func groupedByDay(
        _ entries: [StepRecordEntry],
        calendar: Calendar = .current
    ) -> [StepRecordDay] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.requestedAt) }
            .map { StepRecordDay(date: $0.key, entries: $0.value.sorted { $0.requestedAt > $1.requestedAt }) }
            .sorted { $0.date > $1.date }
    }
}
