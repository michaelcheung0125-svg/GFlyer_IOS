import Foundation

/// 用 x-callback-url 呼叫使用者自建的「捷徑」。
///
/// GFlyer 有兩件事只能靠捷徑完成：寫入健康 App 的步數（需要 HealthKit
/// entitlement，免費 Apple ID 拿不到），以及切換飛行模式（iOS 完全沒有公開
/// API）。兩者的呼叫方式一樣，所以組網址的規則集中在這裡。
enum ShortcutBridge {
    /// 回呼用的自訂 scheme，需與 Info.plist 的 CFBundleURLTypes 一致。
    static let callbackScheme = "gflyer"

    /// 組出 `shortcuts://x-callback-url/run-shortcut` 網址。
    ///
    /// - Parameters:
    ///   - name: 捷徑名稱，必須與使用者裝置上的名稱完全一致。
    ///   - text: 傳給捷徑的文字輸入，捷徑裡用「捷徑輸入」取用。
    ///   - success: 捷徑成功後要回到的網址。
    ///   - failure: 捷徑失敗後要回到的網址。
    static func runShortcutURL(name: String, text: String, success: String, failure: String) -> URL? {
        let query = [
            "name=\(escape(name))",
            "input=text",
            "text=\(escape(text))",
            "x-success=\(escape(success))",
            "x-error=\(escape(failure))",
        ].joined(separator: "&")
        return URL(string: "shortcuts://x-callback-url/run-shortcut?\(query)")
    }

    /// 逐字元編碼：巢狀網址裡的 `?`、`&`、`=` 一定要編碼，否則會被外層網址吃掉。
    static func escape(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
