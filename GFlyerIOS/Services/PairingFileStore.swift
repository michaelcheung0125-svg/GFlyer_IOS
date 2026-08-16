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
        let fileManager = FileManager.default
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: sourceURL)
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
