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
            // gflyer://airplane/... 回報飛行模式有沒有切換成功。
            // LocalDevVPN 開關 VPN 後打開的是沒有路徑的 gflyer://，刻意不處理：
            // 結果由 LocalDevVPNBridge 在回到前景時查路由確認
            .onOpenURL { url in
                guard !stepRecorder.handleCallback(url) else { return }
                airplaneAssist.handleCallback(url)
            }
        }
    }
}
