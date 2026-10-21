/// 留言板的座標和路線，經共用的「別處來的座標、路線」方法進出模擬。
extension SimulationController {
    @discardableResult
    func previewBoardCoordinate(_ coordinate: GeoCoordinate, startImmediately: Bool) -> Bool {
        previewExternalCoordinate(coordinate, startImmediately: startImmediately, sourceLabel: "留言板")
    }

    @discardableResult
    func previewBoardRoute(_ route: SharedBoardRoute, startImmediately: Bool) -> Bool {
        previewExternalRoute(points: route.points, loop: route.loop, startImmediately: startImmediately, sourceLabel: "留言板")
    }

    func saveBoardCoordinate(_ coordinate: GeoCoordinate, name: String?) {
        saveExternalCoordinate(coordinate, name: name, fallbackName: "留言板位置 \(coordinate.display)")
    }

    func saveBoardRoute(_ route: SharedBoardRoute, authorName: String) {
        saveExternalRoute(name: "\(route.name) (\(authorName))", points: route.points, loop: route.loop)
    }
}
