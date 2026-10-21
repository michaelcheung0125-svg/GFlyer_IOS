import XCTest
@testable import GFlyerIOS

/// 公開版設定頁下載 DDI 的狀態。`DeveloperDiskImageStore` 換成假的，測試不碰網絡。
@MainActor
final class DeveloperDiskImageDownloadTests: XCTestCase {
    private struct Failure: LocalizedError {
        var errorDescription: String? { "網絡中斷" }
    }

    @MainActor
    private final class FakeStore: DeveloperDiskImageDownloading {
        var downloaded = false
        var downloadError: Error?
        var downloads = 0
        /// `holdsCheck`／`holdsDownload` 設了的話，`isDownloaded`／`download` 等到對應的
        /// continuation 被呼叫才返回。
        var holdsCheck = false
        var heldCheck: CheckedContinuation<Void, Never>?
        var holdsDownload = false
        var heldDownload: CheckedContinuation<Void, Never>?

        func isDownloaded() async -> Bool {
            if holdsCheck {
                await withCheckedContinuation { heldCheck = $0 }
            }
            return downloaded
        }

        func download() async throws {
            downloads += 1
            if holdsDownload {
                await withCheckedContinuation { heldDownload = $0 }
            }
            if let downloadError { throw downloadError }
            downloaded = true
        }
    }

    func testRefreshShowsWhetherTheFilesAreThere() async {
        let store = FakeStore()
        let model = DeveloperDiskImageDownload(store: store)
        XCTAssertEqual(model.state, .checking)

        await model.refresh()
        XCTAssertEqual(model.state, .missing)

        store.downloaded = true
        await model.refresh()
        XCTAssertEqual(model.state, .downloaded)
    }

    func testDownloadMarksTheImageDownloaded() async {
        let store = FakeStore()
        let model = DeveloperDiskImageDownload(store: store)
        await model.refresh()

        let failure = await model.download()
        XCTAssertNil(failure)
        XCTAssertEqual(model.state, .downloaded)
        XCTAssertEqual(store.downloads, 1)
    }

    func testAFailedDownloadReportsTheErrorAndCanBePressedAgain() async {
        let store = FakeStore()
        store.downloadError = Failure()
        let model = DeveloperDiskImageDownload(store: store)
        await model.refresh()

        let failure = await model.download()
        XCTAssertEqual(failure, "DDI 下載失敗：網絡中斷")
        XCTAssertEqual(model.state, .missing)
    }

    func testRefreshAndASecondPressWhileDownloadingLeaveTheDownloadAlone() async {
        let store = FakeStore()
        store.holdsDownload = true
        let model = DeveloperDiskImageDownload(store: store)
        let first = Task { await model.download() }
        while store.heldDownload == nil { await Task.yield() }
        XCTAssertEqual(model.state, .downloading)

        await model.refresh()
        XCTAssertEqual(model.state, .downloading)
        let second = await model.download()
        XCTAssertNil(second)
        XCTAssertEqual(store.downloads, 1)

        store.heldDownload?.resume()
        let failure = await first.value
        XCTAssertNil(failure)
        XCTAssertEqual(model.state, .downloaded)
    }

    /// 打開設定頁時開始的檢查，在使用者按了下載之後才查完：不可以蓋掉「下載中…」。
    func testACheckThatFinishesAfterTheDownloadStartedDoesNotOverwriteIt() async {
        let store = FakeStore()
        store.holdsCheck = true
        store.holdsDownload = true
        let model = DeveloperDiskImageDownload(store: store)
        let check = Task { await model.refresh() }
        while store.heldCheck == nil { await Task.yield() }
        let download = Task { await model.download() }
        while store.heldDownload == nil { await Task.yield() }

        store.heldCheck?.resume()
        await check.value
        XCTAssertEqual(model.state, .downloading)

        store.heldDownload?.resume()
        _ = await download.value
        XCTAssertEqual(model.state, .downloaded)
    }

    /// 公開版不自己下載：開始或測試連線時沒有 DDI，錯誤要指到設定頁的按鈕，按鈕寫明大小。
    func testTheMissingMessagePointsAtTheDownloadButtonAndItsSize() {
        XCTAssertEqual(Edition.developerDiskImageDownloadTitle, "下載 DDI（約 16.5 MB）")
        XCTAssertEqual(
            Edition.developerDiskImageMissingMessage,
            "還沒有下載 DDI。請到設定頁的「Developer Disk Image」按「下載 DDI（約 16.5 MB）」，完成後再試。"
        )
    }
}
