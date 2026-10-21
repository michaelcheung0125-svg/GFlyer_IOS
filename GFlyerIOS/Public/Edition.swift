/// 公開版（App Store）。見 `EditionFeatures`。
enum Edition: EditionFeatures {
    static let callbackScheme = "jetpiggy-gflyer"

    static func speedHint(kilometresPerHour: Double) -> String? { nil }
}
