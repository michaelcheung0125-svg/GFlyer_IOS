import SwiftUI

/// 親友版和公開版不同的地方。
///
/// 每個版本的資料夾（`GFlyerIOS/Family/`、`GFlyerIOS/Public/`）各有一個
/// `enum Edition: EditionFeatures` 和一個 `final class EditionModel: EditionModelFeatures`，
/// 兩個 App target 各自只編譯其中一套，所以共用的程式直接寫 `Edition.xxx`、`EditionModel`。
/// 這兩個 protocol 保證兩個版本有相同的成員：哪個版本少了一項，那個版本就編譯不過。
/// 照 Android 每個版本的 `object Edition`（GFlyer 的 `app/src/<版本>/java/com/geopilot/app/edition/Edition.kt`）。
///
/// 共用的程式只經這裏碰版本專屬的東西（docs/APP_STORE_PLAN.md 第 8 項）。
protocol EditionFeatures {
    /// 捷徑和 LocalDevVPN 回到 App 用的自訂 scheme，要和這個版本 `Info.plist` 的
    /// `CFBundleURLTypes` 一致。兩個版本不可以相同：兩個 App 都裝了的話，iOS 不保證
    /// 回呼打開的是哪一個。
    static var callbackScheme: String { get }

    /// 主畫面速度控制下面的提示，沒有時為 nil。照 Android 的 `speedHint`。
    static func speedHint(kilometresPerHour: Double) -> String?
}

/// 版本專屬功能在 App 執行期間的狀態，例如親友版的檢查新版和補錄步數。`GFlyerIOSApp` 建立一個，
/// 交給主畫面和設定頁。公開版的實作全部是空的，照 Android 公開版的 `NoScreenFeatures`。
///
/// 每一項都放在原本寫在共用畫面的同一個位置，所以親友版的畫面和提示的先後都和分版本之前相同。
@MainActor
protocol EditionModelFeatures: ObservableObject {
    associatedtype MainScreenPresentations: ViewModifier
    associatedtype SettingsPresentations: ViewModifier
    associatedtype SettingsSections: View

    init()

    /// 主畫面上版本專屬的提示和畫面，例如親友版的「有新版本」和從地圖工具列打開的畫面。
    /// 那些畫面用 `simulation` 傳送位置。
    func mainScreenPresentations(simulation: SimulationController, feedback: MainScreenFeedback) -> MainScreenPresentations

    /// 版本專屬的提示正在顯示。主畫面升級後只出現一次的提示要等它關掉，免得互相擋掉。
    var isPresentingAlert: Bool { get }

    /// 地圖工具列上版本專屬的按鈕，接在「分享到留言板」後面。
    func mapToolItems(feedback: MainScreenFeedback) -> [MapToolItem]

    /// 設定頁上版本專屬的提示和畫面。
    var settingsPresentations: SettingsPresentations { get }

    /// 設定頁裏版本專屬的 section，放在「繞圈設定」之後。
    @ViewBuilder var settingsSections: SettingsSections { get }

    /// 打開 App 的網址是這個版本的功能的，就處理並回傳 true，例如親友版補錄的捷徑回呼。
    /// 回傳 false 的交給共用的功能（飛航模式輔助）。
    func handleOpenURL(_ url: URL) -> Bool

    /// App 回到前景時。CI 截圖時不呼叫（`MainView.isCapturingScreenshots`）。
    func appDidBecomeActive()
}

/// 主畫面讓版本專屬的功能回報結果用的兩個方法。
struct MainScreenFeedback {
    /// 畫面頂端顯示一下就消失的提示。
    let announce: (String) -> Void
    /// 「操作失敗」提示。
    let reportError: (String) -> Void
}

/// 地圖工具列的一個按鈕。共用的和版本專屬的按鈕都用它，畫法相同，兩個一列。
struct MapToolItem: Identifiable {
    let id: String
    let icon: String
    /// VoiceOver 讀的名稱。
    let label: String
    var tint: Color?
    /// 轉圈代替圖示，例如定位中。
    var isBusy = false
    /// 右上角的小字，例如「NEW」。
    var badge: String?
    let action: () -> Void
}
