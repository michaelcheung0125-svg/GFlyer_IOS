import SwiftUI

/// 定位檢查頁（GFlyer-Suite `docs/features/location-check.md`）：iOS 現在交給其他 App 的位置，和本 App 推送的
/// 位置比對，給一句結論。從設定頁「目前位置與背景路線」推進來，兩個版本都有。
struct LocationCheckView: View {
    @ObservedObject var controller: SimulationController
    @StateObject private var reader = LocationCheckReader()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // 「多久之前」每秒更新
        TimelineView(.periodic(from: .now, by: 1)) { context in
            form(now: context.date)
        }
        .navigationTitle(LocationCheckText.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if scenePhase == .active { reader.start() } }
        .onDisappear { reader.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reader.start() } else { reader.stop() }
        }
        // 主畫面的跨日時區提醒被設定頁蓋住，從這一頁傳送時在這裏問
        .alert(
            CrossDateWarningText.title,
            isPresented: crossDateAlertBinding,
            presenting: controller.pendingCrossDateWarning
        ) { _ in
            Button(CrossDateWarningText.confirmButton) { controller.confirmCrossDateStart() }
            Button(CrossDateWarningText.cancelButton, role: .cancel) { controller.cancelCrossDateStart() }
        } message: { warning in
            Text(CrossDateWarningText.message(for: warning))
        }
    }

    private func form(now: Date) -> some View {
        let pushed = controller.status.isActive ? controller.status.coordinate : nil
        let fix = reader.fix
        let verdict = LocationCheck.verdict(
            hasPermission: reader.hasPermission,
            pushed: pushed,
            movingMetresPerSecond: controller.movingMetresPerSecond,
            received: fix?.received
        )
        return Form {
            Section {
                Text(LocationCheckText.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section(LocationCheckText.settingsSection) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(LocationCheckText.pushingLabel)
                    Text(pushed?.display ?? LocationCheckText.notPushing)
                        .font(.numericCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(LocationCheckText.receivedSection) {
                row(LocationCheckText.coordinateLabel, fix?.received.coordinate.display)
                row(LocationCheckText.accuracyLabel, fix.map { LocationCheck.accuracyText(metres: $0.accuracyMetres) })
                row(LocationCheckText.timeLabel, fix.map { LocationCheck.timeText(timestamp: $0.timestamp, now: now) })
                row(
                    LocationCheckText.sourceLabel,
                    fix.map { $0.received.isSimulated ? LocationCheckText.sourceSimulated : LocationCheckText.sourceReal }
                )
                row(LocationCheckText.distanceLabel, distanceText(fix: fix, pushed: pushed))
            }
            Section {
                verdictCard(verdict)
                    .listRowBackground(verdictTint(verdict).opacity(0.15))
            }
            Section {
                Button {
                    controller.teleportToSelected()
                } label: {
                    Label(LocationCheckText.teleportButton, systemImage: "location.fill")
                }
                Text(LocationCheckText.selected(controller.selectedCoordinate))
                    .font(.numericCaption)
                    .foregroundStyle(.secondary)
                Button {
                    controller.stop()
                } label: {
                    Label(LocationCheckText.stopButton, systemImage: "stop.fill")
                }
                .disabled(!controller.status.isActive)
                // 主畫面的狀態列被設定頁蓋住；錯誤照舊跳「操作失敗」
                Text(controller.status.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? LocationCheckText.noValue)
                .font(.numericLabel)
                .multilineTextAlignment(.trailing)
        }
    }

    private func distanceText(fix: LocationCheckReader.Fix?, pushed: GeoCoordinate?) -> String? {
        guard let fix, let pushed else { return nil }
        return LocationCheck.distanceText(metres: GeoMath.distanceMetres(from: fix.received.coordinate, to: pushed))
    }

    private func verdictCard(_ verdict: LocationCheckVerdict) -> some View {
        let hint = verdict == .waiting && reader.updatesFailed ? LocationCheckText.updatesFailedHint : verdict.hint
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text(verdict.text).font(.labelEmphasis)
            } icon: {
                Image(systemName: verdictSymbol(verdict)).foregroundStyle(verdictTint(verdict))
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if verdict == .needsPermission {
                Button {
                    reader.requestPermission()
                } label: {
                    Label(LocationCheckText.grantPermissionButton, systemImage: "gearshape")
                }
                // 只有按鈕本身按得到，不是整張卡片
                .buttonStyle(.borderless)
            }
        }
    }

    /// 規格 3.4 的卡片顏色：符合是綠色、只是說明是灰色、要注意是提醒色、有問題是錯誤色。
    private func verdictTint(_ verdict: LocationCheckVerdict) -> Color {
        switch verdict {
        case .matches: return .statusOK
        case .waiting, .realLocation: return .secondary
        case .needsPermission, .mockFromElsewhere: return .statusAttention
        case .mismatch: return .statusDanger
        }
    }

    private func verdictSymbol(_ verdict: LocationCheckVerdict) -> String {
        switch verdict {
        case .matches: return "checkmark.circle.fill"
        case .waiting: return "clock"
        case .realLocation: return "info.circle"
        case .needsPermission, .mockFromElsewhere, .mismatch: return "exclamationmark.triangle.fill"
        }
    }

    private var crossDateAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.pendingCrossDateWarning != nil },
            set: { if !$0 { controller.cancelCrossDateStart() } }
        )
    }
}
