import SwiftUI

@main
struct GFlyerIOSApp: App {
    @StateObject private var controller = SimulationController()

    var body: some Scene {
        WindowGroup {
            MainView(controller: controller)
        }
    }
}
