import Foundation
import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: SimulationController
    @ObservedObject private var pairingStore: PairingFileStore
    @ObservedObject private var deviceLocation: DeviceLocationService
    @State private var showImporter = false
    @State private var importError: String?
    @State private var showPresetPrompt = false
    @State private var presetName = ""
    @State private var presetSpeed = "50"

    init(controller: SimulationController) {
        self.controller = controller
        _pairingStore = ObservedObject(wrappedValue: controller.pairingStore)
        _deviceLocation = ObservedObject(wrappedValue: controller.deviceLocation)
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
                "通道操作失敗",
                isPresented: Binding(
                    get: { controller.lastError != nil },
                    set: { if !$0 { controller.lastError = nil } }
                )
            ) {
                Button("確定", role: .cancel) { controller.lastError = nil }
            } message: {
                Text(controller.lastError ?? "未知錯誤")
            }
        }
    }
}
