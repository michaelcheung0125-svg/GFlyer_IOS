import SwiftUI

/// 「在這支 iPhone 上配對」的幾列（docs/APP_STORE_PLAN.md 第 4、6 項）：沒有在配對時是開始的按鈕和上一次的結果，
/// 配對進行中是進度、PIN 和剩下時間，最後一列是說明。設定頁「首次設定」和公開版的首次設定引導都用。
///
/// 步驟照 2026-10-20 iOS 27 實機（香港繁體中文）的畫面一字不差地寫：「Pair with GFlyer」在實機上就是英文。
/// 配對進行中也顯示，切回來時還看得到下一步。
struct OnDevicePairingRows: View {
    @ObservedObject var controller: SimulationController
    @ObservedObject var pairing: OnDevicePairingController
    /// 開始的按鈕。公開版的引導第一步用同一個動作叫出「開發者模式」，按鈕名稱不同。
    var startTitle = OnDevicePairingController.continuedTaskTitle
    var startIcon = "iphone.radiowaves.left.and.right"
    /// 最後一列的說明；nil 用設定頁的配對步驟。
    var note: String?

    /// 設定頁的配對步驟。
    static let steps =
        "iOS 27 起不用電腦。按「\(OnDevicePairingController.continuedTaskTitle)」之後：\n1. 打開 iPhone 的「設定」>「私隱與保安」>「開發者模式」。\n2. 在「其他裝置」按「Pair with GFlyer」，再按「配對」。\n3. 在「輸入密碼」輸入 GFlyer 顯示的 6 位數字，通知也會顯示這組數字。\n配對成功後會取代現有的 Pairing File。"

    var body: some View {
        if pairing.phase.isActive {
            activeRows
        } else {
            Button {
                pairing.start()
            } label: {
                Label(startTitle, systemImage: startIcon)
            }
            .disabled(controller.isMotionActive)
            resultText
        }
        Text(controller.isMotionActive && !pairing.phase.isActive
             ? "模擬進行中不能配對，請先按停止。"
             : note ?? Self.steps)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var activeRows: some View {
        HStack(spacing: Spacing.md) {
            ProgressView()
            Text(statusText)
        }
        if case let .enterPIN(pin) = pairing.phase {
            LabeledContent("PIN") {
                Text(pin)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
            }
        }
        if pairing.needsLocalNetworkPermission {
            Text("GFlyer 還沒有本機網路權限，「設定」找不到它。系統詢問時請按「允許」。")
                .font(.caption)
                .foregroundStyle(Color.statusAttention)
        }
        if let message = pairing.lastAttemptMessage {
            Text("上一次沒有成功，可以在「設定」再按一次「Pair with GFlyer」。\n\(message)")
                .font(.caption)
                .foregroundStyle(Color.statusAttention)
        }
        LabeledContent("剩下時間") {
            Text(String(format: "%d:%02d", pairing.secondsRemaining / 60, pairing.secondsRemaining % 60))
                .font(.numericLabel)
        }
        Button("取消配對", role: .destructive) {
            pairing.cancel()
        }
    }

    private var statusText: String {
        switch pairing.phase {
        case .starting: return "正在準備"
        case .waitingForDevice: return "等待「設定」連線"
        case .deviceConnected: return "「設定」已連線"
        case .enterPIN: return "在「設定」的「輸入密碼」輸入這組數字"
        case .idle, .succeeded, .failed: return ""
        }
    }

    @ViewBuilder
    private var resultText: some View {
        switch pairing.phase {
        case .succeeded:
            Label("配對完成，Pairing File 已更新。", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(Color.statusOK)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.statusDanger)
        case .idle, .starting, .waitingForDevice, .deviceConnected, .enterPIN:
            EmptyView()
        }
    }
}
