import Foundation

/// 執行中的 App 版本。設定頁的「關於」和「聯絡我們」的電郵用，兩個版本都有；
/// 親友版的檢查新版另外自己讀。
struct AppVersionInfo {
    let version: String
    let build: String
    /// 重簽時可能被加上後綴，顯示在設定頁方便診斷比對問題。
    let bundleIdentifier: String

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        bundleIdentifier = bundle.bundleIdentifier ?? ""
    }

    var displayVersion: String { "\(version) (\(build))" }
}
