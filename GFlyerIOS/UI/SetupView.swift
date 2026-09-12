import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var gpx: UTType { UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml }
}

struct ExportedDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .xml, .gpx] }
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
        case gpxRoutes
        case backup

        var contentType: UTType {
            switch self {
            case .gpxRoutes: return .gpx
            case .backup: return .json
            }
        }

        var defaultFilename: String {
            switch self {
            case .gpxRoutes: return "gflyer-routes.gpx"
            case .backup: return "gflyer-backup.json"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var controller: SimulationController
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject var stepRecorder: StepRecorderController
    @ObservedObject private var pairingStore: PairingFileStore
    @ObservedObject private var deviceLocation: DeviceLocationService
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
    @State private var showStepRecorder = false
    @State private var isForceClearing = false

    init(
        controller: SimulationController,
        updateChecker: AppUpdateChecker,
        stepRecorder: StepRecorderController
    ) {
        self.controller = controller
        self.updateChecker = updateChecker
        self.stepRecorder = stepRecorder
        _pairingStore = ObservedObject(wrappedValue: controller.pairingStore)
        _deviceLocation = ObservedObject(wrappedValue: controller.deviceLocation)
    }

    var body: some View {
        NavigationStack {
            formWithTransfers
                .alert("匯入失敗", isPresented: binding(for: $importError)) {
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
                .alert(
                    "更新",
                    isPresented: Binding(
                        get: { updateChecker.lastError != nil },
                        set: { if !$0 { updateChecker.lastError = nil } }
                    )
                ) {
                    Button("確定", role: .cancel) { updateChecker.lastError = nil }
                } message: {
                    Text(updateChecker.lastError ?? "未知錯誤")
                }
                .alert("完成", isPresented: binding(for: $transferSummary)) {
                    Button("確定", role: .cancel) { transferSummary = nil }
                } message: {
                    Text(transferSummary ?? "")
                }
                .sheet(isPresented: $showStepRecorder) {
                    StepRecorderView(recorder: stepRecorder)
                }
                .alert("清除結果", isPresented: binding(for: $forceClearMessage)) {
                    Button("確定", role: .cancel) { forceClearMessage = nil }
                } message: {
                    Text(forceClearMessage ?? "")
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
                Text("還原會以備份內容取代現有的收藏、歷史、資料夾、路線與速度預設。留言板登入與 Pairing File 不受影響。")
            }
    }

    private var formContent: some View {
        Form {
            backendSection
            pairingSection
            localDevVPNSection
            locationSection
            developerDiskImageSection
            speedPresetSection
            playbackSection
            orbitRadiusSection
            softwareUpdateSection
            stepRecorderSection
            transferSection
            instructionsSection
            if controller.canControlDeviceLocation { recoverySection }
        }
    }

    // MARK: - 區段

    // 版本放在設定頁第一列：使用者要確認裝到哪一版時，第一眼就看得到。
    private var backendSection: some View {
        Section("關於") {
            LabeledContent("App 版本", value: updateChecker.displayVersion)
            LabeledContent("Bundle ID", value: updateChecker.bundleIdentifier)
                .font(.caption.monospaced())
            LabeledContent("定位後端", value: controller.backendName)
            LabeledContent(
                "原生程式庫",
                value: controller.canControlDeviceLocation ? "已載入" : "尚未啟用"
            )
            if let guideURL = URL(string: "https://michaelcheung0125-svg.github.io/GFlyer-updates/USER_GUIDE_ZH_HK.html") {
                Button {
                    openURL(guideURL)
                } label: {
                    Label("使用教學", systemImage: "book")
                }
            }
        }
    }

    private var pairingSection: some View {
        Section("首次設定") {
            LabeledContent("Pairing File", value: pairingStore.isImported ? "已匯入" : "未匯入")
            Button {
                pendingImport = .pairingFile
                showImporter = true
            } label: {
                Label("匯入 Pairing File", systemImage: "doc.badge.plus")
            }
            if pairingStore.isImported {
                Button("移除 Pairing File", role: .destructive) {
                    do {
                        try pairingStore.remove()
                    } catch {
                        importError = describe(error)
                    }
                }
            }
        }
    }

    private var localDevVPNSection: some View {
        Section("LocalDevVPN") {
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
                    Label("測試 LocalDevVPN 通道", systemImage: "network.badge.shield.half.filled")
                }
            }
            .disabled(
                !controller.canControlDeviceLocation
                    || !pairingStore.isImported
                    || controller.isTestingTunnel
                    || controller.isMotionActive
            )
            Text("預設為 10.7.0.1，Remote Pairing port 為 49152。開始全機定位模擬前，請先在 LocalDevVPN 開啟 VPN。")
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
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !isDefaultPreset(preset) {
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
            .disabled(controller.quickSpeedPresets.count >= 12)
            .alert("新增速度預設", isPresented: $showPresetPrompt) {
                TextField("名稱", text: $presetName)
                TextField("速度 km/h", text: $presetSpeed)
                    .keyboardType(.decimalPad)
                Button("新增") { addSpeedPreset() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("速度會限制在 1.8 至 900 km/h")
            }
        }
    }

    private var playbackSection: some View {
        Section("路線播放") {
            Picker("開始前倒數", selection: playbackBinding(\.startDelaySeconds)) {
                ForEach(PlaybackSettings.startDelayOptions, id: \.self) { seconds in
                    Text(seconds == 0 ? "關閉" : "\(seconds) 秒").tag(seconds)
                }
            }
            Picker("自動停止", selection: playbackBinding(\.autoStopMinutes)) {
                ForEach(PlaybackSettings.autoStopOptions, id: \.self) { minutes in
                    Text(minutes == 0 ? "關閉" : "\(minutes) 分鐘").tag(minutes)
                }
            }
            Stepper(
                "逐點傳送停留 \(controller.playbackSettings.dwellSeconds) 秒",
                value: playbackBinding(\.dwellSeconds),
                in: PlaybackSettings.dwellRange,
                step: 5
            )
            Toggle("跨日期傳送提醒", isOn: playbackBinding(\.crossDateWarningEnabled))
            Picker("搖桿速度上限", selection: playbackBinding(\.joystickMaxSpeedKilometresPerHour)) {
                ForEach(PlaybackSettings.joystickMaxSpeedOptions, id: \.self) { speed in
                    Text("\(speed) km/h").tag(speed)
                }
            }
            Text("倒數方便先切回遊戲畫面；停留秒數只在多點路線的「逐點傳送」模式使用。搖桿以推桿幅度控制速度，推到底會持續加速到上限。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var orbitRadiusSection: some View {
        Section("到點繞圈半徑") {
            ForEach(Array(controller.playbackSettings.orbitRadiiMetres.enumerated()), id: \.offset) { index, radius in
                Stepper(
                    "第 \(index + 1) 圈 · \(radius) 米",
                    value: orbitRadiusBinding(index: index, fallback: radius),
                    in: PlaybackSettings.orbitRadiusRange,
                    step: 5
                )
            }
            HStack {
                Button {
                    controller.updatePlayback { settings in
                        settings.orbitRadiiMetres.append(PlaybackSettings.defaultOrbitRadiiMetres.last ?? 30)
                    }
                } label: {
                    Label("新增一圈", systemImage: "plus")
                }
                .disabled(controller.playbackSettings.orbitRadiiMetres.count >= PlaybackSettings.maxOrbitLaps)
                Spacer()
                Button(role: .destructive) {
                    controller.updatePlayback { settings in
                        if settings.orbitRadiiMetres.count > 1 {
                            settings.orbitRadiiMetres.removeLast()
                        }
                    }
                } label: {
                    Label("移除最後一圈", systemImage: "minus.circle")
                }
                .disabled(controller.playbackSettings.orbitRadiiMetres.count <= 1)
            }
            .buttonStyle(.borderless)
            Text("多點路線選擇「到點繞圈」時，會依序以這些半徑各繞一圈（最多 \(PlaybackSettings.maxOrbitLaps) 圈）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var softwareUpdateSection: some View {
        Section("軟體更新") {
            LabeledContent("更新狀態", value: updateChecker.statusMessage)
            Button {
                updateChecker.checkNow()
            } label: {
                if updateChecker.isChecking {
                    HStack {
                        ProgressView()
                        Text("正在檢查更新")
                    }
                } else {
                    Label("檢查更新", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(updateChecker.isChecking)
            if let update = updateChecker.availableUpdate {
                Button {
                    updateChecker.openInstaller(for: update)
                } label: {
                    Label("用 SideStore 更新到 \(update.displayVersion)", systemImage: "square.and.arrow.down")
                }
            }
            if let sourceURL = updateChecker.addSourceURL(using: .sideStore) {
                Button {
                    openURL(sourceURL)
                } label: {
                    Label("把更新來源加入 SideStore", systemImage: "plus.rectangle.on.folder")
                }
            }
            Text("GFlyer 不能自行安裝 IPA，更新一律交給 SideStore 或 AltStore 下載並用你的 Apple ID 重新簽名。免費 Apple ID 的簽名仍然每 7 天到期。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepRecorderSection: some View {
        Section("補錄步數") {
            Button {
                showStepRecorder = true
            } label: {
                LabeledContent {
                    Text("今天 \(stepRecorder.todaySteps) 步")
                        .font(.caption.monospacedDigit())
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

    private var transferSection: some View {
        Section("資料匯入與匯出") {
            Button {
                pendingImport = .gpxRoutes
                showImporter = true
            } label: {
                Label("匯入 GPX 路線", systemImage: "square.and.arrow.down")
            }
            .disabled(controller.isMotionActive)
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
            Text("備份檔為 GFlyer Backup v1 格式，包含收藏、歷史、資料夾、路線與速度預設，與 GFlyer Android 的備份/還原互通。留言板登入與 Pairing File 不會包含在備份內。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var instructionsSection: some View {
        Section("操作順序") {
            Text("1. 用電腦產生這部 iPhone 的 pairing file。")
            Text("2. 將檔案傳到 iPhone 並在此匯入。")
            Text("3. 開啟 LocalDevVPN。")
            Text("4. 回到地圖選點並按開始。")
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
            Text("想讓其他 App 回到真實位置時使用：清除模擬、關閉模擬 session，並驗證目前回報的定位。iOS 可能要取得新的真實定位後才會更新；若驗證顯示仍是模擬座標，關閉 LocalDevVPN 並開關一次飛行模式通常可解決。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func isDefaultPreset(_ preset: QuickSpeedPreset) -> Bool {
        SpeedScale.defaultPresets.contains {
            $0.name == preset.name && $0.kilometresPerHour == preset.kilometresPerHour
        }
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

    private func loadBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            pendingBackupData = try readSecurityScopedFile(at: url)
        } catch {
            importError = describe(error)
        }
    }

    private func importGpx(_ result: Result<[URL], Error>) {
        do {
            var importedRoutes = 0
            for url in try result.get() {
                let data = try readSecurityScopedFile(at: url)
                importedRoutes += controller.importGpxData(data)
            }
            if importedRoutes > 0 {
                transferSummary = "已匯入 \(importedRoutes) 條 GPX 路線。"
            }
        } catch {
            importError = describe(error)
        }
    }

    private func restoreBackup(_ data: Data) {
        if let result = controller.importBackupData(data) {
            transferSummary = "已還原 \(result.favoriteCount) 個收藏、\(result.routeCount) 條路線、\(result.folderCount) 個資料夾與 \(result.presetCount) 個速度預設。"
        }
        pendingBackupData = nil
    }

    private func playbackBinding<Value>(
        _ keyPath: WritableKeyPath<PlaybackSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { controller.playbackSettings[keyPath: keyPath] },
            set: { value in controller.updatePlayback { $0[keyPath: keyPath] = value } }
        )
    }

    private func orbitRadiusBinding(index: Int, fallback: Int) -> Binding<Int> {
        Binding(
            get: {
                let radii = controller.playbackSettings.orbitRadiiMetres
                return radii.indices.contains(index) ? radii[index] : fallback
            },
            set: { value in
                controller.updatePlayback { settings in
                    if settings.orbitRadiiMetres.indices.contains(index) {
                        settings.orbitRadiiMetres[index] = value
                    }
                }
            }
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
