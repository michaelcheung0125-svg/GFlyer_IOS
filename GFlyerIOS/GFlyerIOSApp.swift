import SwiftUI

@main
struct GFlyerIOSApp: App {
    @StateObject private var controller = SimulationController()
    @StateObject private var messageBoard = MessageBoardController()

    var body: some Scene {
        WindowGroup {
            MainView(controller: controller, messageBoard: messageBoard)
        }
    }
}
