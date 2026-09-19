import Combine
import Darwin
import Foundation
import UIKit

/// 讓 GFlyer 代使用者開關 LocalDevVPN，免得每次都要自己切去那個 App。
///
/// GFlyer 不能自己內建 VPN：Network Extension 權限只開放給付費開發者帳號，
/// 用免費 Apple ID 經 SideStore 簽名的 App 拿不到。LocalDevVPN 則提供
/// `localdevvpn://enable?scheme=gflyer` 與 `disable`：它開關 VPN 後約 1 秒會
/// 自己打開 `gflyer://`，把使用者帶回來。那個回呼網址沒有附帶結果，所以
/// GFlyer 不處理它，而是在回到前景後直接查路由表確認 VPN 真的開了或關了
/// （見 `routesThroughTunnel`）。這樣即使 LocalDevVPN 沒有自動跳回、使用者
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
        routeCheck: @escaping (String) -> Bool = LocalDevVPNBridge.routesThroughTunnel(deviceIP:),
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

    // MARK: - 路由檢查

    /// 問系統：送往 `deviceIP` 的封包會從哪張網卡出去。
    ///
    /// UDP 的 `connect()` 只查路由表、不送出任何封包，所以這個檢查沒有副作用，
    /// 也不會觸發 LocalDevVPN 的隨選連線規則（那些規則比對的是網域名稱）。
    /// LocalDevVPN 只把目標 IP 這一條路由導進 VPN，其他流量照舊走 Wi-Fi 或
    /// 行動網絡，所以「這一條路由走 VPN 介面」就代表 LocalDevVPN 已連線。
    nonisolated static func routesThroughTunnel(deviceIP: String) -> Bool {
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(49_152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else {
            return false
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let connected = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        // 飛行模式且沒有 VPN 時沒有任何路由，connect 會直接失敗
        guard connected == 0 else { return false }

        var source = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0, let name = interfaceName(owning: source.sin_addr) else { return false }
        return isTunnelInterface(name)
    }

    /// iOS 的 VPN 介面名稱：Network Extension 用 `utun`，IKEv2/IPsec 用 `ipsec`。
    nonisolated static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
    }

    private nonisolated static func interfaceName(owning address: in_addr) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let raw = entry.pointee.ifa_addr,
                  raw.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let candidate = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            if candidate.s_addr == address.s_addr {
                return String(cString: entry.pointee.ifa_name)
            }
        }
        return nil
    }
}
