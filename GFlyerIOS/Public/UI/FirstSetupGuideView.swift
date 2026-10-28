import SwiftUI

/// 公開版的首次設定引導（docs/APP_STORE_PLAN.md 第 14 項）：一步一個畫面，每一步用的是設定頁的同一組按鈕和狀態，
/// 所以引導和設定頁看到的字相同。疊在主畫面或設定頁上，兩邊都是 sheet：iOS 26 以下要在這裏匯入 Pairing File，
/// 推進設定頁的話，選檔畫面會和設定頁自己的 `.fileImporter` 互相干擾（`SetupView.ImportTarget`）。
struct FirstSetupGuideView: View {
    @ObservedObject var controller: SimulationController
    @ObservedObject var guide: FirstSetupGuide
    @ObservedObject private var pairingStore: PairingFileStore
    @ObservedObject private var tunnel: LocalTunnel
    @ObservedObject private var pairing: OnDevicePairingController
    @ObservedObject private var download: DeveloperDiskImageDownload
    @State private var showImporter = false
    @State private var importError: String?
    @State private var isClearing = false
    @State private var clearMessage: String?

    init(controller: SimulationController, guide: FirstSetupGuide) {
        self.controller = controller
        self.guide = guide
        _pairingStore = ObservedObject(wrappedValue: controller.pairingStore)
        _tunnel = ObservedObject(wrappedValue: controller.vpn)
        _pairing = ObservedObject(wrappedValue: controller.onDevicePairing)
        // 和設定頁「Developer Disk Image」的同一個，離開這裏下載也繼續
        _download = ObservedObject(wrappedValue: DeveloperDiskImageDownload.shared)
    }

    private var step: FirstSetupStep { guide.step }
    private var pairsOnDevice: Bool { pairing.isAvailable }

    private var readiness: FirstSetupReadiness {
        FirstSetupReadiness(
            hasPairingFile: pairingStore.isImported,
            isTunnelUp: tunnel.isTunnelUp,
            hasDeveloperDiskImage: download.state == .downloaded
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                instructionSection
                actionSection
                navigationSection
            }
            .navigationTitle(FirstSetupText.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FirstSetupText.closeButton) { guide.close() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: PairingFileStore.supportedTypes) { result in
                importPairingFile(result)
            }
        }
        .modifier(FirstSetupAlerts(controller: controller, importError: $importError, clearMessage: $clearMessage))
        // VPN 狀態沒有系統通知可以訂閱，打開時重新查一次（和設定頁相同）
        .onAppear { tunnel.refreshStatus() }
    }

    // MARK: - 區段

    private var instructionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(FirstSetupText.progress(step))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(FirstSetupText.title(step, pairsOnDevice: pairsOnDevice))
                    .font(.headline)
                ForEach(FirstSetupText.instructions(step, pairsOnDevice: pairsOnDevice), id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        switch step {
        case .showDeveloperMode:
            if pairsOnDevice {
                Section {
                    OnDevicePairingRows(
                        controller: controller,
                        pairing: pairing,
                        startTitle: FirstSetupText.showDeveloperModeButton,
                        startIcon: "eye",
                        note: FirstSetupText.showDeveloperModeNote
                    )
                }
            }
        case .enableDeveloperMode:
            EmptyView()
        case .pair:
            pairSection
        case .tunnel:
            Section(LocalTunnel.settingsTitle) {
                tunnel.settingsRows(controller: controller)
            }
        case .developerDiskImage:
            Section("Developer Disk Image") {
                Edition.developerDiskImageRows(controller: controller)
            }
        case .teleport:
            Section {
                locationCheckLink
                Text(LocationCheckText.selected(controller.selectedCoordinate))
                    .font(.numericCaption)
                    .foregroundStyle(.secondary)
            }
        case .restore:
            Section {
                clearButton
                locationCheckLink
            }
        }
    }

    private var pairSection: some View {
        Section {
            LabeledContent("Pairing File", value: pairingStore.isImported ? "已匯入" : "未匯入")
            if pairsOnDevice {
                OnDevicePairingRows(controller: controller, pairing: pairing)
            }
            Button {
                showImporter = true
            } label: {
                Label("匯入 Pairing File", systemImage: "doc.badge.plus")
            }
        }
    }

    // 和設定頁「目前位置與背景路線」的入口相同
    private var locationCheckLink: some View {
        NavigationLink {
            LocationCheckView(controller: controller)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(LocationCheckText.title)
                Text(LocationCheckText.entrySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 和設定頁「恢復」的按鈕相同
    private var clearButton: some View {
        Button(role: .destructive) {
            guard !isClearing else { return }
            isClearing = true
            Task {
                let message = await controller.forceClearSimulation()
                isClearing = false
                // 清除指令本身失敗時由「操作失敗」提示顯示
                if controller.lastError == nil { clearMessage = message }
            }
        } label: {
            if isClearing {
                HStack {
                    ProgressView()
                    Text("正在清除並驗證定位")
                }
            } else {
                Text("完整清除模擬定位")
            }
        }
        .disabled(isClearing)
    }

    private var navigationSection: some View {
        Section {
            HStack {
                if step.previous != nil {
                    Button(FirstSetupText.backButton) { guide.goBack() }
                }
                Spacer()
                if step.next == nil {
                    Button(FirstSetupText.finishButton) { guide.finish() }
                        .fontWeight(.semibold)
                } else {
                    Button(FirstSetupText.nextButton) { guide.goForward() }
                        .fontWeight(.semibold)
                        .disabled(!readiness.canGoForward(from: step))
                }
            }
            // 一列裡有兩個按鈕，不加的話在 Form 裡點哪裡都會觸發整列
            .buttonStyle(.borderless)
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !readiness.canGoForward(from: step), let note = FirstSetupText.waitingNote(step) {
                    Text(note)
                }
                Text(FirstSetupText.reopenNote)
            }
        }
    }

    // MARK: - 動作

    private func importPairingFile(_ result: Result<URL, Error>) {
        do {
            try pairingStore.importFile(from: result.get())
        } catch {
            // 按「取消」也會回 failure，那不是匯入失敗（和設定頁相同）
            let nsError = error as NSError
            guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else { return }
            importError = error.localizedDescription
        }
    }
}

/// 引導上的提示。主畫面和設定頁的「操作失敗」被這個 sheet 蓋住，所以這裏也要有一個。
private struct FirstSetupAlerts: ViewModifier {
    @ObservedObject var controller: SimulationController
    @Binding var importError: String?
    @Binding var clearMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("操作失敗", isPresented: binding(for: $controller.lastError)) {
                Button("確定", role: .cancel) { controller.lastError = nil }
            } message: {
                Text(controller.lastError ?? "未知錯誤")
            }
            .alert("沒有成功", isPresented: binding(for: $importError)) {
                Button("確定", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "未知錯誤")
            }
            .alert("清除結果", isPresented: binding(for: $clearMessage)) {
                Button("確定", role: .cancel) { clearMessage = nil }
            } message: {
                Text(clearMessage ?? "")
            }
    }

    /// 有值就顯示（和設定頁的 `binding(for:)` 相同）。
    private func binding(for value: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }
}

/// 主畫面上的引導：第一次打開 App 時自己打開（`FirstSetupGuide.presentOnLaunchIfNeeded`）。
struct FirstSetupMainScreen: ViewModifier {
    @ObservedObject var guide: FirstSetupGuide
    let simulation: SimulationController

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $guide.isPresentedOnMainScreen, onDismiss: { guide.close() }) {
                FirstSetupGuideView(controller: simulation, guide: guide)
            }
            .task {
                // 截圖不要被它蓋住；啟動時已經有「恢復上次模擬？」或錯誤的提示時，sheet 打不開
                guard !MainView.isCapturingScreenshots,
                      simulation.pendingResumeSession == nil,
                      simulation.lastError == nil
                else { return }
                guide.presentOnLaunchIfNeeded(canControlDevice: simulation.canControlDeviceLocation)
            }
    }
}

/// 從設定頁打開的引導，疊在設定頁上面。
struct FirstSetupSettingsSheet: ViewModifier {
    @ObservedObject var guide: FirstSetupGuide
    let simulation: SimulationController

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $guide.isPresentedInSettings, onDismiss: { guide.close() }) {
                FirstSetupGuideView(controller: simulation, guide: guide)
            }
    }
}

/// 設定頁「首次設定」最上面打開引導的按鈕。
struct FirstSetupEntryRow: View {
    @ObservedObject var guide: FirstSetupGuide

    var body: some View {
        Button {
            guide.presentFromSettings()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(FirstSetupText.entryTitle)
                    Text(FirstSetupText.entrySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "list.number")
            }
        }
    }
}
