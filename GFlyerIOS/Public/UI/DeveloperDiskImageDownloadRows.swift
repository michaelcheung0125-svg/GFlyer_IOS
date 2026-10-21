import SwiftUI

/// 公開版設定頁「Developer Disk Image」section：DDI 狀態、下載按鈕（連大小）和說明。
struct DeveloperDiskImageDownloadRows: View {
    @ObservedObject var controller: SimulationController
    @ObservedObject var download: DeveloperDiskImageDownload

    var body: some View {
        LabeledContent("DDI 狀態", value: statusLabel)
            .task { await download.refresh() }
        Button {
            controller.downloadDeveloperDiskImage(download)
        } label: {
            Label(Edition.developerDiskImageDownloadTitle, systemImage: "arrow.down.circle")
        }
        .disabled(download.state != .missing)
        Text("傳送定位前，iPhone 要先掛載 Apple 的 Developer Disk Image（DDI）。按「\(Edition.developerDiskImageDownloadTitle)」後，GFlyer 會從 GitHub 下載固定版本的 DDI，經 SHA-256 驗證後保留在本機，之後不用再下載。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var statusLabel: String {
        switch download.state {
        case .checking: return "檢查中…"
        case .missing: return "未下載"
        case .downloading: return "下載中…"
        case .downloaded: return "已下載"
        }
    }
}
