import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static var gpx: UTType { UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml }
}

struct ExportedDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .xml, .gpx, .propertyList] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// 每個 Section 與每組 modifier 都拆成獨立的計算屬性。整份 Form 寫在一起時
/// Swift 型別檢查器會在 body 上放棄（unable to type-check in reasonable
/// time），新增 Section 時請沿用這個分層。
struct SetupView: View {
    /// SwiftUI 同一個 view 上只會有一個 .fileImporter 真的生效，串接多個時其餘
    /// 會靜默失效——按下去沒有任何反應，也不會報錯。所以三種匯入共用一個
    /// modifier，由 pendingImport 決定接受哪些型別、結果交給誰處理。
    /// 詳見 https://developer.apple.com/forums/thread/781186
    private enum ImportTarget {
        case pairingFile
        case gpxRoutes
        case backup

        var contentTypes: [UTType] {
            switch self {
            case .pairingFile: return PairingFileStore.supportedTypes
            case .gpxRoutes: return [.gpx, .xml]
            case .backup: return [.json]
            }
        }

        var allowsMultipleSelection: Bool { self == .gpxRoutes }
    }

    /// .fileExporter 有同樣的限制，同樣併成一個。
    private enum ExportTarget {
        case pairingFile
        case gpxRoutes
        case backup

        var contentType: UTType {
            switch self {
            case .pairingFile: return .propertyList
            case .gpxRoutes: return .gpx
            case .backup: return .json
            }
        }

        var defaultFilename: String {
            switch self {
            case .pairingFile: return PairingFileStore.exportFilename
            case .gpxRoutes: return "gflyer-routes.gpx"
            case .backup: return "gflyer-backup.json"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var controller: SimulationController
    @ObservedObject var edition: EditionModel
    @ObservedObject private var pairingStore: PairingFileStore
    @ObservedObject private var deviceLocation: DeviceLocationService
    @ObservedObject private var vpn: LocalTunnel
    @ObservedObject private var onDevicePairing: OnDevicePairingController
    /// 和 GFlyerIOSApp 讀同一個鍵；那邊負責套用，這裡只負責改。
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var showImporter = false
    @State private var pendingImport: ImportTarget?
    @State private var showExporter = false
    @State private var pendingExport: ExportTarget?
    @State private var exportDocument = ExportedDataDocument()
    @State private var importError: String?
    @State private var showPresetPrompt = false
    @State private var presetName = ""
    @State private var presetSpeed = "50"
    @State private var pendingBackupData: Data?
    @State private var transferSummary: String?
    @State private var forceClearMessage: String?
    @State private var isForceClearing = false
    @State private var contactMessage: String?
    @State private var confirmingPairingRemoval = false
    private let appVersion = AppVersionInfo()

    init(controller: SimulationController, edition: EditionModel) {
        self.controller = controller
        self.edition = edition
        _pairingStore = ObservedObject(wrappedValue: controller.pairingStore)
        _deviceLocation = ObservedObject(wrappedValue: controller.deviceLocation)
        _vpn = ObservedObject(wrappedValue: controller.vpn)
        _onDevicePairing = ObservedObject(wrappedValue: controller.onDevicePairing)
    }

    var body: some View {
        NavigationStack {
            formWithTransfers
                // 匯入、匯出和移除共用這個提示，所以標題不寫「匯入」。
                .alert("沒有成功", isPresented: binding(for: $importError)) {
                    Button("確定", role: .cancel) { importError = nil }
                } message: {
                    Text(importError ?? "未知錯誤")
                }
                .alert(
                    "操作失敗",
                    isPresented: Binding(
                        get: { controller.lastError != nil },
                        set: { if !$0 { controller.lastError = nil } }
                    )
                ) {
                    Button("確定", role: .cancel) { controller.lastError = nil }
                } message: {
                    Text(controller.lastError ?? "未知錯誤")
                }
                .modifier(edition.settingsPresentations)
                .alert("完成", isPresented: binding(for: $transferSummary)) {
                    Button("確定", role: .cancel) { transferSummary = nil }
                } message: {
                    Text(transferSummary ?? "")
                }
                .alert("清除結果", isPresented: binding(for: $forceClearMessage)) {
                    Button("確定", role: .cancel) { forceClearMessage = nil }
                } message: {
                    Text(forceClearMessage ?? "")
                }
                .alert("聯絡我們", isPresented: binding(for: $contactMessage)) {
                    Button("確定", role: .cancel) { contactMessage = nil }
                } message: {
                    Text(contactMessage ?? "")
                }
        }
    }

    // MARK: - 檔案匯入與匯出

    private var formWithTransfers: some View {
        formContent
            .navigationTitle("裝置設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: pendingImport?.contentTypes ?? [],
                allowsMultipleSelection: pendingImport?.allowsMultipleSelection ?? false
            ) { result in
                // 先取出再清掉，否則下一次呼叫會沿用上一次的目標。
                let target = pendingImport
                pendingImport = nil
                switch target {
                case .pairingFile: importPairingFile(result)
                case .gpxRoutes: importGpx(result)
                case .backup: loadBackup(result)
                case nil: break
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: pendingExport?.contentType ?? .data,
                defaultFilename: pendingExport?.defaultFilename
            ) { result in
                pendingExport = nil
                if case let .failure(error) = result { importError = describe(error) }
            }
            .alert(
                "還原備份",
                isPresented: binding(for: $pendingBackupData),
                presenting: pendingBackupData
            ) { data in
                Button("還原", role: .destructive) { restoreBackup(data) }
                Button("取消", role: .cancel) { pendingBackupData = nil }
            } message: { _ in
                Text(Edition.restoreConfirmationMessage)
            }
            .alert("移除 Pairing File？", isPresented: $confirmingPairingRemoval) {
                Button("移除", role: .destructive) { removePairingFile() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(onDevicePairing.isAvailable
                     ? "移除之後，要再按「匯入 Pairing File」或「\(OnDevicePairingController.continuedTaskTitle)」才能傳送位置。想留一份的話，先按「匯出 Pairing File」。"
                     : "移除之後，要再按「匯入 Pairing File」才能傳送位置。想留一份的話，先按「匯出 Pairing File」。")
            }
    }

    private var formContent: some View {
        Form {
            backendSection
            appearanceSection
            pairingSection
            tunnelSection
            locationSection
            developerDiskImageSection
            speedPresetSection
            playbackSection
            orbitRadiusSection
            edition.settingsSections
            transferSection
            instructionsSection
            if controller.canControlDeviceLocation { recoverySection }
        }
        // VPN 狀態沒有系統通知可以訂閱，打開設定頁時重新查一次
        .onAppear { vpn.refreshStatus() }
    }

    // MARK: - 區段

    // 版本放在設定頁第一列：使用者要確認裝到哪一版時，第一眼就看得到。
    private var backendSection: some View {
        Section("關於") {
            LabeledContent("App 版本", value: appVersion.displayVersion)
            LabeledContent("Bundle ID", value: appVersion.bundleIdentifier)
                .font(.caption.monospaced())
            LabeledContent("定位後端", value: controller.backendName)
            LabeledContent(
                "原生程式庫",
                value: controller.canControlDeviceLocation ? "已載入" : "尚未啟用"
            )
            if let guideURL = Edition.userGuideURL {
                Button {
                    openURL(guideURL)
                } label: {
                    Label("使用教學", systemImage: "book")
                }
            }
            Button {
                openContactEmail()
            } label: {
                Label("聯絡我們", systemImage: "envelope")
            }
        }
    }

    private var appearanceSection: some View {
        // 帶字串標題的 Section 沒有 footer 參數，要 footer 就得用
        // header:／footer: 這一組，兩邊都寫成 Text。
        Section {
            Picker("深淺色", selection: $appearanceRawValue) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("外觀")
        } footer: {
            Text("只影響 GFlyer，不會改到其他 App。選「跟隨系統」就是原本的行為。")
        }
    }

    private var pairingSection: some View {
        Section("首次設定") {
            LabeledContent("Pairing File", value: pairingStore.isImported ? "已匯入" : "未匯入")
            if onDevicePairing.isAvailable { onDevicePairingRows }
            Button {
                pendingImport = .pairingFile
                showImporter = true
            } label: {
                Label("匯入 Pairing File", systemImage: "doc.badge.plus")
            }
            if pairingStore.isImported {
                // docs/APP_STORE_PLAN.md 第 5 項。
                Button {
                    do {
                        exportDocument = ExportedDataDocument(data: try pairingStore.exportData())
                        pendingExport = .pairingFile
                        showExporter = true
                    } catch {
                        importError = describe(error)
                    }
                } label: {
                    Label("匯出 Pairing File", systemImage: "square.and.arrow.up")
                }
                Text("存一份到「檔案」：重裝 GFlyer 之後，用「匯入 Pairing File」選這個檔就不用重新配對。檔案裏有配對這支 iPhone 的鑰匙，不要傳給別人。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // 一按就刪太容易誤觸（使用者 2026-10-21 回報），先問一次。
                Button("移除 Pairing File", role: .destructive) {
                    confirmingPairingRemoval = true
                }
            }
        }
    }

    /// iOS 27 起才有（docs/APP_STORE_PLAN.md 第 4、6 項）。步驟照 2026-10-20 iOS 27 實機（香港繁體中文）
    /// 的畫面一字不差地寫：「Pair with GFlyer」在實機上就是英文。配對進行中也顯示，切回來時還看得到下一步。
    @ViewBuilder
    private var onDevicePairingRows: some View {
        if onDevicePairing.phase.isActive {
            activePairingRows
        } else {
            Button {
                onDevicePairing.start()
            } label: {
                Label(OnDevicePairingController.continuedTaskTitle, systemImage: "iphone.radiowaves.left.and.right")
            }
            .disabled(controller.isMotionActive)
            pairingResultText
        }
        Text(controller.isMotionActive && !onDevicePairing.phase.isActive
             ? "模擬進行中不能配對，請先按停止。"
             : "iOS 27 起不用電腦。按「\(OnDevicePairingController.continuedTaskTitle)」之後：\n1. 打開 iPhone 的「設定」>「私隱與保安」>「開發者模式」。\n2. 在「其他裝置」按「Pair with GFlyer」，再按「配對」。\n3. 在「輸入密碼」輸入 GFlyer 顯示的 6 位數字，通知也會顯示這組數字。\n配對成功後會取代現有的 Pairing File。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var activePairingRows: some View {
        HStack(spacing: Spacing.md) {
            ProgressView()
            Text(pairingStatusText)
        }
        if case let .enterPIN(pin) = onDevicePairing.phase {
            LabeledContent("PIN") {
                Text(pin)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
            }
        }
        if onDevicePairing.needsLocalNetworkPermission {
            Text("GFlyer 還沒有本機網路權限，「設定」找不到它。系統詢問時請按「允許」。")
                .font(.caption)
                .foregroundStyle(Color.statusAttention)
        }
        if let message = onDevicePairing.lastAttemptMessage {
            Text("上一次沒有成功，可以在「設定」再按一次「Pair with GFlyer」。\n\(message)")
                .font(.caption)
                .foregroundStyle(Color.statusAttention)
        }
        LabeledContent("剩下時間") {
            Text(String(format: "%d:%02d", onDevicePairing.secondsRemaining / 60, onDevicePairing.secondsRemaining % 60))
                .font(.numericLabel)
        }
        Button("取消配對", role: .destructive) {
            onDevicePairing.cancel()
        }
    }

    private var pairingStatusText: String {
        switch onDevicePairing.phase {
        case .starting: return "正在準備"
        case .waitingForDevice: return "等待「設定」連線"
        case .deviceConnected: return "「設定」已連線"
        case .enterPIN: return "在「設定」的「輸入密碼」輸入這組數字"
        case .idle, .succeeded, .failed: return ""
        }
    }

    @ViewBuilder
    private var pairingResultText: some View {
        switch onDevicePairing.phase {
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

    private var tunnelSection: some View {
        Section(LocalTunnel.settingsTitle) {
            vpn.settingsRows(controller: controller)
            TextField("目標 IP", text: $controller.deviceIP)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
            LabeledContent("CoreDevice 通道", value: controller.tunnelTestMessage)
            Button {
                controller.testTunnelConnection()
            } label: {
                if controller.isTestingTunnel {
                    HStack {
                        ProgressView()
                        Text("正在測試通道")
                    }
                } else {
                    Label(LocalTunnel.testButtonTitle, systemImage: "network.badge.shield.half.filled")
                }
            }
            .disabled(
                !controller.canControlDeviceLocation
                    || !pairingStore.isImported
                    || controller.isTestingTunnel
                    || controller.isMotionActive
            )
            Text(LocalTunnel.deviceIPHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var locationSection: some View {
        Section("目前位置與背景路線") {
            LabeledContent("定位權限", value: deviceLocation.authorizationLabel)
            LabeledContent(
                "背景活動",
                value: deviceLocation.isBackgroundActivityActive ? "執行中" : "待機"
            )
            Text("目前位置按鈕和背景路線需要「使用 App 期間」定位權限。路線執行時 iOS 會顯示背景定位指示；停止路線後 GFlyer 會立即結束背景活動。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var developerDiskImageSection: some View {
        Section("Developer Disk Image") {
            Text("第一次使用裝置模式時，GFlyer 會下載約 16 MB、固定版本並經 SHA-256 驗證的 Personalized DDI，之後保留在本機使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var speedPresetSection: some View {
        Section("速度預設") {
            ForEach(controller.quickSpeedPresets) { preset in
                HStack {
                    Text(preset.name)
                    Spacer()
                    Text(String(format: "%.1f km/h", preset.kilometresPerHour))
                        .font(.numericCaption)
                        .foregroundStyle(.secondary)
                    if !preset.isBuiltIn {
                        Button(role: .destructive) {
                            controller.removeQuickSpeedPreset(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("刪除速度預設")
                    }
                }
            }
            Button { showPresetPrompt = true } label: {
                Label("新增速度預設", systemImage: "plus")
            }
            .disabled(controller.quickSpeedPresets.count >= QuickSpeedPreset.maxCount)
            .alert("新增速度預設", isPresented: $showPresetPrompt) {
                TextField("名稱", text: $presetName)
                TextField("速度 km/h", text: $presetSpeed)
                    .keyboardType(.decimalPad)
                Button("新增") { addSpeedPreset() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("速度會限制在 1.8 至 900 km/h")
            }
            if controller.quickSpeedPresets.count >= QuickSpeedPreset.maxCount {
                Text("速度快捷預設最多 \(QuickSpeedPreset.maxCount) 個")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playbackSection: some View {
        Section("路線播放") {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Picker("多點路線倒數", selection: playbackBinding(\.startDelaySeconds)) {
                    ForEach(PlaybackSettings.startDelayOptions, id: \.self) { seconds in
                        Text(seconds == 0 ? "不用" : "\(seconds) 秒").tag(seconds)
                    }
                }
                Text(controller.playbackSettings.startDelaySeconds == 0
                     ? "按「開始」後立即啟動多點路線。"
                     : "按「開始」後倒數 \(controller.playbackSettings.startDelaySeconds) 秒才啟動，方便切換到要測試的 App。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("自動停止", selection: playbackBinding(\.autoStopMinutes)) {
                ForEach(PlaybackSettings.autoStopOptions, id: \.self) { minutes in
                    Text(minutes == 0 ? "關閉" : "\(minutes) 分鐘").tag(minutes)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Stepper(
                    "傳送到點停留 \(controller.playbackSettings.dwellSeconds) 秒",
                    value: playbackBinding(\.dwellSeconds),
                    in: PlaybackSettings.dwellRange,
                    step: 1
                )
                Text("定點傳送模式到達路線點後，先停留再執行繞圈／微動。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Toggle(CrossDateWarningText.settingTitle, isOn: playbackBinding(\.crossDateWarningEnabled))
                Text(CrossDateWarningText.settingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("搖桿速度上限", selection: playbackBinding(\.joystickMaxSpeedKilometresPerHour)) {
                ForEach(PlaybackSettings.joystickMaxSpeedOptions, id: \.self) { speed in
                    Text("\(speed) km/h").tag(speed)
                }
            }
            Text("搖桿以推桿幅度控制速度，推到底會持續加速到上限。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 和 Android 的「繞圈設定」相同:每一圈 ±5 公尺、可刪任一圈,新增的一圈 40 公尺;改完一律經過
    /// `PlaybackSettings.normalizedOrbitRadii`(會去重,所以調成和另一圈一樣時那一圈會消失)。
    private var orbitRadiusSection: some View {
        Section("繞圈設定") {
            let radii = controller.playbackSettings.orbitRadiiMetres
            ForEach(Array(radii.enumerated()), id: \.offset) { index, radius in
                orbitRadiusRow(index: index, radius: radius, canDelete: radii.count > 1)
            }
            if radii.count < PlaybackSettings.maxOrbitLaps {
                Button {
                    controller.editOrbitRadii(.add)
                } label: {
                    Label("新增一圈（預設 \(PlaybackSettings.addedLapRadiusMetres) 米）", systemImage: "plus")
                }
            } else {
                Text("最多 \(PlaybackSettings.maxOrbitLaps) 圈。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func orbitRadiusRow(index: Int, radius: Int, canDelete: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Text("第 \(index + 1) 圈半徑")
            Spacer()
            Button {
                controller.editOrbitRadii(.decrease(index: index))
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(radius <= PlaybackSettings.orbitRadiusRange.lowerBound)
            .accessibilityLabel("減少第 \(index + 1) 圈半徑")
            Text("\(radius) 米")
                .font(.numericLabel)
                .frame(minWidth: 56)
            Button {
                controller.editOrbitRadii(.increase(index: index))
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(radius >= PlaybackSettings.orbitRadiusRange.upperBound)
            .accessibilityLabel("增加第 \(index + 1) 圈半徑")
            Button(role: .destructive) {
                controller.editOrbitRadii(.delete(index: index))
            } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(!canDelete)
            .accessibilityLabel("刪除第 \(index + 1) 圈")
        }
        // 一列裡有好幾個按鈕,不加的話在 Form 裡點哪裡都會觸發整列
        .buttonStyle(.borderless)
    }

    private var transferSection: some View {
        Section("資料匯入與匯出") {
            Button {
                pendingImport = .gpxRoutes
                showImporter = true
            } label: {
                Label("匯入 GPX 路線", systemImage: "square.and.arrow.down")
            }
            // 模擬中也可以匯入(和 Android 相同):路線照樣存進去,只是不載入編輯器
            Button {
                if let data = controller.exportAllRoutesAsGpx() {
                    exportDocument = ExportedDataDocument(data: data)
                    pendingExport = .gpxRoutes
                    showExporter = true
                }
            } label: {
                Label("匯出全部路線（GPX）", systemImage: "square.and.arrow.up")
            }
            .disabled(controller.savedRoutes.isEmpty)
            Button {
                if let data = controller.exportBackupData() {
                    exportDocument = ExportedDataDocument(data: data)
                    pendingExport = .backup
                    showExporter = true
                }
            } label: {
                Label("匯出備份檔", systemImage: "externaldrive.badge.timemachine")
            }
            Button {
                pendingImport = .backup
                showImporter = true
            } label: {
                Label("還原備份檔", systemImage: "arrow.counterclockwise")
            }
            .disabled(controller.isMotionActive)
            Text(Edition.backupFormatNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var instructionsSection: some View {
        Section("操作順序") {
            Text("1. 用電腦產生這部 iPhone 的 pairing file。")
            Text("2. 將檔案傳到 iPhone 並在此匯入。")
            ForEach(LocalTunnel.usageSteps, id: \.self) { Text($0) }
        }
    }

    private var recoverySection: some View {
        Section("恢復") {
            Button(role: .destructive) {
                guard !isForceClearing else { return }
                isForceClearing = true
                Task {
                    let message = await controller.forceClearSimulation()
                    isForceClearing = false
                    // 清除指令本身失敗時由「操作失敗」提示顯示；
                    // 其餘一律顯示驗證結果（真實／仍模擬／取不到定位）
                    if controller.lastError == nil { forceClearMessage = message }
                }
            } label: {
                if isForceClearing {
                    HStack {
                        ProgressView()
                        Text("正在清除並驗證定位")
                    }
                } else {
                    Text("完整清除模擬定位")
                }
            }
            .disabled(isForceClearing)
            vpn.recoveryRows(isClearing: isForceClearing)
        }
    }

    // MARK: - 動作與繫結

    private func addSpeedPreset() {
        if let speed = Double(presetSpeed),
           !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            controller.saveQuickSpeedPreset(name: presetName, speed: speed)
        }
        presetName = ""
        presetSpeed = "50"
    }

    /// 使用者按「取消」時 fileImporter 一樣會回 failure，那不是匯入失敗，
    /// 不該跳警告。回 nil 代表沒有東西要顯示。
    private func describe(_ error: Error) -> String? {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return nil
        }
        return error.localizedDescription
    }

    private func importPairingFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try pairingStore.importFile(from: url)
        } catch {
            importError = describe(error)
        }
    }

    private func removePairingFile() {
        do {
            try pairingStore.remove()
        } catch {
            importError = describe(error)
        }
    }

    private func loadBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            pendingBackupData = try readSecurityScopedFile(at: url)
        } catch {
            importError = describe(error)
        }
    }

    /// 讀不到的檔案略過、繼續下一個,整批只顯示一則訊息;選了檔案就一定有訊息,
    /// 每個都讀不到時是「找不到可用路線」。和 Android 相同(GFlyer-Suite docs/features/gpx-import.md)。
    private func importGpx(_ result: Result<[URL], Error>) {
        let urls: [URL]
        do {
            urls = try result.get()
        } catch {
            importError = describe(error)
            return
        }
        guard !urls.isEmpty else { return }
        var importedRoutes = 0
        for url in urls {
            guard let data = try? readSecurityScopedFile(at: url) else { continue }
            importedRoutes += controller.importGpxData(data)
        }
        if importedRoutes > 0 {
            transferSummary = SimulationController.gpxImportedMessage(count: importedRoutes)
        } else {
            importError = SimulationController.gpxNoRoutesMessage
        }
    }

    private func restoreBackup(_ data: Data) {
        if let result = controller.importBackupData(data) {
            transferSummary = "已還原 \(result.favoriteCount) 個收藏、\(result.routeCount) 條路線、\(result.folderCount) 個資料夾與 \(result.presetCount) 個速度預設。"
        }
        pendingBackupData = nil
    }

    /// 「聯絡我們」：收件人、標題與內文都已填好（GFlyer-Suite docs/features/contact-us.md）。
    /// 沒有電郵 App 接手時把地址複製到剪貼簿，訊息和 Android 一字不差。
    private func openContactEmail() {
        let version = appVersion.version
        let subject = ContactEmail.subject(platform: "iOS", version: version)
        let body = ContactEmail.body(
            platform: "iOS",
            version: version,
            build: appVersion.build,
            system: "iOS \(UIDevice.current.systemVersion)",
            device: ContactEmail.hardwareIdentifier()
        )
        guard let url = ContactEmail.mailtoURL(subject: subject, body: body) else {
            showNoMailApp()
            return
        }
        openURL(url) { accepted in
            if !accepted { showNoMailApp() }
        }
    }

    private func showNoMailApp() {
        UIPasteboard.general.string = ContactEmail.address
        contactMessage = ContactEmail.noMailAppMessage
    }

    private func playbackBinding<Value>(
        _ keyPath: WritableKeyPath<PlaybackSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { controller.playbackSettings[keyPath: keyPath] },
            set: { value in controller.updatePlayback { $0[keyPath: keyPath] = value } }
        )
    }

    /// 把「有值就顯示」的 optional 狀態轉成 alert 需要的 Bool binding。
    private func binding<Value>(for value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }

    private func readSecurityScopedFile(at url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}
