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

/// 什麼時候把鏡頭縮放到整條探索預覽(GFlyer-Suite docs/features/serpentine-exploration.md §3.5,和 Android
/// `MainScreen.kt` 的 `lastExplorationPreviewCenter` 相同)。`MainView` 在預覽起點與控制面板的框改變時問它;
/// 這裡只有規則,縮放到哪裡由 `ExplorationCamera` 算。
struct ExplorationFitTrigger: Equatable {
    /// 縮放之後這段時間內控制面板的框又變了,就用新的面板高度再縮放一次(秒)。切進探索時面板在同一次更新裡
    /// 換成探索的設定(高了 150〜200 pt),新的框要等版面排好才量得到,比預覽起點的 `onChange` 晚;沒有這一次,
    /// 縮放用的是舊模式的面板高度,預覽的下半段被面板蓋住。過了這段時間面板再變(例如停止後按鈕收起)不縮放。
    static let panelSettleSeconds: TimeInterval = 1

    /// 上一次縮放時的起點。離開探索模式時清掉,所以每次切進來都縮放一次。
    private(set) var lastFittedStart: GeoCoordinate?
    /// 剛縮放過的起點,`panelRefitDeadline`(`ProcessInfo.systemUptime`)之前面板一變就再縮放一次。
    private(set) var panelRefitStart: GeoCoordinate?
    private(set) var panelRefitDeadline: TimeInterval = 0

    /// 鏡頭要看的預覽起點:探索模式、沒有在探索(含暫停)時是 `start`,其他時候 nil。Y 與方向不在裡面,
    /// 所以只改它們不會重新縮放。
    static func fitStart(isExploreMode: Bool, isExploring: Bool, start: GeoCoordinate) -> GeoCoordinate? {
        guard isExploreMode, !isExploring else { return nil }
        return start
    }

    /// `fitStart` 改變時呼叫。回傳要縮放到的起點;nil 就不動鏡頭。
    mutating func startToFit(_ start: GeoCoordinate?, isExploreMode: Bool) -> GeoCoordinate? {
        guard isExploreMode else {
            self = ExplorationFitTrigger()
            return nil
        }
        guard let start else {
            // 探索中:不縮放,也不再為面板補縮放;上一次的起點留著,停止後起點沒變就不動鏡頭
            panelRefitStart = nil
            return nil
        }
        return start == lastFittedStart ? nil : start
    }

    /// 真的縮放了(地圖的大小已經量到)才呼叫。
    mutating func didFit(_ start: GeoCoordinate, now: TimeInterval) {
        lastFittedStart = start
        panelRefitStart = start
        panelRefitDeadline = now + Self.panelSettleSeconds
    }

    /// 控制面板的框改變時呼叫:剛縮放過、起點沒變,就要用新的面板高度再縮放一次。
    func shouldRefitForPanel(currentStart: GeoCoordinate?, now: TimeInterval) -> Bool {
        guard let panelRefitStart, panelRefitStart == currentStart else { return false }
        return now < panelRefitDeadline
    }
}
