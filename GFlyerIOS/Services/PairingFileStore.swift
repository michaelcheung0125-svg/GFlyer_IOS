import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PairingFileStore: ObservableObject {
    static let fileName = "pairingFile.plist"
    static let supportedTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList,
    ]

    /// 匯出到「檔案」時的預設檔名。和 idevice_pair 產生的 RP Pairing File 一樣是 XML plist。
    nonisolated static let exportFilename = "gflyer-pairing-file.plist"

    @Published private(set) var isImported = false
    @Published private(set) var revision = UUID()

    private let directory: URL

    /// `directory` 只給測試用；App 一律存在 Application Support/Pairing。
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
        refresh()
    }

    var url: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    func refresh() {
        isImported = FileManager.default.fileExists(atPath: url.path)
        revision = UUID()
    }

    func importFile(from sourceURL: URL) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        try save(Data(contentsOf: sourceURL))
    }

    /// 匯入和「在這支 iPhone 上配對」共用：同一個位置、同樣的檔案保護。
    /// 不是合法的 plist 就丟出錯誤，舊檔保持不變。
    func save(_ data: Data) throws {
        let fileManager = FileManager.default
        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes(
            [
                .posixPermissions: 0o600,
                .protectionKey: FileProtectionType.complete,
            ],
            ofItemAtPath: url.path
        )
        refresh()
    }

    /// 「匯出 Pairing File」：原樣交出存著的檔案，匯入或在這支 iPhone 上配對得到的都一樣。
    func exportData() throws -> Data {
        try Data(contentsOf: url)
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refresh()
    }
}
