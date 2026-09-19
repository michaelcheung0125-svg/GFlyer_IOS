import SwiftUI
import UIKit

/// 關掉 MapKit 的「單指縮放」：點一下地圖、隨即再按住上下拖，會變成縮放
/// 而不是移動地圖，要等約半秒才恢復。
///
/// Apple Maps 也有這個手勢，但在 GFlyer 點地圖是用來選點，選完立刻拖動
/// 地圖正好撞上它。SwiftUI `Map` 沒有公開 API 可以只關這一個手勢——關掉
/// `.zoom` 會連雙指縮放一起關——所以只能照類別名稱找出
/// `_MKOneHandedZoomGestureRecognizer` 停用。找不到（例如日後 iOS 改名）時
/// 什麼都不做，行為和原本一樣；雙指縮放與雙擊放大不受影響。
struct OneHandedZoomDisabler: UIViewRepresentable {
    func makeUIView(context _: Context) -> ProbeView {
        ProbeView()
    }

    // 不在 update 時掃描：地圖畫面在模擬中每秒更新數次，每次都掃整個視窗太浪費
    func updateUIView(_: ProbeView, context _: Context) { }

    final class ProbeView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Map 內部的 UIKit 視圖可能比這個探針晚一點才建立：在 0、0.5、2 秒各掃一次
            Task { @MainActor [weak self] in
                for wait: UInt64 in [0, 500_000_000, 1_500_000_000] {
                    if wait > 0 { try? await Task.sleep(nanoseconds: wait) }
                    guard let window = self?.window else { return }
                    OneHandedZoomDisabler.disableOneHandedZoom(in: window)
                }
            }
        }
    }

    /// 停用 `view` 以下所有單指縮放手勢，回傳停用了幾個。
    @discardableResult
    static func disableOneHandedZoom(in view: UIView) -> Int {
        var disabled = 0
        for recognizer in view.gestureRecognizers ?? [] where isOneHandedZoom(recognizer) {
            if recognizer.isEnabled {
                recognizer.isEnabled = false
                disabled += 1
            }
        }
        for subview in view.subviews {
            disabled += disableOneHandedZoom(in: subview)
        }
        return disabled
    }

    static func isOneHandedZoom(_ recognizer: UIGestureRecognizer) -> Bool {
        String(describing: type(of: recognizer)).contains("OneHandedZoom")
    }
}
