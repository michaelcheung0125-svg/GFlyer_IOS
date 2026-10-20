import SwiftUI

/// 主畫面的「有新版本」提示。
struct UpdatePromptAlert: ViewModifier {
    @ObservedObject var updateChecker: AppUpdateChecker

    func body(content: Content) -> some View {
        content.alert(
            "有新版本",
            isPresented: $updateChecker.showsPrompt,
            presenting: updateChecker.availableUpdate
        ) { update in
            Button("用 SideStore 更新") { updateChecker.openInstaller(for: update) }
            Button("今日不再顯示") { updateChecker.snoozeForToday() }
            Button("稍後", role: .cancel) { updateChecker.dismissPrompt() }
        } message: { update in
            Text(message(for: update))
        }
    }

    private func message(for update: AvailableUpdate) -> String {
        var text = "GFlyer \(update.displayVersion) 已發佈（目前為 \(updateChecker.displayVersion)）。"
        if !update.releaseNotes.isEmpty {
            text += "\n\n\(update.releaseNotes)"
        }
        text += "\n\n更新會交給 SideStore 下載並用你的 Apple ID 重新簽名。"
        return text
    }
}

/// 設定頁的「更新」錯誤提示：手動檢查失敗，或找不到 SideStore、AltStore。
struct UpdateErrorAlert: ViewModifier {
    @ObservedObject var updateChecker: AppUpdateChecker

    func body(content: Content) -> some View {
        content.alert(
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
    }
}

/// 設定頁的「軟體更新」。
struct SoftwareUpdateSection: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var updateChecker: AppUpdateChecker

    var body: some View {
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
}
