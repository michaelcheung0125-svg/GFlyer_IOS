import SwiftUI

/// 會回應按壓的按鈕樣式。
///
/// 會有這個東西，是因為實機回報「按下去常常不確定有沒有按到」。原因出在
/// `.buttonStyle(.plain)`：它連系統預設的按壓高亮一起拿掉了，畫面上只剩一個
/// 圖示，手指壓住時什麼都不會變。
///
/// 這裡補回兩種回饋，而且兩種都要。視覺回饋（縮小加底色）單獨用不夠，因為
/// 手指往往正好蓋住剛按下去的那顆按鈕；觸覺回饋補上看不見的那一半。
struct PressFeedbackButtonStyle: ButtonStyle {
    /// 整列寬的按鈕要關掉縮放。小圖示縮一下最清楚，但一整條狀態列縮起來很
    /// 搶眼，看起來像跑版而不像「收到你的手指了」——那種寬度只留底色就夠。
    var scalesOnPress = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0))
            )
            .scaleEffect(configuration.isPressed && scalesOnPress ? 0.93 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
            // 只在「按下去」那一刻震一次。放開時再震一次，一次點擊會感覺像兩次。
            .sensoryFeedback(.impact(flexibility: .soft), trigger: configuration.isPressed) { was, now in
                !was && now
            }
    }
}
