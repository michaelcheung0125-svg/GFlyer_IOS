import MapKit

/// 探索預覽的鏡頭:沒有在探索時,預覽的起點一改變就縮放到剛好容納整條預覽(GFlyer-Suite
/// docs/features/serpentine-exploration.md §3.5;Android 是 `CameraUpdateFactory.newLatLngBounds(bounds, 72)`)。
///
/// iOS 的搜尋列與控制面板疊在地圖上面,所以要把預覽放進「地圖沒被蓋住的那一塊」,不是整張地圖:
/// 算出一個和地圖同樣長寬比的範圍,讓預覽的外框落在那一塊的正中間、四周留 `padding`。
enum ExplorationCamera {
    /// 預覽外框四周留的邊距(pt),相當於 Android 的 72 px。
    static let padding: CGFloat = 24
    /// 沒被蓋住的那一塊比這個還矮時(橫向、字很大、面板幾乎蓋滿)就不管上下的遮擋,改用整張地圖。
    static let minimumVisibleHeight: CGFloat = 120
    /// 每 pt 至少幾個 map point(赤道上約 0.15 公尺),預覽很短時不要放大到街景以下。
    static let minimumMapPointsPerPoint = 1.0

    /// - Parameters:
    ///   - mapSize: 地圖的大小(pt)。
    ///   - coveredTop: 地圖上緣被蓋住的高度(搜尋列)。
    ///   - coveredBottom: 地圖下緣被蓋住的高度(控制面板)。
    /// - Returns: 給 `MapCameraPosition.rect` 的範圍;沒有點或還不知道地圖大小時是 nil。
    static func visibleRect(
        for points: [GeoCoordinate],
        mapSize: CGSize,
        coveredTop: CGFloat,
        coveredBottom: CGFloat,
        padding: CGFloat = ExplorationCamera.padding
    ) -> MKMapRect? {
        guard mapSize.width > 0, mapSize.height > 0, let bounds = boundingRect(of: points) else { return nil }
        var top = max(coveredTop, 0)
        var bottom = max(coveredBottom, 0)
        if mapSize.height - top - bottom - 2 * padding < minimumVisibleHeight {
            top = 0
            bottom = 0
        }
        let visibleWidth = Double(max(mapSize.width - 2 * padding, 1))
        let visibleHeight = Double(max(mapSize.height - top - bottom - 2 * padding, 1))
        let scale = max(bounds.width / visibleWidth, bounds.height / visibleHeight, minimumMapPointsPerPoint)
        let width = Double(mapSize.width) * scale
        let height = Double(mapSize.height) * scale
        // 預覽外框的中心放在沒被蓋住那一塊的中心
        let visibleCentreY = Double(top + padding) + visibleHeight / 2
        return MKMapRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - visibleCentreY * scale,
            width: width,
            height: height
        )
    }

    /// 所有點的外框(map point)。點散在 180 度經線兩邊時(外框比半個世界還寬),把西半球那一側的點
    /// 往右移一個世界寬,外框才不會繞地球一圈。
    static func boundingRect(of points: [GeoCoordinate]) -> MKMapRect? {
        let mapPoints = points.map { MKMapPoint($0.clLocationCoordinate) }
        let worldWidth = MKMapSize.world.width
        var xs = mapPoints.map(\.x)
        let ys = mapPoints.map(\.y)
        if let minX = xs.min(), let maxX = xs.max(), maxX - minX > worldWidth / 2 {
            xs = xs.map { $0 < worldWidth / 2 ? $0 + worldWidth : $0 }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
