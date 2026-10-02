import Foundation

/// 「聯絡我們」電郵的收件人、標題與內文，三平台一字不差
/// （GFlyer-Suite docs/features/contact-us.md、contracts/fixtures/contact/email.json）。
/// SharedContractTests 照抄 fixture 的期望值，改文字時兩邊要一起改。
enum ContactEmail {
    static let address = "gflyer@jetpiggy.com"

    /// 找不到可以寄電郵的 App 時顯示；這時地址已經複製到剪貼簿。
    static let noMailAppMessage = "找不到可以寄電郵的 App，已複製地址 \(address)。"

    static func subject(platform: String, version: String) -> String {
        "GFlyer 意見回報（\(platform) v\(filled(version))）"
    }

    /// 前面三個空行留給使用者寫內容；最後一行後面沒有換行。
    static func body(platform: String, version: String, build: String, system: String, device: String) -> String {
        "\n\n\n----\n以下資料方便我們找出問題，請保留：\n"
            + "App：GFlyer \(platform) v\(filled(version))（\(filled(build))）\n"
            + "系統：\(filled(system))\n"
            + "裝置：\(filled(device))"
    }

    /// 標題與內文放在 mailto: 的查詢參數裡，由 URLComponents 編碼。
    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// 硬體代碼，例如 iPhone16,2；模擬器上是 arm64 或 x86_64。
    static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// 去掉前後空白；是空字串時寫成「未知」。
    private static func filled(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知" : trimmed
    }
}
