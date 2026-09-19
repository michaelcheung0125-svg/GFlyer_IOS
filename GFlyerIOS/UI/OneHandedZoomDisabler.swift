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
///
/// 只在畫面出現時關一次是不夠的：0.6.4 關過之後，0.6.5 又有人遇到縮放，
/// 顯示地圖會在自己更新版面時把手勢重新啟用。所以這裡記住找到的手勢物件，
/// 每次 SwiftUI 更新地圖時順手關回去，另外用一個低頻率的迴圈定期複查，
/// 並每隔幾次重新掃描一次，以防手勢物件被整個換掉。
struct OneHandedZoomDisabler: UIViewRepresentable {
    func makeUIView(context _: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_ uiView: ProbeView, context _: Context) {
        // 只把記住的那幾個關回去，成本極低，可以跟著地圖的每次更新跑
        uiView.reapplyToKnownRecognizers()
    }

    final class ProbeView: UIView {
        private struct WeakRecognizer {
            weak var value: UIGestureRecognizer?
        }

        private var known: [WeakRecognizer] = []
        private var watchTask: Task<Void, Never>?

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
            guard window != nil else {
                watchTask?.cancel()
                watchTask = nil
                return
            }
            guard watchTask == nil else { return }
            watchTask = Task { @MainActor [weak self] in
                var untilNextSweep = 0
                while !Task.isCancelled, let view = self, view.window != nil {
                    // 在背景不用做：地圖沒有在更新，手勢也不會被重新啟用
                    if UIApplication.shared.applicationState == .active {
                        if untilNextSweep <= 0 {
                            view.sweepWindow()
                            untilNextSweep = 3
                        } else {
                            view.reapplyToKnownRecognizers()
                            untilNextSweep -= 1
                        }
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        /// 重新掃描整個視窗，記住並停用找到的單指縮放手勢。
        func sweepWindow() {
            guard let window else { return }
            var found: [UIGestureRecognizer] = []
            OneHandedZoomDisabler.collectOneHandedZoom(in: window, into: &found)
            for recognizer in found where recognizer.isEnabled {
                recognizer.isEnabled = false
            }
            known = found.map { WeakRecognizer(value: $0) }
        }

        /// 把記住的手勢再關一次。地圖重建版面時會把它們啟用回來。
        func reapplyToKnownRecognizers() {
            var stillThere = false
            for entry in known {
                guard let recognizer = entry.value else { continue }
                stillThere = true
                if recognizer.isEnabled { recognizer.isEnabled = false }
            }
            // 手勢物件被整個換掉時，等下一次定期掃描重新找
            if !stillThere { known = [] }
        }
    }

    /// 收集 `view` 以下所有單指縮放手勢。
    static func collectOneHandedZoom(in view: UIView, into found: inout [UIGestureRecognizer]) {
        for recognizer in view.gestureRecognizers ?? [] where isOneHandedZoom(recognizer) {
            found.append(recognizer)
        }
        for subview in view.subviews {
            collectOneHandedZoom(in: subview, into: &found)
        }
    }

    /// 停用 `view` 以下所有單指縮放手勢，回傳停用了幾個。
    @discardableResult
    static func disableOneHandedZoom(in view: UIView) -> Int {
        var found: [UIGestureRecognizer] = []
        collectOneHandedZoom(in: view, into: &found)
        var disabled = 0
        for recognizer in found where recognizer.isEnabled {
            recognizer.isEnabled = false
            disabled += 1
        }
        return disabled
    }

    static func isOneHandedZoom(_ recognizer: UIGestureRecognizer) -> Bool {
        String(describing: type(of: recognizer)).contains("OneHandedZoom")
    }
}
