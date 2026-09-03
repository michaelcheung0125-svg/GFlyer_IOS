import SwiftUI

struct StepRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var recorder: StepRecorderController
    @State private var showCustomPrompt = false
    @State private var customSteps = "2000"
    @State private var showQuickCustomPrompt = false
    @State private var quickCustomSteps = ""
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                recordSection
                quickSection
                historySection
                shortcutSection
                helpSection
            }
            .navigationTitle("補錄步數")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("自訂步數", isPresented: $showCustomPrompt) {
                TextField("步數", text: $customSteps)
                    .keyboardType(.numberPad)
                Button("補錄") {
                    if let steps = Int(customSteps.trimmingCharacters(in: .whitespaces)) {
                        recorder.record(steps: steps)
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("可輸入 \(StepRecordHistory.minimumSteps) 至 \(StepRecordHistory.maximumSteps) 之間的步數。")
            }
            .alert("一鍵補錄步數", isPresented: $showQuickCustomPrompt) {
                TextField("步數", text: $quickCustomSteps)
                    .keyboardType(.numberPad)
                Button("設定") {
                    if let steps = Int(quickCustomSteps.trimmingCharacters(in: .whitespaces)) {
                        recorder.quickStepCount = steps
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("設定地圖工具列上那個按鈕每次補錄的步數。")
            }
            .alert("清除紀錄", isPresented: $showClearConfirm) {
                Button("清除", role: .destructive) { recorder.clearHistory() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只會清掉 GFlyer 這邊的補錄紀錄，已經寫進健康 App 的步數不受影響。")
            }
            .alert(
                "補錄步數",
                isPresented: Binding(
                    get: { recorder.lastMessage != nil },
                    set: { if !$0 { recorder.lastMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) { recorder.lastMessage = nil }
            } message: {
                Text(recorder.lastMessage ?? "")
            }
            .alert(
                "操作失敗",
                isPresented: Binding(
                    get: { recorder.lastError != nil },
                    set: { if !$0 { recorder.lastError = nil } }
                )
            ) {
                Button("確定", role: .cancel) { recorder.lastError = nil }
            } message: {
                Text(recorder.lastError ?? "")
            }
        }
    }

    // MARK: - 補錄

    private var recordSection: some View {
        Section("補錄步數") {
            HStack(spacing: 10) {
                ForEach(StepRecordHistory.presetStepCounts, id: \.self) { steps in
                    Button {
                        recorder.record(steps: steps)
                    } label: {
                        Text("\(steps)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            Button {
                showCustomPrompt = true
            } label: {
                Label("自訂步數", systemImage: "slider.horizontal.3")
            }
            Text("按下後會開啟「捷徑」App 執行你的捷徑，寫入完成會自動跳回 GFlyer。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 一鍵補錄

    /// 地圖工具列那個按鈕的設定。
    private var quickSection: some View {
        Section {
            Picker("每次補錄", selection: $recorder.quickStepCount) {
                ForEach(quickChoices, id: \.self) { steps in
                    Text("\(steps)").tag(steps)
                }
            }
            .pickerStyle(.segmented)
            Button {
                quickCustomSteps = String(recorder.quickStepCount)
                showQuickCustomPrompt = true
            } label: {
                Label("自訂步數", systemImage: "slider.horizontal.3")
            }
            LabeledContent("狀態") {
                if recorder.isQuickRecordReady {
                    Label("可用", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("尚未驗證", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("地圖上的一鍵補錄")
        } footer: {
            Text(recorder.isQuickRecordReady
                 ? "地圖右側的步行圖示按鈕會直接補錄 \(recorder.quickStepCount) 步，不用再進來這一頁。"
                 : "捷徑成功寫入一次之後，地圖右側的步行圖示按鈕就會變成一鍵補錄；在那之前按它會回到這一頁。")
        }
    }

    /// 預設值加上目前的自訂值，避免自訂之後 Picker 找不到對應選項。
    private var quickChoices: [Int] {
        var choices = StepRecordHistory.presetStepCounts
        if !choices.contains(recorder.quickStepCount) {
            choices.append(recorder.quickStepCount)
            choices.sort()
        }
        return choices
    }

    // MARK: - 七天紀錄

    private var historySection: some View {
        Section("最近七天") {
            LabeledContent("今天", value: "\(recorder.todaySteps) 步")
            LabeledContent("七天合計", value: "\(recorder.sevenDaySteps) 步")
            if recorder.days.isEmpty {
                Text("還沒有補錄紀錄。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recorder.days) { day in
                    DisclosureGroup {
                        ForEach(day.entries) { entry in
                            HStack {
                                Text("\(entry.steps) 步")
                                    .font(.subheadline)
                                Spacer()
                                Text(entry.requestedAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                statusBadge(entry.status)
                            }
                        }
                    } label: {
                        HStack {
                            Text(Self.dayLabel(day.date))
                            Spacer()
                            Text("\(day.confirmedSteps) 步")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if day.hasUnconfirmed {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清除補錄紀錄", systemImage: "trash")
                }
            }
            Text("這裡列出的是 GFlyer 送出的補錄，不是從健康 App 讀回來的實際步數；合計只計入捷徑回報成功的項目。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: StepRecordEntry.Status) -> some View {
        switch status {
        case .confirmed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityLabel(status.label)
        case .pending:
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel(status.label)
        case .failed:
            Image(systemName: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel(status.label)
        }
    }

    // MARK: - 捷徑設定

    private var shortcutSection: some View {
        Section("捷徑設定") {
            TextField("捷徑名稱", text: $recorder.shortcutName)
                .autocorrectionDisabled()
            LabeledContent(
                "捷徑 App",
                value: recorder.isShortcutsInstalled ? "已安裝" : "找不到"
            )
            Text("名稱必須和你在「捷徑」App 裡建立的捷徑完全一致（包含空格）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var helpSection: some View {
        Section("如何建立捷徑") {
            Text("1. 開啟「捷徑」App，建立新捷徑。")
            Text("2. 加入「記錄健康樣本」動作，類型選「步數」。")
            Text("3. 把數值欄位設成「捷徑輸入」，讓 GFlyer 帶入步數。")
            Text("4. 把捷徑命名為上方填寫的名稱。")
            Text("GFlyer 本身不會讀寫健康資料，寫入完全由你的捷徑以它自己的權限完成，所以免費 Apple ID 也能使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
