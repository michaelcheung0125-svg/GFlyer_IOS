import SwiftUI

/// 留言板的兩個畫面：從導覽列打開的留言板，以及從地圖工具列打開的「分享到留言板」。
struct MessageBoardSheets: ViewModifier {
    @ObservedObject var edition: EditionModel
    let simulation: SimulationController

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $edition.showsMessageBoard) {
                MessageBoardView(board: edition.messageBoard, simulation: simulation)
            }
            .sheet(isPresented: $edition.showsBoardShare) {
                ShareToMessageBoardView(board: edition.messageBoard, simulation: simulation)
            }
    }
}

/// 導覽列的留言板按鈕，右上角是未讀數。
struct MessageBoardNavigationButton: View {
    @ObservedObject var board: MessageBoardController
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "bubble.left.and.bubble.right")
                .overlay(alignment: .topTrailing) { unreadBadge }
        }
        .accessibilityLabel("留言板，\(board.unreadCount) 個未讀項目")
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if board.unreadCount > 0 {
            Text(board.unreadCount > 99 ? "99+" : "\(board.unreadCount)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xs)
                .frame(minWidth: 14, minHeight: 14)
                // 這個紅色是 iOS 未讀徽章的慣例，不是 statusDanger。綁上狀態色的話，
                // 哪天調整「危險」的顏色，徽章會跟著變成一個不再像徽章的東西。
                .background(.red, in: Capsule())
                .offset(x: 8, y: -8)
        }
    }
}

extension MapToolItem {
    /// 地圖工具列的「分享到留言板」。
    static func boardShare(open: @escaping () -> Void) -> MapToolItem {
        MapToolItem(id: "board-share", icon: "square.and.arrow.up", label: "分享到留言板", action: open)
    }
}
