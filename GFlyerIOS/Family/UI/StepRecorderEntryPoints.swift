import SwiftUI

/// 主畫面上的補錄：從地圖工具列打開的補錄畫面，以及一鍵補錄的結果。
struct StepRecorderMainScreen: ViewModifier {
    @ObservedObject var edition: EditionModel
    @ObservedObject var recorder: StepRecorderController
    let feedback: MainScreenFeedback

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $edition.showsStepRecorderOnMap) { StepRecorderView(recorder: recorder) }
            // 工具列的一鍵補錄不會開啟補錄畫面，結果要在主畫面回報。開著補錄
            // 畫面時交給它自己的 alert，這裡不重複顯示。
            .onChange(of: recorder.lastMessage) { _, message in
                guard let message, !edition.showsStepRecorderOnMap else { return }
                feedback.announce(message)
                recorder.lastMessage = nil
            }
            .onChange(of: recorder.lastError) { _, error in
                guard let error, !edition.showsStepRecorderOnMap else { return }
                feedback.reportError(error)
                recorder.lastError = nil
            }
    }
}

/// 從設定頁「補錄步數」打開的補錄畫面。
struct StepRecorderSettingsSheet: ViewModifier {
    @ObservedObject var edition: EditionModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: $edition.showsStepRecorderInSettings) {
            StepRecorderView(recorder: edition.stepRecorder)
        }
    }
}

/// 設定頁的「補錄步數」。
struct StepRecorderSection: View {
    @ObservedObject var recorder: StepRecorderController
    let open: () -> Void

    var body: some View {
        Section("補錄步數") {
            Button(action: open) {
                LabeledContent {
                    Text("今天 \(recorder.todaySteps) 步")
                        .font(.numericCaption)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("補錄步數", systemImage: "figure.walk")
                }
            }
            Text("透過你自建的「捷徑」把步數寫入健康 App，GFlyer 本身不需要健康權限。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension MapToolItem {
    /// 一鍵補錄。捷徑還沒成功跑過一次時不直接送出，改為帶使用者去設定頁——
    /// 在那之前送出只會開啟一個找不到的捷徑，使用者也不知道要去哪裡修。
    @MainActor
    static func stepRecord(
        recorder: StepRecorderController,
        feedback: MainScreenFeedback,
        openRecorder: @escaping () -> Void
    ) -> MapToolItem {
        let isReady = recorder.isQuickRecordReady
        return MapToolItem(
            id: "step-record",
            icon: "figure.walk",
            label: isReady ? "補錄 \(recorder.quickStepCount) 步" : "設定補錄步數",
            tint: isReady ? nil : Color.secondary
        ) {
            guard isReady else {
                openRecorder()
                return
            }
            let steps = recorder.quickStepCount
            recorder.record(steps: steps)
            feedback.announce("正在用捷徑補錄 \(steps) 步")
        }
    }
}
