import Combine
import Foundation
import UIKit

/// 讓 GFlyer 代使用者開關 LocalDevVPN，免得每次都要自己切去那個 App。
///
/// GFlyer 不能自己內建 VPN：Network Extension 權限只開放給付費開發者帳號，
/// 用免費 Apple ID 經 SideStore 簽名的 App 拿不到。LocalDevVPN 則提供
/// `localdevvpn://enable?scheme=gflyer` 與 `disable`：它開關 VPN 後約 1 秒會
/// 自己打開 `gflyer://`，把使用者帶回來。那個回呼網址沒有附帶結果，所以
/// GFlyer 不處理它，而是在回到前景後直接查路由表確認 VPN 真的開了或關了
/// （見 `TunnelRoute`）。這樣即使 LocalDevVPN 沒有自動跳回、使用者
/// 自己按「連線」再切回來，流程一樣接得下去。
@MainActor
final class LocalDevVPNBridge: ObservableObject {
    enum Action: Equatable {
        case connect
        case disconnect

        /// LocalDevVPN 網址的 host。
        var host: String { self == .connect ? "enable" : "disable" }
    }

    /// 送往目標 IP 的連線目前是否經過 VPN 介面。
    @Published private(set) var isTunnelUp = false
    /// 已跳去 LocalDevVPN、正在等結果。
    @Published private(set) var isSwitching = false
    /// 按開始時，如果 VPN 沒開就自動跳去 LocalDevVPN 開啟。
    @Published var autoConnectOnStart: Bool {
        didSet { defaults.set(autoConnectOnStart, forKey: Self.autoConnectKey) }
    }
    /// 完整清除成功後順便關閉 LocalDevVPN。
    @Published var disconnectAfterFullClear: Bool {
        didSet { defaults.set(disconnectAfterFullClear, forKey: Self.disconnectAfterClearKey) }
    }

    /// 由 `SimulationController.deviceIP` 同步過來，查路由時用。
    var deviceIP = "10.7.0.1" {
        didSet { refreshStatus() }
    }

    nonisolated static let scheme = "localdevvpn"
    static let connectFailureMessage =
        "LocalDevVPN 仍未連線。請打開 LocalDevVPN 按「連線」（英文介面為 Connect），再回到 GFlyer 重新開始。"
    static let disconnectFailureMessage =
        "LocalDevVPN 仍在連線。請打開 LocalDevVPN 按「斷線」（英文介面為 Disconnect）。"

    private struct Pending {
        let id = UUID()
        let action: Action
        let continuation: CheckedContinuation<Bool, Never>
        var hasLeftApp = false
    }

    private let defaults: UserDefaults
    private let routeCheck: (String) -> Bool
    private let canOpen: @MainActor (URL) -> Bool
    private let openURL: @MainActor (URL) async -> Bool
    private let pollAttempts: Int
    private let pollIntervalNanoseconds: UInt64
    private var pending: Pending?
    private var settleTask: Task<Void, Never>?
    // App 生命週期內都要持續監看，所以不移除觀察者；沒有 deinit 是刻意的
    private var observers: [NSObjectProtocol] = []

    private static let autoConnectKey = "gflyer.localdevvpn-auto-connect"
    private static let disconnectAfterClearKey = "gflyer.localdevvpn-disconnect-after-clear"

    /// - Parameters:
    ///   - pollAttempts: 回到 GFlyer 後最多查幾次路由。LocalDevVPN 固定等 1 秒
    ///     就跳回來，那時 VPN 可能還在連線中，所以要多等一陣。
    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        routeCheck: @escaping (String) -> Bool = TunnelRoute.routesThroughTunnel(deviceIP:),
        canOpen: @escaping @MainActor (URL) -> Bool = { UIApplication.shared.canOpenURL($0) },
        openURL: @escaping @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0) },
        pollAttempts: Int = 40,
        pollIntervalNanoseconds: UInt64 = 250_000_000
    ) {
        self.defaults = defaults
        self.routeCheck = routeCheck
        self.canOpen = canOpen
        self.openURL = openURL
        self.pollAttempts = max(pollAttempts, 1)
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        autoConnectOnStart = defaults.object(forKey: Self.autoConnectKey) as? Bool ?? true
        disconnectAfterFullClear = defaults.bool(forKey: Self.disconnectAfterClearKey)
        // 生命週期通知一定在主執行緒送出；queue 用 nil 讓處理同步發生，
        // 「離開 → 回來」的先後次序才不會被打亂
        observers = [
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { () -> Void in self?.appDidEnterBackground() }
            },
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { () -> Void in self?.appDidBecomeActive() }
            },
        ]
        refreshStatus()
    }

    var isInstalled: Bool {
        guard let url = URL(string: "\(Self.scheme)://") else { return false }
        return canOpen(url)
    }

    func refreshStatus() {
        let up = routeCheck(deviceIP)
        if isTunnelUp != up { isTunnelUp = up }
    }

    /// 按開始時是否要先跳去 LocalDevVPN：VPN 沒開、使用者沒關掉這個功能、
    /// 而且裝了 LocalDevVPN。沒裝的話照舊直接開始，由連線錯誤提示接手。
    func needsConnectBeforeStart() -> Bool {
        refreshStatus()
        return !isTunnelUp && autoConnectOnStart && isInstalled
    }

    /// 請 LocalDevVPN 開或關 VPN。等使用者回到 GFlyer、VPN 狀態真的變成
    /// 要求的樣子才回傳 true；打不開 LocalDevVPN 或逾時則回傳 false。
    func perform(_ action: Action) async -> Bool {
        // 上一次還在等結果又收到新要求：先以失敗結束它，continuation 只能 resume 一次
        finishPending(reached: false)
        guard let url = Self.url(for: action) else { return false }
        let reached = await withCheckedContinuation { continuation in
            let request = Pending(action: action, continuation: continuation)
            let requestID = request.id
            pending = request
            isSwitching = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await openURL(url) == false, pending?.id == requestID {
                    finishPending(reached: false)
                }
            }
        }
        refreshStatus()
        return reached
    }

    // MARK: - 生命週期

    private func appDidEnterBackground() {
        pending?.hasLeftApp = true
    }

    private func appDidBecomeActive() {
        refreshStatus()
        // 只在「跳去 LocalDevVPN 之後回來」才確認結果；拉下控制中心之類
        // 不會進背景的切換不算
        guard let current = pending, current.hasLeftApp, settleTask == nil else { return }
        let id = current.id
        settleTask = Task { [weak self] in
            await self?.settle(id)
        }
    }

    private func settle(_ id: UUID) async {
        defer { settleTask = nil }
        for attempt in 0..<pollAttempts {
            guard let current = pending, current.id == id else { return }
            refreshStatus()
            if isTunnelUp == (current.action == .connect) {
                finishPending(reached: true)
                return
            }
            if attempt < pollAttempts - 1 {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
        guard pending?.id == id else { return }
        finishPending(reached: false)
    }

    private func finishPending(reached: Bool) {
        guard let current = pending else { return }
        pending = nil
        isSwitching = false
        current.continuation.resume(returning: reached)
    }

    // MARK: - 網址

    /// `localdevvpn://enable?scheme=gflyer`：LocalDevVPN 做完會打開 `gflyer://`。
    nonisolated static func url(for action: Action) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = action.host
        components.queryItems = [URLQueryItem(name: "scheme", value: ShortcutBridge.callbackScheme)]
        return components.url
    }
}
