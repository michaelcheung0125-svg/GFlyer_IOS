import SwiftUI

@main
struct GFlyerIOSApp: App {
    @StateObject private var controller = SimulationController()
    @StateObject private var messageBoard = MessageBoardController()
    @StateObject private var coordinateLibrary = CoordinateLibraryController()
    @StateObject private var updateChecker = AppUpdateChecker()
    @StateObject private var stepRecorder = StepRecorderController()
    @StateObject private var airplaneAssist = AirplaneAssistController()

    var body: some Scene {
        WindowGroup {
            MainView(
                controller: controller,
                messageBoard: messageBoard,
                coordinateLibrary: coordinateLibrary,
                updateChecker: updateChecker,
                stepRecorder: stepRecorder,
                airplaneAssist: airplaneAssist
            )
            // 兩種捷徑回呼：gflyer://steps/... 把補錄標成已寫入，
            // gflyer://airplane/... 回報飛行模式有沒有切換成功
            .onOpenURL { url in
                guard !stepRecorder.handleCallback(url) else { return }
                airplaneAssist.handleCallback(url)
            }
        }
    }
}
