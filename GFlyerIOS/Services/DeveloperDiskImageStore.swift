import CryptoKit
import Foundation

struct DeveloperDiskImageFiles: Sendable {
    let image: URL
    let trustCache: URL
    let buildManifest: URL
}

actor DeveloperDiskImageStore {
    static let shared = DeveloperDiskImageStore()

    /// nil 是 App 的 Application Support 裏的 `DeveloperDiskImage`；測試給暫存資料夾。
    private let baseDirectory: URL?

    init(directory: URL? = nil) {
        baseDirectory = directory
    }

    private struct Download: Sendable {
        let name: String
        let sha256: String
        /// 檔案大小，只用來告訴使用者要下載多少（`downloadSizeText`）；內容由 `sha256` 核對。
        let bytes: Int
    }

    private static let revision = "5423e4e955fbb3a9eef3e1212acfbfc6e7a26236"
    private static let downloads = [
        Download(
            name: "BuildManifest.plist",
            sha256: "8edd4a2f4f4ef1fbd7bfe49785d8badc673d1395d1d94d85b132ca8ab5ecaf54",
            bytes: 801_505
        ),
        Download(
            name: "Image.dmg",
            sha256: "05fd807da5e19f030fa4941f24800c965c6c77982ab572dd5d1ef778fb69f9ca",
            bytes: 15_733_248
        ),
        Download(
            name: "Image.dmg.trustcache",
            sha256: "36af60889ff5a737874a26daeb8e1a0139ebfebec6ec2e4d8f6a3c1bf1dce35c",
            bytes: 1_895
        ),
    ]

    /// 三個檔案合計的大小，例如「16.5 MB」（1 MB = 1,000,000 bytes，和 iOS 顯示的相同）。
    static let downloadSizeText = String(
        format: "%.1f MB", Double(downloads.map(\.bytes).reduce(0, +)) / 1_000_000
    )

    /// 掛載要用的三個檔案。本機沒有或驗證不過的：`missingMessage` 是 nil 就下載（親友版），
    /// 有值就不下載，丟出這句錯誤（公開版要使用者先在設定頁按下載，見
    /// `EditionFeatures.developerDiskImageMissingMessage`）。
    func prepare(missingMessage: String? = nil) async throws -> DeveloperDiskImageFiles {
        let directory = try directoryURL()
        for download in Self.downloads {
            let destination = directory.appendingPathComponent(download.name)
            if (try? isValid(destination, expectedHash: download.sha256)) == true {
                continue
            }
            if let missingMessage {
                throw SimulationError.developerDiskImage(missingMessage)
            }
            try? FileManager.default.removeItem(at: destination)
            try await downloadFile(download, to: destination)
        }

        return DeveloperDiskImageFiles(
            image: directory.appendingPathComponent("Image.dmg"),
            trustCache: directory.appendingPathComponent("Image.dmg.trustcache"),
            buildManifest: directory.appendingPathComponent("BuildManifest.plist")
        )
    }

    /// 三個檔案都在本機而且驗證得過。
    func isDownloaded() -> Bool {
        guard let directory = try? directoryURL() else { return false }
        return Self.downloads.allSatisfy {
            (try? isValid(directory.appendingPathComponent($0.name), expectedHash: $0.sha256)) == true
        }
    }

    /// 下載本機沒有或驗證不過的檔案。
    func download() async throws {
        _ = try await prepare()
    }

    private func directoryURL() throws -> URL {
        let directory = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeveloperDiskImage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func downloadFile(_ download: Download, to destination: URL) async throws {
        let base = "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/\(Self.revision)/PersonalizedImages/Xcode_iOS_DDI_Personalized"
        guard let url = URL(string: "\(base)/\(download.name)") else {
            throw SimulationError.developerDiskImage("DDI 下載網址無效。")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw SimulationError.developerDiskImage("無法下載 \(download.name)。")
        }
        guard hash(data) == download.sha256 else {
            throw SimulationError.developerDiskImage("\(download.name) 的 SHA-256 驗證失敗。")
        }

        try data.write(to: destination, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        var protectedURL = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(values)
    }

    private func isValid(_ url: URL, expectedHash: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return hash(try Data(contentsOf: url, options: .mappedIfSafe)) == expectedHash
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
