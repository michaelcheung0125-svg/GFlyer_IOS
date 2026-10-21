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
    /// 捷徑和開關本機通道的 App 回到 GFlyer 用的自訂 scheme，要和這個版本 `Info.plist` 的
    /// `CFBundleURLTypes` 一致。兩個版本不可以相同：兩個 App 都裝了的話，iOS 不保證
    /// 回呼打開的是哪一個。
    static var callbackScheme: String { get }

    /// 主畫面速度控制下面的提示，沒有時為 nil。照 Android 的 `speedHint`。
    static func speedHint(kilometresPerHour: Double) -> String?

    /// 共用的錯誤說明和狀態裏說到本機通道的句子。`SimulationError` 和 idevice backend 不在主執行緒，
    /// 所以放在這裏而不是 `LocalTunnel`。
    static var tunnelWording: TunnelWording { get }

    /// 設定頁「關於」的「使用教學」；nil 時不顯示。
    static var userGuideURL: URL? { get }

    /// 設定頁「關於」的「私隱政策」，用瀏覽器打開；nil 時不顯示。照 Android 每個版本的
    /// `EditionPrivacyText.policyUrl`：只有公開版有（審查指南 5.1.1），親友版沒有。
    static var privacyPolicyURL: URL? { get }

    /// 設定頁按「還原備份檔」時確認的說明。
    static var restoreConfirmationMessage: String { get }

    /// 設定頁備份和還原下面的說明。
    static var backupFormatNote: String { get }

    /// 要掛載 DDI、本機又沒有時：nil 就直接下載（親友版）；有值就不自己下載，丟出這句錯誤，
    /// 使用者要先在設定頁按下載（公開版：審查指南 4.2.3 要求第一次使用要下載的資源先說明大小
    /// 並詢問）。idevice backend 不在主執行緒，所以放在這裏。
    static var developerDiskImageMissingMessage: String? { get }

    associatedtype DeveloperDiskImageRows: View
    /// 設定頁「Developer Disk Image」section 的內容。
    @MainActor @ViewBuilder static func developerDiskImageRows(controller: SimulationController) -> DeveloperDiskImageRows

    /// 收藏的「國家 · 城市」反查送去的服務（GFlyer-Suite docs/features/region-labels.md）：親友版是 Nominatim，
    /// 公開版是 Apple 的地點服務（3.5a，DRIFT D33）。照 Android 每個版本的 `Edition.placeLookup`。
    static func makeRegionLabelSource() -> any RegionLabelSource

    /// 自動反查要先取得同意時（公開版，region-labels.md 3.10），同意說明和設定開關裏反查送去的服務；
    /// nil 是不用問（親友版）。
    static var regionLookupConsentService: String? { get }
}

/// 見 `EditionFeatures.tunnelWording`。每一句都是完整的句子，畫面上的字由版本決定。
struct TunnelWording {
    /// 目標 IP 不是有效的 IPv4 位址。
    let invalidDeviceIP: String
    /// 建立通道失敗，idevice 沒有給錯誤訊息時。
    let tunnelFailed: String
    /// CoreDevice/RSD 交握失敗時的建議。
    let handshakeHint: String
    /// 通道中斷或連不上時的建議。
    let reconnectHint: String
    /// 設定頁測試通道成功後主畫面的狀態。
    let verifiedStatus: String
}

/// 版本專屬功能在 App 執行期間的狀態，例如親友版的檢查新版和補錄步數。`GFlyerIOSApp` 建立一個，
/// 交給主畫面和設定頁。公開版的實作全部是空的，照 Android 公開版的 `NoScreenFeatures`。
///
/// 每一項都放在原本寫在共用畫面的同一個位置，所以親友版的畫面和提示的先後都和分版本之前相同。
@MainActor
protocol EditionModelFeatures: ObservableObject {
    associatedtype MainScreenPresentations: ViewModifier
    associatedtype NavigationBarButtons: View
    associatedtype SettingsPresentations: ViewModifier
    associatedtype SettingsSections: View

    init()

    /// 主畫面上版本專屬的提示和畫面，例如親友版的「有新版本」和從地圖工具列打開的畫面。
    /// 那些畫面用 `simulation` 傳送位置。
    func mainScreenPresentations(simulation: SimulationController, feedback: MainScreenFeedback) -> MainScreenPresentations

    /// 主畫面導覽列右邊、「設定」前面的按鈕，例如親友版的留言板。
    @ViewBuilder var navigationBarButtons: NavigationBarButtons { get }

    /// 版本專屬的提示正在顯示。主畫面升級後只出現一次的提示要等它關掉，免得互相擋掉。
    var isPresentingAlert: Bool { get }

    /// 地圖工具列上版本專屬的按鈕，接在「已儲存路線」後面。
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

/// 本機通道：送往目標 IP 的連線經它回到這支 iPhone 的開發服務。每個版本的資料夾提供一個
/// `LocalTunnel`（親友版請使用者另外安裝的 App 開關通道；公開版到 docs/APP_STORE_PLAN.md
/// 第 12 項才有自己的），`SimulationController` 建立一個（`vpn`）。共用的程式只經這些成員碰通道，
/// 說明文字也由它給，每個版本說的是自己的通道。
@MainActor
protocol LocalTunnelFeatures: ObservableObject {
    associatedtype SettingsRows: View
    associatedtype RecoveryRows: View

    /// 查路由用的目標 IP，`SimulationController.deviceIP` 一變就同步過來。
    var deviceIP: String { get set }

    /// 重新查一次通道的狀態。設定頁打開時呼叫。
    func refreshStatus()

    /// 按開始時要先開通道的話，回傳開通道期間主畫面的狀態；不用（通道已開，或這個版本
    /// 不代使用者開）回傳 nil，直接開始。
    func statusWhileConnectingBeforeStart() -> String?

    /// 開通道，真的開了回傳 nil；開不了回傳要顯示的狀態和錯誤。
    func connectBeforeStart() async -> TunnelFailure?

    /// 完整清除成功並驗證之後。使用者要的話關通道並回傳結果；沒有嘗試回傳 nil。
    func disconnectAfterFullClearIfWanted() async -> TunnelClosing?

    /// 完整清除後 iOS 仍回報模擬座標、通道又沒有關掉時的說明；nil 用一般的說明。
    static var stillSimulatedWhileOpenMessage: String? { get }

    /// 設定頁通道 section 的標題。
    static var settingsTitle: String { get }

    /// 設定頁通道 section 裏版本專屬的列，放在「目標 IP」前面。
    @ViewBuilder func settingsRows(controller: SimulationController) -> SettingsRows

    /// 設定頁測試通道的按鈕。
    static var testButtonTitle: String { get }

    /// 設定頁通道 section 最後的說明。
    static var deviceIPHint: String { get }

    /// 設定頁「恢復」裏「完整清除模擬定位」下面的列。
    @ViewBuilder func recoveryRows(isClearing: Bool) -> RecoveryRows

    /// 設定頁「操作順序」匯入 Pairing File 之後的步驟，連編號。
    static var usageSteps: [String] { get }
}

/// 開不了通道時主畫面的狀態和「操作失敗」的錯誤。
struct TunnelFailure {
    let status: String
    let message: String
}

/// 完整清除後關通道的結果。`message` 接在驗證結果的下一行。
struct TunnelClosing {
    let closed: Bool
    let message: String
}
