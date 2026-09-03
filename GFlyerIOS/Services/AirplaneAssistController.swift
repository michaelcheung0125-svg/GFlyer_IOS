import Combine
import Foundation
import Network
import UIKit

/// 協助使用者完成「開飛行模式 → 開始模擬 → 關飛行模式」這串操作。
///
/// 在行動網絡下，先進入飛行模式再建立模擬明顯比較穩定（實測）。iOS **沒有任何
/// 公開 API 讓 App 自己切換飛行模式**，所以這裡能做的是兩件事：
///
/// 1. 用 `NWPathMonitor` 判斷目前在 Wi-Fi、行動網絡還是已斷網，讓畫面上的步驟
///    自動推進——使用者不必猜「現在可以關掉飛行模式了嗎」。
/// 2. 對願意多建一個捷徑的人，透過捷徑的「設定飛航模式」動作代為切換，把控制
///    中心那幾下操作變成 App 內的一個按鈕。
///
/// 沒有建捷徑的人也完全能用，只是第 1、3 步要自己去控制中心切。
@MainActor
final class AirplaneAssistController: ObservableObject {
    /// 目前的對外連線方式。`unknown` 多半代表只剩 VPN 之類的介面。
    enum Connection: String, Equatable {
        case wifi
        case cellular
        case offline
        case unknown

        var label: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "行動網絡"
            case .offline: return "無網絡（飛行模式）"
            case .unknown: return "偵測中"
            }
        }

        var iconName: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .offline: return "airplane"
            case .unknown: return "questionmark.circle"
            }
        }

        /// 只有行動網絡需要這套流程；Wi-Fi 下通常直接開始模擬就可以。
        var needsAssist: Bool { self == .cellular }
    }

    /// 流程中的四個狀態，全部由目前連線與模擬狀態推導，不另外保存。
    ///
    /// 這樣做的好處是不會有「畫面停在第 2 步但其實早就模擬中」的狀態不同步；
    /// 使用者從控制中心手動切換飛行模式，畫面一樣會跟著跳。
    enum Step: Equatable {
        case turnOnAirplane
        case startSimulation
        case turnOffAirplane
        case finished
    }

    @Published private(set) var connection: Connection = .unknown
    @Published var lastMessage: String?
    @Published var lastError: String?
    @Published var shortcutName: String {
        didSet {
            defaults.set(shortcutName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: shortcutNameKey)
        }
    }
    /// 使用者已建立飛航切換捷徑並願意讓 App 呼叫它。
    @Published var isAutomationEnabled: Bool {
        didSet { defaults.set(isAutomationEnabled, forKey: automationKey) }
    }
    /// 模擬成功開始後自動把飛行模式關回去。
    ///
    /// 只自動化「關閉」這個方向：關掉飛行模式永遠是安全的，失敗了也只是維持
    /// 現狀由使用者自己關；反過來自動開啟飛行模式若中途出錯，會把人留在斷網
    /// 狀態，所以那一步一律保持手動。
    @Published var autoDisableAfterStart: Bool {
        didSet { defaults.set(autoDisableAfterStart, forKey: autoDisableKey) }
    }

    static let defaultShortcutName = "GFlyer 飛航切換"

    private let defaults: UserDefaults
    private let shortcutNameKey = "gflyer.airplane-shortcut-name"
    private let automationKey = "gflyer.airplane-automation-enabled"
    private let autoDisableKey = "gflyer.airplane-auto-disable"
    // 使用者按過「開始模擬」之後才允許自動關閉，避免任何一次模擬開始都跳去捷徑
    private var isAwaitingAutoDisable = false
    // App 生命週期內都要持續監看，所以不做 cancel；沒有 deinit 是刻意的
    private let monitor = NWPathMonitor()

    init(defaults: UserDefaults = .standard, startsMonitoring: Bool = true) {
        self.defaults = defaults
        shortcutName = (defaults.string(forKey: shortcutNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultShortcutName
        isAutomationEnabled = defaults.bool(forKey: automationKey)
        autoDisableAfterStart = defaults.object(forKey: autoDisableKey) as? Bool ?? true
        guard startsMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let connection = AirplaneAssistController.connection(
                isSatisfied: path.status == .satisfied,
                usesWiFi: path.usesInterfaceType(.wifi),
                usesCellular: path.usesInterfaceType(.cellular)
            )
            Task { @MainActor in self?.updateConnection(connection) }
        }
        monitor.start(queue: DispatchQueue(label: "com.geopilot.gflyer.airplane-assist"))
    }

    /// 更新目前連線狀態。正式執行時由 `NWPathMonitor` 呼叫。
    func updateConnection(_ connection: Connection) {
        self.connection = connection
    }

    var isShortcutsInstalled: Bool {
        guard let url = URL(string: "shortcuts://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// 是否可以用捷徑代切飛行模式。
    var isAutomationReady: Bool {
        isAutomationEnabled
            && isShortcutsInstalled
            && !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func step(isSimulating: Bool) -> Step {
        Self.step(connection: connection, isSimulating: isSimulating)
    }

    /// 由連線狀態與模擬狀態推導目前該做哪一步。
    nonisolated static func step(connection: Connection, isSimulating: Bool) -> Step {
        switch (isSimulating, connection) {
        case (false, .offline): return .startSimulation
        case (false, _): return .turnOnAirplane
        case (true, .offline): return .turnOffAirplane
        case (true, _): return .finished
        }
    }

    /// 從 NWPathMonitor 的背景 queue 呼叫，所以不能是 MainActor 隔離的。
    nonisolated static func connection(isSatisfied: Bool, usesWiFi: Bool, usesCellular: Bool) -> Connection {
        guard isSatisfied else { return .offline }
        if usesWiFi { return .wifi }
        if usesCellular { return .cellular }
        // 只剩 VPN 之類的介面時無法判斷是哪種底層連線，不要猜
        return .unknown
    }

    // MARK: - 切換

    /// 呼叫捷徑切換飛行模式。捷徑會收到 `on` 或 `off` 作為文字輸入。
    func setAirplaneMode(_ turnOn: Bool, application: UIApplication = .shared) {
        lastError = nil
        lastMessage = nil
        guard isShortcutsInstalled else {
            lastError = "找不到「捷徑」App，請先從 App Store 安裝。"
            return
        }
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            lastError = "請先填寫飛航切換捷徑的名稱。"
            return
        }
        guard let url = Self.airplaneShortcutURL(name: name, turnOn: turnOn) else {
            lastError = "無法組出捷徑連結，請確認捷徑名稱。"
            return
        }
        application.open(url, options: [:]) { [weak self] opened in
            guard let self, !opened else { return }
            Task { @MainActor in self.lastError = "無法開啟捷徑 App。" }
        }
    }

    /// 使用者在輔助畫面按下「開始模擬」時呼叫，讓之後的自動關閉生效一次。
    func armAutoDisable() {
        isAwaitingAutoDisable = true
    }

    func cancelAutoDisable() {
        isAwaitingAutoDisable = false
    }

    /// 模擬真的開始之後呼叫。回傳是否觸發了自動關閉，方便畫面顯示提示。
    @discardableResult
    func simulationDidActivate(application: UIApplication = .shared) -> Bool {
        guard isAwaitingAutoDisable else { return false }
        isAwaitingAutoDisable = false
        guard autoDisableAfterStart, isAutomationReady, connection == .offline else { return false }
        setAirplaneMode(false, application: application)
        return true
    }

    // MARK: - 回呼

    /// 處理 `gflyer://airplane/on`、`/off`、`/failed` 三種回呼。
    /// 回傳是否為本控制器負責的網址。
    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == ShortcutBridge.callbackScheme,
              url.host?.lowercased() == "airplane" else { return false }
        switch url.lastPathComponent.lowercased() {
        case "on":
            // 不覆寫 connection：NWPathMonitor 會回報實際狀態，比捷徑的回報可靠
            lastMessage = "已開啟飛行模式，現在可以開始模擬。"
        case "off":
            lastMessage = "已關閉飛行模式，模擬會繼續進行。"
        case "failed":
            isAwaitingAutoDisable = false
            lastError = "捷徑沒有成功切換飛行模式，請改用控制中心手動切換。"
        default:
            return false
        }
        return true
    }

    // MARK: - 網址

    nonisolated static func airplaneShortcutURL(name: String, turnOn: Bool) -> URL? {
        let state = turnOn ? "on" : "off"
        return ShortcutBridge.runShortcutURL(
            name: name,
            text: state,
            success: "\(ShortcutBridge.callbackScheme)://airplane/\(state)",
            failure: "\(ShortcutBridge.callbackScheme)://airplane/failed"
        )
    }
}
