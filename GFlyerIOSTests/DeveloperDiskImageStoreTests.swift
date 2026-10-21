import XCTest
@testable import GFlyerIOS

/// `DeveloperDiskImageStore` 不碰網絡的部分，用暫存資料夾。兩個版本的 test target 都跑。
final class DeveloperDiskImageStoreTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gflyer-ddi-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func testDownloadSizeAddsUpTheThreeFiles() {
        XCTAssertEqual(DeveloperDiskImageStore.downloadSizeText, "16.5 MB")
    }

    /// 公開版給了錯誤文字：本機沒有檔案時丟出它，不下載。
    func testPrepareWithAMissingMessageThrowsItWithoutDownloading() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeveloperDiskImageStore(directory: directory)

        let downloaded = await store.isDownloaded()
        XCTAssertFalse(downloaded)
        do {
            _ = try await store.prepare(missingMessage: "請先下載")
            XCTFail("沒有檔案時應該丟出錯誤")
        } catch {
            XCTAssertEqual(error.localizedDescription, "請先下載")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    /// 檔案在但 SHA-256 不對，也算沒有。
    func testFilesThatFailTheHashCheckCountAsMissing() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        let store = DeveloperDiskImageStore(directory: directory)

        let downloaded = await store.isDownloaded()
        XCTAssertFalse(downloaded)
        do {
            _ = try await store.prepare(missingMessage: "請先下載")
            XCTFail("驗證不過時應該丟出錯誤")
        } catch {
            XCTAssertEqual(error.localizedDescription, "請先下載")
        }
    }
}
