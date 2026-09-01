import Foundation

struct AvailableUpdate: Equatable {
    let version: String
    let buildVersion: String
    let releaseNotes: String
    let downloadURL: URL
    let minOSVersion: String?

    var displayVersion: String { "\(version) (\(buildVersion))" }
}

enum AppVersionOrder {
    /// 先比行銷版本（0.3.0），相同再比 build number。
    /// 兩者都用數字逐段比較，缺少的段視為 0，所以 "0.4" 會大於 "0.3.9"。
    static func isNewer(
        candidateVersion: String,
        candidateBuild: String,
        thanVersion currentVersion: String,
        build currentBuild: String
    ) -> Bool {
        switch compare(candidateVersion, currentVersion) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame: return compare(candidateBuild, currentBuild) == .orderedDescending
        }
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(of: lhs)
        let right = components(of: rhs)
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue != rightValue {
                return leftValue > rightValue ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }

    private static func components(of value: String) -> [Int] {
        value
            .split(separator: ".")
            .map { segment in
                // 容忍 "1.2.3-beta" 這類尾綴：只取開頭的數字
                Int(segment.prefix { $0.isNumber }) ?? 0
            }
    }
}

/// 解析 AltStore/SideStore 來源檔，取出指定 App 最新且可安裝的版本。
enum AltStoreSourceParser {
    static func latestUpdate(
        from data: Data,
        bundleIdentifier: String,
        currentVersion: String,
        currentBuild: String
    ) throws -> AvailableUpdate? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let apps = root["apps"] as? [[String: Any]] else {
            throw AppUpdateError.invalidSource
        }
        guard let app = matchingApp(in: apps, bundleIdentifier: bundleIdentifier),
              let versions = app["versions"] as? [[String: Any]] else {
            return nil
        }

        let candidates = versions.compactMap { entry -> AvailableUpdate? in
            guard let version = entry["version"] as? String,
                  let urlText = entry["downloadURL"] as? String,
                  let url = URL(string: urlText),
                  url.scheme?.lowercased() == "https" else { return nil }
            let build = (entry["buildVersion"] as? String)
                ?? (entry["buildVersion"] as? NSNumber).map { $0.stringValue }
                ?? version
            return AvailableUpdate(
                version: version,
                buildVersion: build,
                releaseNotes: (entry["localizedDescription"] as? String) ?? "",
                downloadURL: url,
                minOSVersion: entry["minOSVersion"] as? String
            )
        }

        // 來源檔慣例是最新版排在前面，但不倚賴這一點，自己挑出最大的
        let newest = candidates.max { first, second in
            AppVersionOrder.isNewer(
                candidateVersion: second.version,
                candidateBuild: second.buildVersion,
                thanVersion: first.version,
                build: first.buildVersion
            )
        }
        guard let newest else { return nil }
        guard AppVersionOrder.isNewer(
            candidateVersion: newest.version,
            candidateBuild: newest.buildVersion,
            thanVersion: currentVersion,
            build: currentBuild
        ) else { return nil }
        return newest
    }
}

extension AltStoreSourceParser {
    /// 找出來源檔裡對應這個 App 的項目。
    ///
    /// 不能只用完全相等比對：SideStore／AltStore 以免費 Apple ID 安裝時，
    /// 會在 bundle identifier 後面接上 team id 之類的後綴，所以執行時拿到的
    /// 是 `com.example.app.TEAMID`，而來源檔寫的是 `com.example.app`。
    static func matchingApp(
        in apps: [[String: Any]],
        bundleIdentifier: String
    ) -> [String: Any]? {
        if let exact = apps.first(where: { $0["bundleIdentifier"] as? String == bundleIdentifier }) {
            return exact
        }
        if let prefixed = apps.first(where: { app in
            guard let sourceID = app["bundleIdentifier"] as? String, !sourceID.isEmpty else {
                return false
            }
            // 要求接在點號邊界，避免 com.example.app 誤配 com.example.apple
            return bundleIdentifier.hasPrefix(sourceID + ".")
        }) {
            return prefixed
        }
        // 單一 App 的來源檔沒有其他候選，重簽改過 id 也不會認錯對象
        return apps.count == 1 ? apps.first : nil
    }
}

enum AppUpdateError: LocalizedError, Equatable {
    case notConfigured
    case invalidSource
    case tooLarge
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未設定更新來源網址。"
        case .invalidSource: return "更新來源資料格式不正確。"
        case .tooLarge: return "更新來源資料過大。"
        case let .server(code): return "更新來源伺服器傳回錯誤（HTTP \(code)）。"
        }
    }
}

/// 把安裝動作交給 SideStore（或 AltStore）的 URL scheme。
enum SideloadInstaller: String, CaseIterable {
    case sideStore = "sidestore"
    case altStore = "altstore"

    var displayName: String {
        switch self {
        case .sideStore: return "SideStore"
        case .altStore: return "AltStore"
        }
    }

    var probeURL: URL? { URL(string: "\(rawValue)://") }

    func installURL(for downloadURL: URL) -> URL? {
        encoded(action: "install", target: downloadURL)
    }

    func addSourceURL(for sourceURL: URL) -> URL? {
        encoded(action: "source", target: sourceURL)
    }

    private func encoded(action: String, target: URL) -> URL? {
        var components = URLComponents()
        components.scheme = rawValue
        components.host = action
        components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        return components.url
    }
}
