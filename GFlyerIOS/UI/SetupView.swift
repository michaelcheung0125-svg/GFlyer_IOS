import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: SimulationController
    @ObservedObject private var pairingStore: PairingFileStore
    @State private var showImporter = false
    @State private var importError: String?

    init(controller: SimulationController) {
        self.controller = controller
        _pairingStore = ObservedObject(wrappedValue: controller.pairingStore)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("定位後端") {
                    LabeledContent("目前後端", value: controller.backendName)
                    LabeledContent(
                        "全機 GPS",
                        value: controller.canControlDeviceLocation ? "可用" : "尚未啟用"
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
                    Text("預設為 10.7.0.1。開始全機定位模擬前，請先在 LocalDevVPN 開啟 VPN。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Developer Disk Image") {
                    Text("第一次使用裝置模式時，GFlyer 會下載約 16 MB、固定版本並經 SHA-256 驗證的 Personalized DDI，之後保留在本機使用。")
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
        }
    }
}
