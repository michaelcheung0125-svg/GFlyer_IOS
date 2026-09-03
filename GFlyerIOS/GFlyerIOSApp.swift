import SwiftUI

@main
struct GFlyerIOSApp: App {
    @StateObject private var controller = SimulationController()
    @StateObject private var messageBoard = MessageBoardController()
    @StateObject private var coordinateLibrary = CoordinateLibraryController()
    @StateObject private var updateChecker = AppUpdateChecker()
    @StateObject private var stepRecorder = StepRecorderController()

    var body: some Scene {
        WindowGroup {
            MainView(
                controller: controller,
                messageBoard: messageBoard,
                coordinateLibrary: coordinateLibrary,
                updateChecker: updateChecker,
                stepRecorder: stepRecorder
            )
            // 捷徑寫入步數後會用 gflyer://steps/... 回呼，把紀錄標成已寫入
            .onOpenURL { url in stepRecorder.handleCallback(url) }
        }
    }
}
