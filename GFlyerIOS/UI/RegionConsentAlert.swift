import SwiftUI

/// 「顯示收藏的國家與城市？」(GFlyer-Suite docs/features/region-labels.md 3.10):第一次把收藏的座標送去反查之前
/// 先說明並取得同意,只有要先取得同意的版本(公開版)會跳出。照 Android 的 `RegionConsentDialog`:一定要按
/// 「允許」或「不用」。iOS 的 alert 點外面本來就關不掉;兩個鈕都不是 cancel,實體鍵盤的 Esc 也不會當成拒絕。
///
/// 主畫面和設定頁各掛一個:設定頁是 sheet,它開着時主畫面的 alert 跳不出來。
struct RegionConsentAlert: ViewModifier {
    @ObservedObject var controller: SimulationController
    /// 同一層有別的畫面或提示開着時是 true,等它們關掉才跳出,免得互相擋掉。
    var isBlocked = false
    /// 按了其中一個鈕之後,傳回是誰叫出說明的:按 ☆ 叫出的要接着打開命名 sheet。
    var onAnswer: (RegionConsentPrompt) -> Void = { _ in }

    func body(content: Content) -> some View {
        content.alert(RegionLookupConsentText.title, isPresented: isPresented) {
            // 次序和 Android 相同:「不用」在左、「允許」在右
            Button(RegionLookupConsentText.declineButton) { answer(allowed: false) }
            Button(RegionLookupConsentText.allowButton) { answer(allowed: true) }
        } message: {
            Text(controller.regionConsentParagraphs.joined(separator: "\n\n"))
        }
    }

    /// 只有按鈕會答覆:alert 被系統收起時不當成同意或拒絕,之後再跳出來。
    private var isPresented: Binding<Bool> {
        Binding(get: { controller.regionConsentPrompt != nil && !isBlocked }, set: { _ in })
    }

    private func answer(allowed: Bool) {
        guard let prompt = controller.regionConsentPrompt else { return }
        controller.answerRegionConsent(allowed: allowed)
        onAnswer(prompt)
    }
}
