import MapKit
import XCTest
@testable import GFlyerIOS

/// 探索預覽的鏡頭:沒有在探索時,起點一改變就縮放到整條預覽(GFlyer-Suite
/// docs/features/serpentine-exploration.md §3.5)。什麼時候縮放由 `MainView` 決定,要上機看;
/// 這裡驗縮放到哪裡。
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
}
