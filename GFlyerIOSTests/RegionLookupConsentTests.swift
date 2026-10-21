import XCTest
@testable import GFlyerIOS

/// 自動反查收藏的「國家 · 城市」先取得同意(GFlyer-Suite docs/features/region-labels.md 3.10,docs/APP_STORE_PLAN.md
/// 第 17 項的 U7)。規則和文字照 Android `RegionLookupConsentTest`;要不要問由版本決定,這裏直接把 `asksFirst`
/// 傳給 `RegionLookup`,兩個版本跑的是同一份。公開版實際的服務名稱在 `Public/AppleGeocoderRegionLabelTests`。
@MainActor
final class RegionLookupConsentTests: XCTestCase {

    // MARK: - 規則(Android RegionLookupConsentTest)

    func testEditionsThatDoNotAskAlwaysAllowLookups() {
        for consent in [RegionLookupConsent.unasked, .allowed, .declined] {
            XCTAssertTrue(RegionLookupConsentRules.lookupsAllowed(asksFirst: false, consent: consent))
            XCTAssertFalse(RegionLookupConsentRules.asksOnLookup(asksFirst: false, consent: consent, coordinateCount: 3))
            XCTAssertFalse(RegionLookupConsentRules.asksOnStar(asksFirst: false, consent: consent))
        }
    }

    func testEditionsThatAskOnlyLookUpAfterTheUserAllowedIt() {
        XCTAssertFalse(RegionLookupConsentRules.lookupsAllowed(asksFirst: true, consent: .unasked))
        XCTAssertTrue(RegionLookupConsentRules.lookupsAllowed(asksFirst: true, consent: .allowed))
        XCTAssertFalse(RegionLookupConsentRules.lookupsAllowed(asksFirst: true, consent: .declined))
    }

    func testLookupsAskOnlyWhenSomethingNeedsLookingUpAndNobodyAnsweredYet() {
        XCTAssertTrue(RegionLookupConsentRules.asksOnLookup(asksFirst: true, consent: .unasked, coordinateCount: 1))
        XCTAssertFalse(RegionLookupConsentRules.asksOnLookup(asksFirst: true, consent: .unasked, coordinateCount: 0))
        XCTAssertFalse(RegionLookupConsentRules.asksOnLookup(asksFirst: true, consent: .allowed, coordinateCount: 1))
        XCTAssertFalse(RegionLookupConsentRules.asksOnLookup(asksFirst: true, consent: .declined, coordinateCount: 1))
    }

    func testStarAsksUntilTheUserAnsweredOnce() {
        XCTAssertTrue(RegionLookupConsentRules.asksOnStar(asksFirst: true, consent: .unasked))
        XCTAssertFalse(RegionLookupConsentRules.asksOnStar(asksFirst: true, consent: .allowed))
        XCTAssertFalse(RegionLookupConsentRules.asksOnStar(asksFirst: true, consent: .declined))
    }

    // MARK: - 文字

    /// 和 Android 公開版一字不差:用 Android 的服務名稱組出來,要等於 Android `PlatformGeocoderTextTest` 釘住的字。
    func testTextsMatchAndroid() {
        XCTAssertEqual(RegionLookupConsentText.title, "顯示收藏的國家與城市？")
        XCTAssertEqual(RegionLookupConsentText.allowButton, "允許")
        XCTAssertEqual(RegionLookupConsentText.declineButton, "不用")
        XCTAssertEqual(RegionLookupConsentText.settingTitle, "顯示收藏的國家與城市")
        XCTAssertEqual(RegionLookupConsentText.settingsGroupTitle, "提示與地名")
        XCTAssertEqual(RegionLookupConsentText.paragraphs(service: "手機系統的地點服務（大多數手機由 Google 提供）"), [
            "收藏清單可以在每個收藏旁邊顯示所在的國家與城市，例如「臺灣 · 臺北市」。要查出來，收藏位置與收藏路線第一點的座標會送往手機系統的地點服務（大多數手機由 Google 提供）；之後按 ☆ 收藏新的地點時，那一點的座標也會立刻送出，用來預先填入名稱。",
            "查到的結果只存在本機，不會放進備份檔。不允許也可以照常收藏，只是不顯示國家與城市。之後可以在設定的「提示與地名」更改。",
        ])
        XCTAssertEqual(RegionLookupConsentText.settingDescription(service: "手機系統的地點服務"), "收藏的座標會送往手機系統的地點服務查詢")
        // 英文開頭的名稱前面空一格
        XCTAssertEqual(RegionLookupConsentText.settingDescription(service: "Example 反查"), "收藏的座標會送往 Example 反查查詢")
        XCTAssertTrue(RegionLookupConsentText.paragraphs(service: "Example 服務")[0].contains("座標會送往 Example 服務；"))
    }

    /// 沒有允許時命名 sheet 不等反查,也不顯示「正在查詢地名…」。
    func testTheNameFieldDoesNotWaitWhenLookupsAreNotAllowed() {
        XCTAssertTrue(FavoriteNameField(suggestedName: "").isLookingUp)
        XCTAssertFalse(FavoriteNameField(suggestedName: "", looksUpName: false).isLookingUp)
        let prompt = FavoriteAddPrompt.forTarget(
            Spot.taipei,
            favorites: [],
            regionLabels: ["25.03,121.56": "臺灣 · 臺北市"],
            looksUpName: false
        )
        XCTAssertEqual(prompt, .askName(FavoriteNameRequest(coordinate: Spot.taipei, suggestedName: "", looksUpName: false)))
    }

    // MARK: - RegionLookup

    /// 還沒允許時一般請求和 ☆ 的緊急請求都不送;答案存在這部手機上,下次啟動照樣記得。
    func testNothingIsSentUntilAllowedAndTheAnswerIsRemembered() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let service = ConsentTestRegionLabelSource()
        service.labels[Spot.key(Spot.taipei)] = "臺灣 · 臺北市"
        let lookup = makeLookup(defaults, service)
        XCTAssertEqual(lookup.consent, .unasked)
        XCTAssertFalse(lookup.lookupsAllowed)

        lookup.request([Spot.taipei, Spot.osaka])
        let urgent = await lookup.lookUpUrgently(Spot.seoul)
        await lookup.waitUntilIdle()
        XCTAssertNil(urgent)
        XCTAssertEqual(service.events, [], "還沒允許,一個都不送")
        XCTAssertEqual(lookup.pendingCoordinates, [])

        lookup.setConsent(.allowed)
        lookup.request([Spot.taipei])
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, ["GET 25.0339,121.5645", "sleep 1.1"])
        XCTAssertEqual(makeLookup(defaults, service).consent, .allowed, "下次啟動照樣記得")

        lookup.setConsent(.declined)
        XCTAssertEqual(makeLookup(defaults, service).consent, .declined)
        XCTAssertEqual(defaults.string(forKey: RegionLookup.consentStorageKey), "declined")
    }

    /// 收回同意:還在排隊的拿掉、等它們的 ☆ 拿到 nil;正在查的那一筆不撤回,查到的照樣進快取。
    /// 再允許時拿掉的可以重新排。
    func testWithdrawingConsentDropsWhatIsStillQueued() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let service = ConsentTestRegionLabelSource()
        service.labels[Spot.key(Spot.taipei)] = "臺灣 · 臺北市"
        service.labels[Spot.key(Spot.osaka)] = "日本 · 大阪市"
        let lookup = makeLookup(defaults, service)
        lookup.setConsent(.allowed)

        service.holdsRequests = true
        lookup.request([Spot.taipei, Spot.osaka, Spot.seoul])
        await waitUntil("台北正在查") { service.isHoldingARequest }
        let waiting = Task { await lookup.lookUpUrgently(Spot.osaka) }
        await waitUntil("大阪搬到最前面、有人在等") { lookup.waiterCount(for: Spot.osaka) == 1 }
        XCTAssertEqual(lookup.pendingCoordinates, [Spot.osaka, Spot.seoul])

        lookup.setConsent(.declined)
        XCTAssertEqual(lookup.pendingCoordinates, [], "還在排隊的一併拿掉")
        let urgentResult = await waiting.value
        XCTAssertNil(urgentResult, "等它的 ☆ 拿到查不到")

        service.holdsRequests = false
        service.finishHeldRequest()
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, ["GET 25.0339,121.5645", "sleep 1.1"], "正在查的那一筆不撤回,其他的沒有送")
        XCTAssertEqual(lookup.labels, ["25.03,121.56": "臺灣 · 臺北市"], "查到的照樣進快取")

        lookup.setConsent(.allowed)
        lookup.request([Spot.taipei, Spot.osaka, Spot.seoul])
        await lookup.waitUntilIdle()
        XCTAssertEqual(Array(service.events.dropFirst(2)), [
            "GET 34.6937,135.5023", "sleep 1.1",
            "GET 37.5665,126.978", "sleep 1.1",
        ], "拿掉的不算排過隊,再允許時重新排")
    }

    // MARK: - SimulationController

    /// 開 App 時已有收藏而還沒問過:先問,不送、也不顯示本機快取裏的地名;按「允許」才顯示並把沒查過的排進去。
    func testLaunchWithFavoritesAsksFirstAndAllowingLooksThemUp() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let store = LocalDataStore(defaults: defaults)
        store.addFavorite(name: "台北", coordinate: Spot.taipei)
        store.addFavorite(name: "大阪", coordinate: Spot.osaka)
        defaults.set(try JSONEncoder().encode(["34.69,135.50": "日本 · 大阪市"]), forKey: RegionLookup.storageKey)
        let service = ConsentTestRegionLabelSource()
        service.labels[Spot.key(Spot.taipei)] = "臺灣 · 臺北市"
        let lookup = makeLookup(defaults, service)
        let controller = makeController(defaults, store: store, lookup: lookup)

        XCTAssertEqual(controller.regionConsentPrompt, .lookup)
        XCTAssertEqual(controller.regionLabels, [:], "快取裏有也不顯示")
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, [])
        // 已經有一個在等答案時不換掉它
        controller.askRegionConsent(.settings)
        XCTAssertEqual(controller.regionConsentPrompt, .lookup)

        controller.answerRegionConsent(allowed: true)
        XCTAssertNil(controller.regionConsentPrompt)
        XCTAssertEqual(controller.regionLookupConsent, .allowed)
        XCTAssertEqual(controller.regionLabels, ["34.69,135.50": "日本 · 大阪市"])
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, ["GET 25.0339,121.5645", "sleep 1.1"], "快取裏沒有的才送")
        XCTAssertEqual(controller.regionLabels["25.03,121.56"], "臺灣 · 臺北市")
        XCTAssertFalse(controller.asksRegionConsentOnStar)
    }

    /// 新裝、還沒有收藏:開 App 不問。之後第一次有收藏才問。
    func testNoFavoritesNoQuestionUntilThereIsSomethingToLookUp() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let service = ConsentTestRegionLabelSource()
        let lookup = makeLookup(defaults, service)
        let controller = makeController(defaults, store: LocalDataStore(defaults: defaults), lookup: lookup)
        XCTAssertNil(controller.regionConsentPrompt)
        XCTAssertTrue(controller.regionLookupAsksFirst)
        XCTAssertTrue(controller.asksRegionConsentOnStar, "第一次按 ☆ 先問")

        controller.select(Spot.taipei)
        controller.addFavorite(name: "台北")
        XCTAssertEqual(controller.regionConsentPrompt, .lookup)
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, [])
    }

    /// 按「不用」:不送、不顯示、☆ 不預填也不插隊反查;之後收藏變動也不再問。
    func testDecliningKeepsEverythingOnThePhone() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let store = LocalDataStore(defaults: defaults)
        store.addFavorite(name: "台北", coordinate: Spot.taipei)
        defaults.set(try JSONEncoder().encode(["25.03,121.56": "臺灣 · 臺北市"]), forKey: RegionLookup.storageKey)
        let service = ConsentTestRegionLabelSource()
        let lookup = makeLookup(defaults, service)
        let controller = makeController(defaults, store: store, lookup: lookup)

        controller.answerRegionConsent(allowed: false)
        XCTAssertEqual(controller.regionLookupConsent, .declined)
        XCTAssertNil(controller.regionConsentPrompt)
        XCTAssertEqual(controller.regionLabels, [:])
        XCTAssertFalse(controller.asksRegionConsentOnStar, "答過了,按 ☆ 不再問")

        controller.select(Spot.taipeiSameCell)
        XCTAssertEqual(
            controller.favoritePrompt(),
            .askName(FavoriteNameRequest(coordinate: Spot.taipeiSameCell, suggestedName: "", looksUpName: false)),
            "快取裏有也不預填"
        )
        let label = await controller.favoriteNameLabel(for: Spot.osaka)
        XCTAssertNil(label)
        controller.select(Spot.osaka)
        controller.addFavorite(name: "大阪")
        XCTAssertNil(controller.regionConsentPrompt, "收藏變動不再問")
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, [], "一個都不送")
    }

    /// 設定的開關:打開先問,按「允許」才打開;關掉馬上變成「不用」、不另外問。
    func testTheSettingsSwitchAsksBeforeTurningOn() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let store = LocalDataStore(defaults: defaults)
        store.addFavorite(name: "台北", coordinate: Spot.taipei)
        defaults.set(try JSONEncoder().encode(["25.03,121.56": "臺灣 · 臺北市"]), forKey: RegionLookup.storageKey)
        let service = ConsentTestRegionLabelSource()
        let lookup = makeLookup(defaults, service)
        let controller = makeController(defaults, store: store, lookup: lookup)
        controller.answerRegionConsent(allowed: false)

        controller.setRegionLabelsEnabled(true)
        XCTAssertEqual(controller.regionConsentPrompt, .settings)
        XCTAssertEqual(controller.regionLookupConsent, .declined, "還沒按「允許」,開關還是關的")
        controller.answerRegionConsent(allowed: false)
        XCTAssertEqual(controller.regionLookupConsent, .declined)

        controller.setRegionLabelsEnabled(true)
        controller.answerRegionConsent(allowed: true)
        XCTAssertEqual(controller.regionLookupConsent, .allowed)
        XCTAssertEqual(controller.regionLabels, ["25.03,121.56": "臺灣 · 臺北市"])

        controller.setRegionLabelsEnabled(false)
        XCTAssertNil(controller.regionConsentPrompt, "關掉不另外問")
        XCTAssertEqual(controller.regionLookupConsent, .declined)
        XCTAssertEqual(controller.regionLabels, [:], "清單上的地名馬上消失")

        let backup = try XCTUnwrap(controller.exportBackupData())
        let text = try XCTUnwrap(String(data: backup, encoding: .utf8))
        XCTAssertFalse(text.contains("consent"), "答案不放進備份檔")
    }

    /// 不用問的版本(親友版):有收藏也不問,按 ☆ 不問,設定也叫不出說明。
    func testEditionsThatDoNotAskNeverShowTheQuestion() async throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let store = LocalDataStore(defaults: defaults)
        store.addFavorite(name: "台北", coordinate: Spot.taipei)
        let service = ConsentTestRegionLabelSource()
        let lookup = RegionLookup(defaults: defaults, source: service, clock: service, asksFirst: false)
        let controller = makeController(defaults, store: store, lookup: lookup)

        XCTAssertNil(controller.regionConsentPrompt)
        XCTAssertFalse(controller.regionLookupAsksFirst)
        XCTAssertFalse(controller.asksRegionConsentOnStar)
        controller.askRegionConsent(.settings)
        XCTAssertNil(controller.regionConsentPrompt)
        await lookup.waitUntilIdle()
        XCTAssertEqual(service.events, ["GET 25.0339,121.5645", "sleep 1.1"], "照舊開 App 就查")
    }

    // MARK: - 輔助

    private func makeDefaults() throws -> (UserDefaults, () -> Void) {
        let suiteName = "gflyer.region-consent-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    /// 要先取得同意的反查(公開版的行為)。
    private func makeLookup(_ defaults: UserDefaults, _ service: ConsentTestRegionLabelSource) -> RegionLookup {
        RegionLookup(defaults: defaults, source: service, clock: service, asksFirst: true)
    }

    private func makeController(_ defaults: UserDefaults, store: LocalDataStore, lookup: RegionLookup) -> SimulationController {
        SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: store,
            sessionStore: ActiveSessionStore(defaults: defaults),
            regionLookup: lookup
        )
    }

    /// 佇列的工作與等待者都在主執行緒上排隊執行,所以照時間等,不數 `Task.yield()`。
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

/// 假的反查服務,同時當時鐘,和 `RegionLookup` 一樣在主執行緒上。依序記下請求(「GET 緯度,經度」)與等待
/// (「sleep 秒數」),依座標回應;沒有標籤的當作查不到。`holdsRequests` 打開時請求停在半路,等 `finishHeldRequest()`。
@MainActor
private final class ConsentTestRegionLabelSource: RegionLabelSource, RegionLookupClock {
    private(set) var events: [String] = []
    var labels: [String: String] = [:]
    var holdsRequests = false
    private var held: [CheckedContinuation<Void, Never>] = []

    var isHoldingARequest: Bool { !held.isEmpty }

    func finishHeldRequest() {
        guard !held.isEmpty else { return }
        held.removeFirst().resume()
    }

    func label(for coordinate: GeoCoordinate) async -> String? {
        let key = Spot.key(coordinate)
        events.append("GET \(key)")
        if holdsRequests {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                held.append(continuation)
            }
        }
        return labels[key]
    }

    func sleep(seconds: TimeInterval) async {
        events.append("sleep \(seconds)")
    }
}

private enum Spot {
    static let taipei = GeoCoordinate(latitude: 25.0339, longitude: 121.5645)
    /// 和 `taipei` 同一個快取格(25.03,121.56)。
    static let taipeiSameCell = GeoCoordinate(latitude: 25.0301, longitude: 121.5601)
    static let osaka = GeoCoordinate(latitude: 34.6937, longitude: 135.5023)
    static let seoul = GeoCoordinate(latitude: 37.5665, longitude: 126.978)

    /// 假的反查服務記座標的寫法,和 Nominatim 送出的 lat / lon 相同。
    static func key(_ coordinate: GeoCoordinate) -> String {
        "\(String(coordinate.latitude)),\(String(coordinate.longitude))"
    }
}
