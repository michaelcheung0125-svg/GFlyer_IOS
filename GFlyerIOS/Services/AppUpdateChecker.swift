import Combine
import Foundation
import UIKit

/// 讀取與 SideStore 相同的 AltStore 來源檔，比對執行中的版本，
/// 有新版時提示並把安裝動作交給 SideStore／AltStore。
/// App 本身不會、也無法安裝 IPA。
@MainActor
final class AppUpdateChecker: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage = "尚未檢查"
    @Published var lastError: String?
    @Published var showsPrompt = false

    let currentVersion: String
    let currentBuild: String
    let sourceURL: URL?

    private let bundleIdentifier: String
    private let session: URLSession
    private let defaults: UserDefaults
    private let checkInterval: TimeInterval = 6 * 60 * 60
    private let maximumSourceBytes = 2 * 1_024 * 1_024

    private let lastCheckedKey = "gflyer.update.last-checked"
    private let snoozedDayKey = "gflyer.update.snoozed-day"

    init(
        bundle: Bundle = .main,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        currentBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        bundleIdentifier = bundle.bundleIdentifier ?? "com.geopilot.gflyer.ios"
        let raw = (bundle.object(forInfoDictionaryKey: "GFlyerUpdateSourceURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw),
           url.scheme?.lowercased() == "https",
           url.host?.isEmpty == false,
           url.user == nil,
           url.password == nil {
            sourceURL = url
        } else {
            sourceURL = nil
        }
        self.session = session
        self.defaults = defaults
    }

    var displayVersion: String { "\(currentVersion) (\(currentBuild))" }

    /// 安裝來源檔的一鍵連結，方便使用者在 SideStore 加入這個來源。
    func addSourceURL(using installer: SideloadInstaller) -> URL? {
        sourceURL.flatMap { installer.addSourceURL(for: $0) }
    }

    /// App 回到前景時呼叫；距離上次檢查未滿間隔就跳過。
    func checkIfDue() {
        let last = defaults.object(forKey: lastCheckedKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= checkInterval else { return }
        check(userInitiated: false)
    }

    func checkNow() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        guard !isChecking else { return }
        guard let sourceURL else {
            if userInitiated { lastError = AppUpdateError.notConfigured.localizedDescription }
            return
        }
        isChecking = true
        if userInitiated { statusMessage = "檢查中…" }
        Task { [weak self] in
            guard let self else { return }
            defer { isChecking = false }
            do {
                let update = try await fetchUpdate(from: sourceURL)
                defaults.set(Date(), forKey: lastCheckedKey)
                availableUpdate = update
                if let update {
                    statusMessage = "有新版本 \(update.displayVersion)"
                    if userInitiated || !isSnoozedToday { showsPrompt = true }
                } else {
                    statusMessage = "已是最新版本"
                }
            } catch {
                statusMessage = "檢查失敗"
                if userInitiated { lastError = error.localizedDescription }
            }
        }
    }

    private func fetchUpdate(from url: URL) async throws -> AvailableUpdate? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GFlyer/\(currentVersion) (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AppUpdateError.server(http.statusCode)
        }
        guard data.count <= maximumSourceBytes else { throw AppUpdateError.tooLarge }
        return try AltStoreSourceParser.latestUpdate(
            from: data,
            bundleIdentifier: bundleIdentifier,
            currentVersion: currentVersion,
            currentBuild: currentBuild
        )
    }

    // MARK: - 提示控制

    private var todayKey: Int {
        Int(Date().timeIntervalSince1970 / 86_400)
    }

    var isSnoozedToday: Bool {
        defaults.integer(forKey: snoozedDayKey) == todayKey
    }

    func snoozeForToday() {
        defaults.set(todayKey, forKey: snoozedDayKey)
        showsPrompt = false
    }

    func dismissPrompt() {
        showsPrompt = false
    }

    /// 依序嘗試 SideStore、AltStore；都沒安裝時回傳 false 讓 UI 說明原因。
    @discardableResult
    func openInstaller(for update: AvailableUpdate, application: UIApplication = .shared) -> Bool {
        for installer in SideloadInstaller.allCases {
            guard let probe = installer.probeURL, application.canOpenURL(probe),
                  let installURL = installer.installURL(for: update.downloadURL) else { continue }
            application.open(installURL)
            showsPrompt = false
            return true
        }
        lastError = "找不到 SideStore 或 AltStore。請先安裝其中一個，或自行下載新版 IPA 再側載。"
        return false
    }
}
