import SwiftUI

/// 從地圖工具列打開的座標圖鑑。
struct CoordinateLibrarySheet: ViewModifier {
    @ObservedObject var edition: EditionModel
    // 只交給圖鑑在按鈕動作中呼叫，不觀察：模擬狀態每 250ms 更新，觀察會讓整個清單跟著重繪
    let simulation: SimulationController

    func body(content: Content) -> some View {
        content.sheet(isPresented: $edition.showsCoordinateLibrary) {
            CoordinateLibraryView(library: edition.coordinateLibrary, simulation: simulation)
        }
    }
}

extension MapToolItem {
    /// 地圖工具列的座標圖鑑。有還沒看過的新座標時右上角顯示「NEW」
    /// (GFlyer-Suite docs/features/coordinate-library-new-badge.md)
    @MainActor
    static func coordinateLibrary(_ library: CoordinateLibraryController, open: @escaping () -> Void) -> MapToolItem {
        MapToolItem(
            id: "library",
            icon: "books.vertical",
            label: "座標圖鑑",
            badge: library.hasNewCoordinates ? CoordinateLibraryNewBadge.text : nil,
            action: open
        )
    }
}
