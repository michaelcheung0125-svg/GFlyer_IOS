import SwiftUI

/// 「開飛行模式 → 開始模擬 → 關飛行模式」的引導畫面。
///
/// 三個步驟永遠都列出來，只有目前該做的那一步會highlight。這樣即使網絡偵測
/// 判斷錯了（例如 VPN 讓路徑看起來仍然連線），使用者還是可以直接按任何一步，
/// 不會被卡住。
struct AirplaneAssistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var assist: AirplaneAssistController
    @ObservedObject var simulation: SimulationController

    private var currentStep: AirplaneAssistController.Step {
        assist.step(isSimulating: simulation.status.isActive)
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                stepsSection
                automationSection
                helpSection
            }
            .navigationTitle("飛航模式輔助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: simulation.status.isActive) { _, isActive in
                guard isActive else { return }
                if assist.simulationDidActivate() {
                    assist.lastMessage = "模擬已開始，正在用捷徑關閉飛行模式。"
                }
            }
            .alert(
                "飛航模式輔助",
                isPresented: Binding(
                    get: { assist.lastMessage != nil },
                    set: { if !$0 { assist.lastMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) { assist.lastMessage = nil }
            } message: {
                Text(assist.lastMessage ?? "")
            }
            .alert(
                "操作失敗",
                isPresented: Binding(
                    get: { assist.lastError != nil },
                    set: { if !$0 { assist.lastError = nil } }
                )
            ) {
                Button("確定", role: .cancel) { assist.lastError = nil }
            } message: {
                Text(assist.lastError ?? "")
            }
        }
    }

    // MARK: - 目前狀態

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: assist.connection.iconName)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(assist.connection == .offline ? Color.orange : Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(assist.connection.label)
                        .font(.subheadline.weight(.semibold))
                    Text(simulation.status.isActive ? "模擬進行中" : "尚未開始模擬")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
            if assist.connection == .wifi {
                Text("目前是 Wi-Fi，一般不需要這串操作，直接開始模擬即可。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("目前狀態")
        } footer: {
            Text("網絡狀態是自動偵測的，你從控制中心手動切換飛行模式，下面的步驟也會跟著更新。")
        }
    }

    // MARK: - 步驟

    private var stepsSection: some View {
        Section {
            stepRow(
                step: .turnOnAirplane,
                number: 1,
                title: "開啟飛行模式",
                detail: "行動網絡下先斷網，模擬比較容易建立成功。"
            ) {
                Button("用捷徑開啟") { assist.setAirplaneMode(true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!assist.isAutomationReady)
            }
            stepRow(
                step: .startSimulation,
                number: 2,
                title: "開始模擬",
                detail: "維持飛行模式，直接在這裡開始。"
            ) {
                Button("開始模擬") {
                    assist.armAutoDisable()
                    simulation.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(simulation.status.isActive)
            }
            stepRow(
                step: .turnOffAirplane,
                number: 3,
                title: "關閉飛行模式",
                detail: "模擬已經建立，現在可以把網絡開回來。"
            ) {
                Button("用捷徑關閉") {
                    assist.cancelAutoDisable()
                    assist.setAirplaneMode(false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!assist.isAutomationReady)
            }
        } header: {
            Text("操作步驟")
        } footer: {
            Text(assist.isAutomationReady
                 ? "沒反應時可以照樣從控制中心手動切換，步驟一樣會自動推進。"
                 : "還沒設定飛航切換捷徑，第 1、3 步請從控制中心手動切換飛行模式。設定捷徑後就能在這裡一鍵切換。")
        }
    }

    private func stepRow<Action: View>(
        step: AirplaneAssistController.Step,
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let isCurrent = currentStep == step
        let isDone = isStepDone(step)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Color.green : (isCurrent ? Color.blue : Color.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent || isDone ? Color.primary : Color.secondary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if isCurrent {
                action()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 3)
    }

    /// 走到後面的步驟，代表前面的已經完成。
    private func isStepDone(_ step: AirplaneAssistController.Step) -> Bool {
        switch (step, currentStep) {
        case (.turnOnAirplane, .startSimulation),
             (.turnOnAirplane, .turnOffAirplane),
             (.turnOnAirplane, .finished),
             (.startSimulation, .turnOffAirplane),
             (.startSimulation, .finished),
             (.turnOffAirplane, .finished):
            return true
        default:
            return false
        }
    }

    // MARK: - 自動切換

    private var automationSection: some View {
        Section {
            Toggle("用捷徑切換飛行模式", isOn: $assist.isAutomationEnabled)
            if assist.isAutomationEnabled {
                HStack {
                    Text("捷徑名稱")
                    Spacer()
                    TextField("捷徑名稱", text: $assist.shortcutName)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(maxWidth: 190)
                }
                Toggle("模擬開始後自動關閉", isOn: $assist.autoDisableAfterStart)
                if !assist.isShortcutsInstalled {
                    Label("找不到「捷徑」App", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("自動切換")
        } footer: {
            Text("只有「關閉」會自動執行。自動開啟飛行模式若中途失敗會把你留在斷網狀態，所以第 1 步一律保持手動確認。")
        }
    }

    // MARK: - 說明

    private var helpSection: some View {
        Section("怎樣建立飛航切換捷徑") {
            VStack(alignment: .leading, spacing: 7) {
                helpLine("1.", "開啟「捷徑」App，新增一個捷徑。")
                helpLine("2.", "加入動作「如果」，條件設成：捷徑輸入　是　on。")
                helpLine("3.", "在「如果」裡面加入動作「設定飛航模式」，選開啟。")
                helpLine("4.", "在「否則」裡面再加一個「設定飛航模式」，選關閉。")
                helpLine("5.", "把捷徑命名為「\(AirplaneAssistController.defaultShortcutName)」，或改上面的名稱欄位對應。")
                helpLine("6.", "在捷徑詳細資料關閉「執行前先詢問」，否則每次都要多按一次確認。")
            }
            .padding(.vertical, 2)
            Text("GFlyer 會把 on 或 off 當作文字輸入傳給捷徑。iOS 沒有讓 App 直接切換飛行模式的 API，這是唯一可行的做法。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func helpLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
