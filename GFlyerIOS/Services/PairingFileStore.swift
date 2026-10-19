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

    @Published private(set) var isImported = false
    @Published private(set) var revision = UUID()

    init() {
        refresh()
    }

    var url: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
        return directory.appendingPathComponent(Self.fileName)
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

    func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refresh()
    }
}
