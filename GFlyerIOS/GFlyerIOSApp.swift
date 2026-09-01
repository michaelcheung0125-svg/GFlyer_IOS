import SwiftUI

@main
struct GFlyerIOSApp: App {
    @StateObject private var controller = SimulationController()
    @StateObject private var messageBoard = MessageBoardController()
    @StateObject private var coordinateLibrary = CoordinateLibraryController()

    var body: some Scene {
        WindowGroup {
            MainView(
                controller: controller,
                messageBoard: messageBoard,
                coordinateLibrary: coordinateLibrary
            )
        }
    }
}
