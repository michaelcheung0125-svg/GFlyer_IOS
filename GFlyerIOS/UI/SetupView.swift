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

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var controller: SimulationController
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject private var pairingStore: PairingFileStore
    @ObservedObject private var deviceLocation: DeviceLocationService
    @State private var showImporter = false
    @State private var importError: String?
    @State private var showPresetPrompt = false
    @State private var presetName = ""
    @State private var presetSpeed = "50"
    @State private var showGpxImporter = false
    @State private var showGpxExporter = false
    @State private var gpxDocument = ExportedDataDocument()
    @State private var showBackupImporter = false
    @State private var showBackupExporter = false
    @State private var backupDocument = ExportedDataDocument()
    @State private var pendingBackupData: Data?
    @State private var transferSummary: String?

    init(controller: SimulationController, updateChecker: AppUpdateChecker) {
        self.controller = controller
        self.updateChecker = updateChecker
        _pairingStore = ObservedObject(wrappedValue: controller.pairingStore)
        _deviceLocation = ObservedObject(wrappedValue: controller.deviceLocation)
    }

    private func playbackBinding<Value>(
        _ keyPath: WritableKeyPath<PlaybackSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { controller.playbackSettings[keyPath: keyPath] },
            set: { value in controller.updatePlayback { $0[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("定位後端") {
                    LabeledContent("目前後端", value: controller.backendName)
                    LabeledContent(
                        "原生程式庫",
                        value: controller.canControlDeviceLocation ? "已載入" : "尚未啟用"
                    )
                }

                Section("首次設定") {
                    LabeledContent(
                        "Pairing File",
                        value: pairingStore.isImported ? "已匯入" : "未匯入"
                    )
                    Button {
                        showImporter = true
                    } label: {
                        Label("匯入 Pairing File", systemImage: "doc.badge.plus")
                    }
                    if pairingStore.isImported {
                        Button("移除 Pairing File", role: .destructive) {
                            do {
                                try pairingStore.remove()
                            } catch {
                                importError = error.localizedDescription
                            }
                        }
                    }
                }

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

                Section("Developer Disk Image") {
                    Text("第一次使用裝置模式時，GFlyer 會下載約 16 MB、固定版本並經 SHA-256 驗證的 Personalized DDI，之後保留在本機使用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("速度預設") {
                    ForEach(controller.quickSpeedPresets) { preset in
                        HStack {
                            Text(preset.name)
                            Spacer()
                            Text(String(format: "%.1f km/h", preset.kilometresPerHour))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if !SpeedScale.defaultPresets.contains(where: { $0.name == preset.name && $0.kilometresPerHour == preset.kilometresPerHour }) {
                                Button(role: .destructive) { controller.removeQuickSpeedPreset(preset.id) } label: {
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
                        Button("新增") {
                            if let speed = Double(presetSpeed), !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                controller.saveQuickSpeedPreset(name: presetName, speed: speed)
                            }
                            presetName = ""
                            presetSpeed = "50"
                        }
                        Button("取消", role: .cancel) { }
                    } message: {
                        Text("速度會限制在 1.8 至 900 km/h")
                    }
                }

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

                Section("到點繞圈半徑") {
                    ForEach(Array(controller.playbackSettings.orbitRadiiMetres.enumerated()), id: \.offset) { index, radius in
                        Stepper(
                            "第 \(index + 1) 圈 · \(radius) 米",
                            value: Binding(
                                get: {
                                    let radii = controller.playbackSettings.orbitRadiiMetres
                                    return radii.indices.contains(index) ? radii[index] : radius
                                },
                                set: { value in
                                    controller.updatePlayback { settings in
                                        if settings.orbitRadiiMetres.indices.contains(index) {
                                            settings.orbitRadiiMetres[index] = value
                                        }
                                    }
                                }
                            ),
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

                Section("軟體更新") {
                    LabeledContent("目前版本", value: updateChecker.displayVersion)
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

                Section("資料匯入與匯出") {
                    Button { showGpxImporter = true } label: {
                        Label("匯入 GPX 路線", systemImage: "square.and.arrow.down")
                    }
                    .disabled(controller.isMotionActive)
                    Button {
                        if let data = controller.exportAllRoutesAsGpx() {
                            gpxDocument = ExportedDataDocument(data: data)
                            showGpxExporter = true
                        }
                    } label: {
                        Label("匯出全部路線（GPX）", systemImage: "square.and.arrow.up")
                    }
                    .disabled(controller.savedRoutes.isEmpty)
                    Button {
                        if let data = controller.exportBackupData() {
                            backupDocument = ExportedDataDocument(data: data)
                            showBackupExporter = true
                        }
                    } label: {
                        Label("匯出備份檔", systemImage: "externaldrive.badge.timemachine")
                    }
                    Button { showBackupImporter = true } label: {
                        Label("還原備份檔", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(controller.isMotionActive)
                    Text("備份檔為 GFlyer Backup v1 格式，包含收藏、歷史、資料夾、路線與速度預設，與 GFlyer Android 的備份/還原互通。留言板登入與 Pairing File 不會包含在備份內。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("操作順序") {
                    Text("1. 用電腦產生這部 iPhone 的 pairing file。")
                    Text("2. 將檔案傳到 iPhone 並在此匯入。")
                    Text("3. 開啟 LocalDevVPN。")
                    Text("4. 回到地圖選點並按開始。")
                }

                if controller.canControlDeviceLocation {
                    Section("恢復") {
                        Button("強制清除模擬定位", role: .destructive) {
                            controller.stop()
                        }
                        Text("App 曾被強制關閉或重新啟動時，可使用此操作重新連線並恢復真實 GPS。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("裝置設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: PairingFileStore.supportedTypes
            ) { result in
                do {
                    try pairingStore.importFile(from: result.get())
                } catch {
                    importError = error.localizedDescription
                }
            }
            .alert(
                "匯入失敗",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
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
            .fileImporter(
                isPresented: $showGpxImporter,
                allowedContentTypes: [.gpx, .xml],
                allowsMultipleSelection: true
            ) { result in
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
                    importError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $showGpxExporter,
                document: gpxDocument,
                contentType: .gpx,
                defaultFilename: "gflyer-routes.gpx"
            ) { result in
                if case let .failure(error) = result { importError = error.localizedDescription }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json]
            ) { result in
                do {
                    pendingBackupData = try readSecurityScopedFile(at: result.get())
                } catch {
                    importError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $showBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "gflyer-backup.json"
            ) { result in
                if case let .failure(error) = result { importError = error.localizedDescription }
            }
            .alert(
                "還原備份",
                isPresented: Binding(
                    get: { pendingBackupData != nil },
                    set: { if !$0 { pendingBackupData = nil } }
                ),
                presenting: pendingBackupData
            ) { data in
                Button("還原", role: .destructive) {
                    if let result = controller.importBackupData(data) {
                        transferSummary = "已還原 \(result.favoriteCount) 個收藏、\(result.routeCount) 條路線、\(result.folderCount) 個資料夾與 \(result.presetCount) 個速度預設。"
                    }
                    pendingBackupData = nil
                }
                Button("取消", role: .cancel) { pendingBackupData = nil }
            } message: { _ in
                Text("還原會以備份內容取代現有的收藏、歷史、資料夾、路線與速度預設。留言板登入與 Pairing File 不受影響。")
            }
            .alert(
                "完成",
                isPresented: Binding(
                    get: { transferSummary != nil },
                    set: { if !$0 { transferSummary = nil } }
                )
            ) {
                Button("確定", role: .cancel) { transferSummary = nil }
            } message: {
                Text(transferSummary ?? "")
            }
        }
    }

    private func readSecurityScopedFile(at url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}
