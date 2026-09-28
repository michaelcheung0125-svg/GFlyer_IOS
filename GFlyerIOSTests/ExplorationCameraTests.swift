import MapKit
import XCTest
@testable import GFlyerIOS

/// 探索預覽的鏡頭:沒有在探索時,起點一改變就縮放到整條預覽(GFlyer-Suite
/// docs/features/serpentine-exploration.md §3.5)。這裡驗縮放到哪裡(`ExplorationCamera`)和什麼時候縮放
/// (`ExplorationFitTrigger`、`ExplorationRun.origin`);`MainView` 何時呼叫它們、鏡頭實際怎麼動仍要上機看。
final class ExplorationCameraTests: XCTestCase {
    private let start = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
    private let mapSize = CGSize(width: 390, height: 760)

    /// 範圍裡一個 map point 在地圖上的位置(pt)。
    private func screenPoint(_ mapPoint: MKMapPoint, in rect: MKMapRect) -> CGPoint {
        let scale = rect.width / Double(mapSize.width)
        return CGPoint(x: (mapPoint.x - rect.minX) / scale, y: (mapPoint.y - rect.minY) / scale)
    }

    /// Y = 5,000 的整條預覽(約 10 公里高)落在搜尋列與控制面板之間,四周留 24 pt,而且貼齊其中一個方向。
    func testWholePreviewFitsBetweenTheSearchBarAndTheControlPanel() throws {
        let preview = SerpentinePath.preview(
            current: start,
            state: SerpentineState(),
            verticalLengthMetres: 5_000,
            direction: .east
        )
        let rect = try XCTUnwrap(
            ExplorationCamera.visibleRect(for: preview, mapSize: mapSize, coveredTop: 60, coveredBottom: 380)
        )
        XCTAssertEqual(rect.width / rect.height, Double(mapSize.width / mapSize.height), accuracy: 1e-9, "和地圖同樣長寬比")

        let bounds = try XCTUnwrap(ExplorationCamera.boundingRect(of: preview))
        let topLeft = screenPoint(MKMapPoint(x: bounds.minX, y: bounds.minY), in: rect)
        let bottomRight = screenPoint(MKMapPoint(x: bounds.maxX, y: bounds.maxY), in: rect)
        let padding = ExplorationCamera.padding
        let tolerance: CGFloat = 1e-6
        XCTAssertGreaterThanOrEqual(topLeft.x, padding - tolerance)
        XCTAssertLessThanOrEqual(bottomRight.x, mapSize.width - padding + tolerance)
        XCTAssertGreaterThanOrEqual(topLeft.y, 60 + padding - tolerance, "不被搜尋列蓋住")
        XCTAssertLessThanOrEqual(bottomRight.y, mapSize.height - 380 - padding + tolerance, "不被控制面板蓋住")
        // 預覽很高,所以上下剛好貼齊沒被蓋住的那一塊,中心在那一塊的正中間
        XCTAssertEqual(topLeft.y, 60 + padding, accuracy: 1e-6)
        XCTAssertEqual(bottomRight.y, mapSize.height - 380 - padding, accuracy: 1e-6)
        XCTAssertEqual((topLeft.x + bottomRight.x) / 2, mapSize.width / 2, accuracy: 1e-6)
    }

    /// 控制面板幾乎蓋滿地圖時,改用整張地圖,不要把預覽縮成一個點。
    func testFallsBackToTheWholeMapWhenTheVisibleAreaIsTooShort() throws {
        let preview = SerpentinePath.preview(
            current: start,
            state: SerpentineState(),
            verticalLengthMetres: 1_000,
            direction: .west
        )
        let rect = try XCTUnwrap(
            ExplorationCamera.visibleRect(for: preview, mapSize: mapSize, coveredTop: 60, coveredBottom: 650)
        )
        let bounds = try XCTUnwrap(ExplorationCamera.boundingRect(of: preview))
        let topLeft = screenPoint(MKMapPoint(x: bounds.minX, y: bounds.minY), in: rect)
        let bottomRight = screenPoint(MKMapPoint(x: bounds.maxX, y: bounds.maxY), in: rect)
        // Y = 1,000 的預覽比較寬(2.65 × 2 公里),左右貼齊邊距,上下在整張地圖的正中間
        XCTAssertEqual(topLeft.x, ExplorationCamera.padding, accuracy: 1e-6)
        XCTAssertEqual(bottomRight.x, mapSize.width - ExplorationCamera.padding, accuracy: 1e-6)
        XCTAssertEqual((topLeft.y + bottomRight.y) / 2, mapSize.height / 2, accuracy: 1e-6)
    }

    /// 預覽跨過 180 度經線時,外框只有預覽本身那麼寬,不會繞地球一圈。
    func testBoundingRectAcrossTheAntimeridianStaysNarrow() throws {
        let west = GeoCoordinate(latitude: -16.8, longitude: 179.99)
        let east = GeoCoordinate(latitude: -16.8, longitude: -179.99)
        let bounds = try XCTUnwrap(ExplorationCamera.boundingRect(of: [west, east]))
        let expected = MKMapPoint(east.clLocationCoordinate).x + MKMapSize.world.width - MKMapPoint(west.clLocationCoordinate).x
        XCTAssertEqual(bounds.width, expected, accuracy: 1e-3)
        XCTAssertLessThan(bounds.width, MKMapSize.world.width / 1_000)
    }

    func testNothingToFitWithoutPointsOrMapSize() {
        XCTAssertNil(ExplorationCamera.visibleRect(for: [], mapSize: mapSize, coveredTop: 0, coveredBottom: 0))
        XCTAssertNil(ExplorationCamera.visibleRect(for: [start], mapSize: .zero, coveredTop: 0, coveredBottom: 0))
        // 只有一個點也有個範圍,不會放大到無限
        let single = ExplorationCamera.visibleRect(for: [start], mapSize: mapSize, coveredTop: 0, coveredBottom: 0)
        XCTAssertEqual(single?.width ?? 0, Double(mapSize.width) * ExplorationCamera.minimumMapPointsPerPoint, accuracy: 1e-9)
    }

    // MARK: - 什麼時候縮放

    private let stopped = GeoCoordinate(latitude: 22.3562, longitude: 114.2105)
    private let tapped = GeoCoordinate(latitude: 22.2855, longitude: 114.1577)

    private func status(activeAt coordinate: GeoCoordinate?) -> SimulationStatus {
        var status = SimulationStatus()
        status.isActive = coordinate != nil
        status.coordinate = coordinate
        return status
    }

    /// `MainView.explorationFitStart` 的算法:探索模式裡的預覽起點,探索中是 nil。
    private func fitStart(
        simulatingAt coordinate: GeoCoordinate?,
        selected: GeoCoordinate,
        isExploring: Bool = false,
        isStopping: Bool = false
    ) -> GeoCoordinate? {
        ExplorationFitTrigger.fitStart(
            isExploreMode: true,
            isExploring: isExploring,
            start: ExplorationRun.origin(status: status(activeAt: coordinate), isStopping: isStopping, selected: selected)
        )
    }

    /// 探索模式、沒有在探索(含暫停)時才有起點。Y 與方向不是參數,所以只改它們不會重新縮放。
    func testFitStartOnlyInExploreModeWhileNotExploring() {
        XCTAssertNil(ExplorationFitTrigger.fitStart(isExploreMode: false, isExploring: false, start: start))
        XCTAssertNil(ExplorationFitTrigger.fitStart(isExploreMode: true, isExploring: true, start: start))
        XCTAssertEqual(ExplorationFitTrigger.fitStart(isExploreMode: true, isExploring: false, start: start), start)
    }

    /// 起點:模擬中是模擬座標,否則是選取點(Android `mockStatus.coordinate ?: selected`)。按了停止、還在等清除時
    /// 已經是選取點:Android 停止時一次清掉狀態,iOS 的 `status` 要等 `clearLocation` 回來才重設。
    func testOriginIsTheSelectedPointOnceAStopBegins() {
        XCTAssertEqual(ExplorationRun.origin(status: status(activeAt: nil), isStopping: false, selected: start), start)
        XCTAssertEqual(ExplorationRun.origin(status: status(activeAt: stopped), isStopping: false, selected: start), stopped)
        XCTAssertEqual(ExplorationRun.origin(status: status(activeAt: stopped), isStopping: true, selected: start), start)
        XCTAssertEqual(ExplorationRun.origin(status: status(activeAt: nil), isStopping: true, selected: start), start)
        var noCoordinate = SimulationStatus()
        noCoordinate.isActive = true
        XCTAssertEqual(ExplorationRun.origin(status: noCoordinate, isStopping: false, selected: start), start)
    }

    /// 停止、自動停止與完整清除不動鏡頭:探索前縮放過選取點,停止後到清除完成之前起點已經是選取點,清除後也是。
    /// 以前停止後、清除前的起點是停下的位置,鏡頭先縮放過去,清除後再縮放回來。
    func testStoppingAnExplorationDoesNotMoveTheCamera() {
        var trigger = ExplorationFitTrigger()
        XCTAssertEqual(trigger.startToFit(fitStart(simulatingAt: nil, selected: start), isExploreMode: true), start)
        trigger.didFit(start, now: 0)
        XCTAssertNil(trigger.startToFit(fitStart(simulatingAt: start, selected: start, isExploring: true), isExploreMode: true))
        XCTAssertNil(trigger.startToFit(fitStart(simulatingAt: stopped, selected: start, isStopping: true), isExploreMode: true))
        XCTAssertNil(trigger.startToFit(fitStart(simulatingAt: nil, selected: start), isExploreMode: true))
        XCTAssertEqual(fitStart(simulatingAt: stopped, selected: start), stopped, "沒有停止中這一段時,起點會先跳到停下的位置")
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: start, now: 0.1), "停止後面板收起按鈕也不縮放")
    }

    /// 探索中點過地圖、或這一輪是恢復的:停止時直接縮放到清除之後的起點(選取點),只縮放一次,和 Android 相同。
    func testStopAfterTheSelectionChangedFitsOnceToTheSelectedPoint() {
        var trigger = ExplorationFitTrigger()
        _ = trigger.startToFit(start, isExploreMode: true)
        trigger.didFit(start, now: 0)
        XCTAssertNil(trigger.startToFit(fitStart(simulatingAt: stopped, selected: tapped, isExploring: true), isExploreMode: true))
        XCTAssertEqual(
            trigger.startToFit(fitStart(simulatingAt: stopped, selected: tapped, isStopping: true), isExploreMode: true),
            tapped
        )
        trigger.didFit(tapped, now: 30)
        XCTAssertNil(trigger.startToFit(fitStart(simulatingAt: nil, selected: tapped), isExploreMode: true))

        // 恢復中斷的探索:切進探索時已經在探索,之前沒有縮放過
        var resumed = ExplorationFitTrigger()
        XCTAssertNil(resumed.startToFit(fitStart(simulatingAt: stopped, selected: tapped, isExploring: true), isExploreMode: true))
        XCTAssertEqual(
            resumed.startToFit(fitStart(simulatingAt: stopped, selected: tapped, isStopping: true), isExploreMode: true),
            tapped
        )
        resumed.didFit(tapped, now: 0)
        XCTAssertNil(resumed.startToFit(fitStart(simulatingAt: nil, selected: tapped), isExploreMode: true))
    }

    /// 每個新起點縮放一次:起點沒變(只改 Y 或方向)不縮放,在探索模式點地圖換了起點要縮放,離開探索模式後
    /// 再切進來也要縮放。地圖大小還不知道、沒縮放成功的起點下次再試。
    func testFitsOncePerNewStartAndAgainAfterReenteringExplore() {
        var trigger = ExplorationFitTrigger()
        XCTAssertEqual(trigger.startToFit(start, isExploreMode: true), start)
        XCTAssertEqual(trigger.startToFit(start, isExploreMode: true), start, "沒有 didFit 就還沒縮放過")
        trigger.didFit(start, now: 0)
        XCTAssertNil(trigger.startToFit(start, isExploreMode: true))
        XCTAssertEqual(trigger.startToFit(tapped, isExploreMode: true), tapped)
        trigger.didFit(tapped, now: 5)

        XCTAssertNil(trigger.startToFit(nil, isExploreMode: false))
        XCTAssertNil(trigger.lastFittedStart)
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: tapped, now: 5.1))
        XCTAssertEqual(trigger.startToFit(tapped, isExploreMode: true), tapped, "每次切進來都縮放一次")
    }

    /// 切進探索時控制面板換成探索的設定,新的高度比縮放晚才量到:剛縮放過的起點在 `panelSettleSeconds` 內
    /// 面板一變就再縮放一次(面板可能分幾次排好);起點換了、開始探索、離開探索或時間過了就不再補。
    func testPanelChangeRightAfterAFitRefitsTheSameStart() {
        var trigger = ExplorationFitTrigger()
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: start, now: 0), "還沒縮放過")
        trigger.didFit(start, now: 10)
        XCTAssertTrue(trigger.shouldRefitForPanel(currentStart: start, now: 10.02))
        XCTAssertTrue(trigger.shouldRefitForPanel(currentStart: start, now: 10.5))
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: start, now: 10 + ExplorationFitTrigger.panelSettleSeconds))
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: tapped, now: 10.02), "起點已經換了")
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: nil, now: 10.02), "開始探索或離開探索")

        XCTAssertNil(trigger.startToFit(nil, isExploreMode: true))
        XCTAssertFalse(trigger.shouldRefitForPanel(currentStart: start, now: 10.02), "探索中不補縮放,停止後也不補")
        XCTAssertEqual(trigger.lastFittedStart, start, "探索中留著上一次的起點")
    }
}
