/// 親友版（經 SideStore 安裝）。見 `EditionFeatures`。
enum Edition: EditionFeatures {
    static let callbackScheme = "gflyer"

    static func speedHint(kilometresPerHour: Double) -> String? {
        FlowerSpeedLimit.exceeds(kilometresPerHour) ? "注意: 超過 20 km/h 將無法種花" : nil
    }
}
