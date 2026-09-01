import Foundation

/// 搖桿的速度動力學（純函式，可單元測試），與 GFlyer Android 相同的設計：
/// - 位移決定目標速度，時間只決定逼近速度；手指收回來就慢下來。
/// - 三次曲線：中心附近行程細膩，外圈才衝到頂。
/// - 不對稱斜坡：加速慢、減速快，放手立刻有反應、不過衝。
/// - 推到邊（>97% 行程）切換成持續線性加速，直到上限。
enum JoystickDynamics {
    /// 加速時間常數（秒）：約 0.75 秒到達目標速度的九成。
    static let accelerationTauSeconds = 0.35
    /// 減速時間常數（秒）：明顯比加速快，放手才跟手。
    static let decelerationTauSeconds = 0.12
    /// 位移量超過這個比例視為「推到邊」，切換成持續加速。
    static let edgeThreshold = 0.97
    /// 推到邊後，從靜止線性加速到上限所需的秒數。
    static let edgeRampSeconds = 10.0
    /// 收尾吸附：非常接近目標速度時直接吸附，避免數字永遠跳動。
    static let snapEpsilon = 0.01

    static let minimumMetresPerSecond = SpeedScale.minimumKilometresPerHour / 3.6

    /// 由搖桿位移量（0..1，已扣 dead zone）算出巡航目標速度。
    static func targetSpeed(
        magnitude: Double,
        maxSpeedMetresPerSecond: Double,
        minSpeedMetresPerSecond: Double = minimumMetresPerSecond
    ) -> Double {
        let clamped = min(max(magnitude, 0), 1)
        guard clamped > 0 else { return 0 }
        let top = max(maxSpeedMetresPerSecond, minSpeedMetresPerSecond)
        let curved = clamped * clamped * clamped
        return minSpeedMetresPerSecond + (top - minSpeedMetresPerSecond) * curved
    }

    /// 算出這個 tick 之後的速度：未推到邊＝位置控制（指數逼近）；
    /// 推到邊＝速率控制（線性爬升到上限）。
    static func nextSpeed(
        currentMetresPerSecond: Double,
        magnitude: Double,
        maxSpeedMetresPerSecond: Double,
        deltaSeconds: Double,
        minSpeedMetresPerSecond: Double = minimumMetresPerSecond
    ) -> Double {
        guard deltaSeconds > 0 else { return currentMetresPerSecond }
        let top = max(maxSpeedMetresPerSecond, minSpeedMetresPerSecond)

        if magnitude >= edgeThreshold {
            let accelerationPerSecond = top / edgeRampSeconds
            return min(currentMetresPerSecond + accelerationPerSecond * deltaSeconds, top)
        }

        let target = targetSpeed(
            magnitude: magnitude,
            maxSpeedMetresPerSecond: top,
            minSpeedMetresPerSecond: minSpeedMetresPerSecond
        )
        return rampSpeed(
            currentMetresPerSecond: currentMetresPerSecond,
            targetMetresPerSecond: target,
            deltaSeconds: deltaSeconds
        )
    }

    /// 把目前速度朝目標速度推進一個 tick（指數逼近，與 tick 長度無關）。
    static func rampSpeed(
        currentMetresPerSecond: Double,
        targetMetresPerSecond: Double,
        deltaSeconds: Double,
        accelerationTauSeconds: Double = accelerationTauSeconds,
        decelerationTauSeconds: Double = decelerationTauSeconds
    ) -> Double {
        guard deltaSeconds > 0 else { return currentMetresPerSecond }
        let tau = targetMetresPerSecond >= currentMetresPerSecond
            ? accelerationTauSeconds
            : decelerationTauSeconds
        guard tau > 0 else { return targetMetresPerSecond }
        let factor = 1.0 - exp(-deltaSeconds / tau)
        let next = currentMetresPerSecond + (targetMetresPerSecond - currentMetresPerSecond) * factor
        return abs(targetMetresPerSecond - next) < snapEpsilon ? targetMetresPerSecond : next
    }
}
