import XCTest
@testable import GFlyerIOS

/// ☆ 的命名 sheet(GFlyer-Suite docs/features/favorite-add.md §3.3、§3.4,第 6 節的 iOS 0.6.11 單元測試):
/// sheet 上的文字、名稱欄位的鎖住與填入規則(`FavoriteNameField`,對照 Android `FavoriteAddTest`),
/// 與等地名的 10 秒上限(`FavoriteNameLookup`)。插隊反查本身在 `RegionLookupUrgentTests`;
/// sheet 的外觀(半高、沒有鍵盤、往下滑等於取消)要上機看。
@MainActor
final class FavoriteNameSheetTests: XCTestCase {

    // MARK: - 文字

    func testTextsMatchAndroidWordForWord() {
        XCTAssertEqual(FavoriteAddTexts.dialogTitle, "收藏位置")
        XCTAssertEqual(FavoriteAddTexts.nameLabel, "名稱")
        XCTAssertEqual(FavoriteAddTexts.namePlaceholder, "留空就用座標當名稱")
        XCTAssertEqual(FavoriteAddTexts.lookingUpHint, "正在查詢地名\u{2026}")
        XCTAssertEqual(FavoriteAddTexts.lookingUpHint.unicodeScalars.last?.value, 0x2026, "結尾是一個「…」,不是三個句點")
        XCTAssertFalse(FavoriteAddTexts.lookingUpHint.contains("."))
        XCTAssertEqual(FavoriteAddTexts.confirmButton, "收藏")
        XCTAssertEqual(FavoriteAddTexts.cancelButton, "取消")
        XCTAssertEqual(FavoriteNameLookup.timeoutSeconds, 10, "Android FavoriteAdd.NameLookupTimeoutMillis = 10_000L")
    }

    /// 每按一次 ☆ 是新的 id(`.sheet(item:)` 用它重新建畫面、重新預填);相等只看座標與預填。
    func testEachPressIsANewSheetWithTheSameContent() {
        let first = FavoriteNameRequest(coordinate: NameSpot.taipei, suggestedName: "臺灣 · 臺北市")
        let second = FavoriteNameRequest(coordinate: NameSpot.taipei, suggestedName: "臺灣 · 臺北市")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, FavoriteNameRequest(coordinate: NameSpot.taipei, suggestedName: ""))
    }

    // MARK: - FavoriteNameField:打開時

    func testWithoutACachedLabelTheFieldStartsEmptyUnlockedAndLookingUp() {
        let field = FavoriteNameField(suggestedName: "")
        XCTAssertEqual(field.text, "")
        XCTAssertFalse(field.locked)
        XCTAssertTrue(field.isLookingUp, "欄位下方顯示「正在查詢地名…」")
    }

    func testACachedLabelIsPrefilledLockedAndNotLookedUp() {
        let field = FavoriteNameField(suggestedName: "臺灣 · 臺北市")
        XCTAssertEqual(field.text, "臺灣 · 臺北市")
        XCTAssertTrue(field.locked)
        XCTAssertFalse(field.isLookingUp)
    }

    // MARK: - FavoriteNameField:填入規則

    func testAnUntouchedEmptyFieldTakesTheLabelOnce() {
        var field = FavoriteNameField(suggestedName: "")
        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "臺灣 · 臺北市", "標籤原文")
        XCTAssertTrue(field.locked, "填了就鎖住")
        XCTAssertFalse(field.isLookingUp, "提示消失")

        field.labelArrived("日本 · 大阪市")
        XCTAssertEqual(field.text, "臺灣 · 臺北市", "最多只填一次")
    }

    func testTypedTextIsNeverReplaced() {
        var field = FavoriteNameField(suggestedName: "")
        field.edit("公司")
        XCTAssertTrue(field.locked)
        XCTAssertTrue(field.isLookingUp, "打字不會讓提示消失")

        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "公司")
        XCTAssertFalse(field.isLookingUp)
    }

    func testTypingAndClearingKeepsTheFieldEmpty() {
        var field = FavoriteNameField(suggestedName: "")
        field.edit("公")
        field.edit("")
        XCTAssertEqual(field.text, "")
        XCTAssertTrue(field.locked, "打了字又全部刪光也是使用者的修改")

        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "", "不填")
    }

    /// 只是點進欄位、移動游標:文字沒變,不算動過(Compose 的 `onValueChange` 只在文字改變時呼叫)。
    func testFocusingWithoutChangingTheTextDoesNotLock() {
        var field = FavoriteNameField(suggestedName: "")
        field.edit("")
        XCTAssertFalse(field.locked)

        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "臺灣 · 臺北市")
    }

    func testAFilledLabelThatWasClearedIsNotFilledBack() {
        var field = FavoriteNameField(suggestedName: "")
        field.labelArrived("臺灣 · 臺北市")
        field.edit("")
        XCTAssertEqual(field.text, "")

        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "", "填好的地名被刪光,之後也不填回")
    }

    func testACachedPrefillIsNeverReplacedNorFilledBack() {
        var field = FavoriteNameField(suggestedName: "臺灣 · 臺北市")
        field.labelArrived("日本 · 大阪市")
        XCTAssertEqual(field.text, "臺灣 · 臺北市", "快取的預填不會被晚到的地名換掉")

        field.edit("")
        field.labelArrived("日本 · 大阪市")
        XCTAssertEqual(field.text, "", "預填被刪光後也不填回")

        field.edit("我家")
        XCTAssertEqual(field.text, "我家")
    }

    func testAFailedLookupOnlyHidesTheHint() {
        var empty = FavoriteNameField(suggestedName: "")
        empty.lookupFailed()
        XCTAssertFalse(empty.isLookingUp)
        XCTAssertEqual(empty.text, "")

        var typed = FavoriteNameField(suggestedName: "")
        typed.edit("公司")
        typed.lookupFailed()
        XCTAssertFalse(typed.isLookingUp)
        XCTAssertEqual(typed.text, "公司")
    }

    func testAfterTheTimeoutALateLabelIsNotFilled() {
        var field = FavoriteNameField(suggestedName: "")
        field.timedOut()
        XCTAssertFalse(field.isLookingUp, "提示消失")
        XCTAssertEqual(field.text, "")

        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "", "10 秒之後才到的地名不填")
        field.edit("公司")
        XCTAssertEqual(field.text, "公司", "欄位照樣可以打字")
    }

    func testFinishLookupAppliesEachOutcome() {
        var found = FavoriteNameField(suggestedName: "")
        found.finishLookup(.found("臺灣 · 臺北市"))
        XCTAssertEqual(found, FavoriteNameField(suggestedName: "臺灣 · 臺北市"), "等於打開時就有快取的樣子")

        var failed = FavoriteNameField(suggestedName: "")
        failed.finishLookup(.failed)
        XCTAssertEqual(failed.text, "")
        XCTAssertFalse(failed.isLookingUp)

        var timedOut = FavoriteNameField(suggestedName: "")
        timedOut.finishLookup(.timedOut)
        timedOut.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(timedOut.text, "")
        XCTAssertFalse(timedOut.isLookingUp)
    }

    // MARK: - FavoriteNameLookup:最多等 10 秒

    func testALabelThatArrivesInTimeIsUsed() async {
        let outcome = await FavoriteNameLookup.firstOutcome(lookUp: { "臺灣 · 臺北市" })
        XCTAssertEqual(outcome, .found("臺灣 · 臺北市"))
    }

    func testALookupThatFindsNothingEndsTheWait() async {
        let outcome = await FavoriteNameLookup.firstOutcome(lookUp: { nil })
        XCTAssertEqual(outcome, .failed)
    }

    /// 10 秒先到:不再等,提示消失;反查不被取消,之後才到的地名照樣交出去(進快取與清單),但不填進欄位。
    func testTheWaitEndsAfterTenSecondsWithoutCancellingTheLookup() async {
        let gate = LabelGate()
        let sleeps = SleepLog()
        let outcome = await FavoriteNameLookup.firstOutcome(
            sleeper: { seconds in await sleeps.record(seconds) },
            lookUp: { await gate.wait() }
        )
        XCTAssertEqual(outcome, .timedOut)
        let recorded = await sleeps.seconds
        XCTAssertEqual(recorded, [10], "從打開時算起等 10 秒")

        var field = FavoriteNameField(suggestedName: "")
        field.finishLookup(outcome)
        XCTAssertFalse(field.isLookingUp)

        await waitUntil("反查還在等") { gate.isWaiting }
        gate.open("臺灣 · 臺北市")
        await waitUntil("反查拿到結果") { !gate.finishedWhileCancelled.isEmpty }
        XCTAssertEqual(gate.finishedWhileCancelled, [false], "逾時不取消反查")
        field.labelArrived("臺灣 · 臺北市")
        XCTAssertEqual(field.text, "")
    }

    /// sheet 關掉:`.task` 被取消,等待馬上結束;反查不跟著取消。
    func testClosingTheSheetStopsWaitingButNotTheLookup() async {
        let gate = LabelGate()
        let waiting = Task { await FavoriteNameLookup.firstOutcome(lookUp: { await gate.wait() }) }
        await waitUntil("反查開始等") { gate.isWaiting }

        waiting.cancel()
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .timedOut, "沒有人要看結果了")

        gate.open("臺灣 · 臺北市")
        await waitUntil("反查拿到結果") { !gate.finishedWhileCancelled.isEmpty }
        XCTAssertEqual(gate.finishedWhileCancelled, [false])
    }

    // MARK: - 輔助

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("等不到:\(description)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// 測試控制的反查:`wait()` 一直等到 `open(_:)` 才回傳。記下每次等完時呼叫它的 Task 有沒有被取消。
@MainActor
private final class LabelGate {
    private var waiting: [CheckedContinuation<String?, Never>] = []
    private(set) var finishedWhileCancelled: [Bool] = []

    var isWaiting: Bool { !waiting.isEmpty }

    func wait() async -> String? {
        let label = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            waiting.append(continuation)
        }
        finishedWhileCancelled.append(Task.isCancelled)
        return label
    }

    func open(_ label: String?) {
        let resumed = waiting
        waiting.removeAll()
        for continuation in resumed {
            continuation.resume(returning: label)
        }
    }
}

/// 假的逾時:只記下要等幾秒,馬上回來。
private actor SleepLog {
    private(set) var seconds: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        seconds.append(value)
    }
}

private enum NameSpot {
    static let taipei = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
}
