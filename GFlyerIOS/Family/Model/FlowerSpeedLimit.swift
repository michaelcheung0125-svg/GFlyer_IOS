/// 種花的速度上限，照 Android 親友版的 `FlowerSpeedLimit`。
enum FlowerSpeedLimit {
    static let kilometresPerHour = 20.0

    /// 超過 20 km/h 才算。用 `SpeedScale.isAtMost`，所以從汽車按 −1 三十次（Android 以 Float 累加）
    /// 得到的 20.000013 km/h（畫面顯示 20.0）不會跳出警告。
    static func exceeds(_ speedKilometresPerHour: Double) -> Bool {
        !SpeedScale.isAtMost(speedKilometresPerHour, kilometresPerHour)
    }
}
