import Combine
import SwiftUI
import UIKit

/// 公開版的本機通道：App 內建的通道 extension（`GFlyerPublicTunnel`），經 `TunnelSystem` 開關
/// （docs/APP_STORE_PLAN.md 第 12 項）。不用切去別的 App，所以按開始時通道沒開就一定先開。
/// 通道有沒有開照舊查路由（`TunnelRoute`），和 iOS 回報的 VPN 狀態無關：目標 IP 改了之後，
/// 開着的通道導的是舊位址，也算沒開。見 `LocalTunnelFeatures`。
@MainActor
final class LocalTunnel: ObservableObject, LocalTunnelFeatures {
    /// 送往目標 IP 的連線目前是否經過通道。
    @Published private(set) var isTunnelUp = false
    /// 正在開或關通道；值是要開（true）還是要關。
    @Published private(set) var switching: Bool?
    /// 完整清除成功後順便關閉通道。
    @Published var disconnectAfterFullClear: Bool {
        didSet { defaults.set(disconnectAfterFullClear, forKey: Self.disconnectAfterClearKey) }
    }

    /// 由 `SimulationController.deviceIP` 同步過來，開通道和查路由時用。
    var deviceIP = "10.7.0.1" {
        didSet { refreshStatus() }
    }

    static let connectTimeoutMessage = "本機通道仍未連線。請到設定頁再按一次「開啟本機通道」。"
    static let disconnectFailureMessage = "本機通道仍在連線。請到設定頁再按一次「關閉本機通道」。"
    static let busyMessage = "本機通道正在開啟或關閉，請稍候再試。"

    private let system: TunnelSystem
    private let defaults: UserDefaults
    private let routeCheck: (String) -> Bool
    private let pollAttempts: Int
    private let pollIntervalNanoseconds: UInt64
    // App 生命週期內都要持續監看，所以不移除觀察者；沒有 deinit 是刻意的
    private var observers: [NSObjectProtocol] = []

    private static let disconnectAfterClearKey = "gflyer.local-tunnel-disconnect-after-clear"

    /// - Parameters:
    ///   - pollAttempts: 開或關之後最多查幾次路由。iOS 開通道要一點時間，第一次還要等使用者
    ///     回答加入 VPN 設定（那段時間 `system.connect` 還沒返回，不算在這裏）。
    init(
        system: TunnelSystem? = nil,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        routeCheck: @escaping (String) -> Bool = TunnelRoute.routesThroughTunnel(deviceIP:),
        pollAttempts: Int = 40,
        pollIntervalNanoseconds: UInt64 = 250_000_000
    ) {
        self.system = system ?? SystemTunnel()
        self.defaults = defaults
        self.routeCheck = routeCheck
        self.pollAttempts = max(pollAttempts, 1)
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        disconnectAfterFullClear = defaults.bool(forKey: Self.disconnectAfterClearKey)
        // 使用者可能在 iOS 的 VPN 設定裏自己開關通道，回到 GFlyer 時重新查
        observers = [
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { () -> Void in self?.refreshStatus() }
            },
        ]
        refreshStatus()
    }

    func refreshStatus() {
        let up = routeCheck(deviceIP)
        if isTunnelUp != up { isTunnelUp = up }
    }

    /// 開或關通道，等路由真的變成要求的樣子才回傳 nil；不成功回傳要顯示的錯誤。
    func perform(connect: Bool) async -> String? {
        guard switching == nil else { return Self.busyMessage }
        switching = connect
        defer {
            switching = nil
            refreshStatus()
        }
        if connect {
            do {
                try await system.connect(targetAddress: deviceIP)
            } catch {
                return "無法開啟本機通道：\(error.localizedDescription)\n第一次開啟時，iOS 會詢問可否加入 VPN 設定，要允許才能使用。"
            }
        } else {
            await system.disconnect()
        }
        for attempt in 0..<pollAttempts {
            if routeCheck(deviceIP) == connect { return nil }
            if attempt < pollAttempts - 1 {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
        return connect ? Self.connectTimeoutMessage : Self.disconnectFailureMessage
    }

    // MARK: - LocalTunnelFeatures

    func statusWhileConnectingBeforeStart() -> String? {
        refreshStatus()
        return isTunnelUp ? nil : "正在開啟本機通道…"
    }

    func connectBeforeStart() async -> TunnelFailure? {
        guard let message = await perform(connect: true) else { return nil }
        return TunnelFailure(status: "本機通道尚未連線", message: message)
    }

    /// 使用者開了「清除後同時關閉本機通道」而且通道目前開着才會動作。
    func disconnectAfterFullClearIfWanted() async -> TunnelClosing? {
        refreshStatus()
        guard disconnectAfterFullClear, isTunnelUp else { return nil }
        let failure = await perform(connect: false)
        return TunnelClosing(closed: failure == nil, message: failure ?? "本機通道已關閉。")
    }

    static let stillSimulatedWhileOpenMessage: String? =
        "模擬 session 已關閉，但 iOS 仍回報模擬座標。請關閉本機通道，開關一次飛行模式後再確認；必要時重新開機。"

    static let settingsTitle = "本機通道"

    func settingsRows(controller: SimulationController) -> some View {
        LocalTunnelSettingsRows(controller: controller, tunnel: self)
    }

    static let testButtonTitle = "測試本機通道"

    static let deviceIPHint = "目標 IP 預設為 10.7.0.1，本機通道會把這個位址導回這部 iPhone；Remote Pairing port 為 49152。"

    func recoveryRows(isClearing: Bool) -> some View {
        LocalTunnelRecoveryRows(tunnel: self, isClearing: isClearing)
    }

    static let usageSteps = [
        "3. 按「開啟本機通道」。第一次開啟時，iOS 會詢問可否加入 VPN 設定，要允許才能使用。",
        "4. 回到地圖選點並按開始；本機通道未開時 GFlyer 會自動開啟。",
    ]
}
