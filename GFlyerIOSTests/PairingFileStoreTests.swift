import XCTest
@testable import GFlyerIOS

/// Pairing File 的存檔、匯出和移除（docs/APP_STORE_PLAN.md 第 5 項）。用暫存資料夾，不碰 App 真正的檔。
final class PairingFileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PairingFileStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testExportReturnsTheSavedFileUnchanged() throws {
        let store = PairingFileStore(directory: directory)
        XCTAssertFalse(store.isImported)

        let data = try samplePairingFile(identifier: "first")
        try store.save(data)

        XCTAssertTrue(store.isImported)
        XCTAssertEqual(try store.exportData(), data)
        XCTAssertEqual(store.url.deletingLastPathComponent().path, directory.path)
    }

    @MainActor
    func testSavingSomethingThatIsNotAPropertyListKeepsTheOldFile() throws {
        let store = PairingFileStore(directory: directory)
        let data = try samplePairingFile(identifier: "first")
        try store.save(data)

        // 沒有收尾的 XML；純文字可能被當成舊式 plist 的字串，所以不用。
        XCTAssertThrowsError(try store.save(Data("<plist><dict><key>broken".utf8)))
        XCTAssertEqual(try store.exportData(), data)
    }

    @MainActor
    func testExportAfterRemoveFails() throws {
        let store = PairingFileStore(directory: directory)
        try store.save(try samplePairingFile(identifier: "first"))

        try store.remove()

        XCTAssertFalse(store.isImported)
        XCTAssertThrowsError(try store.exportData())
    }

    func testExportFilenameIsAPropertyList() {
        XCTAssertEqual(URL(fileURLWithPath: PairingFileStore.exportFilename).pathExtension, "plist")
    }

    /// 和 idevice 的 `RpPairingFile::to_bytes` 同樣的鍵；內容是假的。
    private func samplePairingFile(identifier: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "public_key": Data(repeating: 1, count: 32),
                "private_key": Data(repeating: 2, count: 32),
                "identifier": identifier,
                "alt_irk": Data(repeating: 3, count: 16),
            ],
            format: .xml,
            options: 0
        )
    }
}
