import Combine
import Foundation

/// 公開版首次設定引導的一步（docs/APP_STORE_PLAN.md 第 14 項）。次序就是做的次序，一步一個畫面。
enum FirstSetupStep: Int, CaseIterable {
    case showDeveloperMode
    case enableDeveloperMode
    case pair
    case tunnel
    case developerDiskImage
    case teleport
    case restore

    /// 畫面上的「第幾步」。
    var number: Int { rawValue + 1 }
    var next: FirstSetupStep? { Self(rawValue: rawValue + 1) }
    var previous: FirstSetupStep? { Self(rawValue: rawValue - 1) }
}

/// 引導查得到的裝置狀態。
struct FirstSetupReadiness: Equatable {
    var hasPairingFile: Bool
    var isTunnelUp: Bool
    var hasDeveloperDiskImage: Bool

    /// 這一步做完了沒有；nil 是 App 查不到（開發者模式、傳送、清除），由使用者自己看。
    func isDone(_ step: FirstSetupStep) -> Bool? {
        switch step {
        case .pair: return hasPairingFile
        case .tunnel: return isTunnelUp
        case .developerDiskImage: return hasDeveloperDiskImage
        case .showDeveloperMode, .enableDeveloperMode, .teleport, .restore: return nil
        }
    }

    /// 查得到的步驟要做完才可以按「下一步」：後面的步驟都要用到它們。
    func canGoForward(from step: FirstSetupStep) -> Bool { isDone(step) ?? true }
}

/// 首次設定引導開到哪一步、從哪裏打開。第一次打開 App 時自己打開；第 2 步重新開機之後再打開 GFlyer，
/// 回到同一步。按「完成」或「關閉」之後不再自己打開，要從設定頁「首次設定」打開。
@MainActor
final class FirstSetupGuide: ObservableObject {
    /// 疊在主畫面上。
    @Published var isPresentedOnMainScreen = false
    /// 疊在設定頁上。
    @Published var isPresentedInSettings = false
    @Published private(set) var step: FirstSetupStep {
        didSet { defaults.set(step.rawValue, forKey: Self.stepKey) }
    }
    /// 按過「完成」或「關閉」。
    private(set) var isDismissed: Bool {
        didSet { defaults.set(isDismissed, forKey: Self.dismissedKey) }
    }

    private let defaults: UserDefaults
    private static let stepKey = "gflyer.first-setup.step"
    private static let dismissedKey = "gflyer.first-setup.dismissed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        step = FirstSetupStep(rawValue: defaults.integer(forKey: Self.stepKey)) ?? .showDeveloperMode
        isDismissed = defaults.bool(forKey: Self.dismissedKey)
    }

    var isPresented: Bool { isPresentedOnMainScreen || isPresentedInSettings }

    /// App 打開時。預覽模式控制不了 iPhone，不自己打開。
    func presentOnLaunchIfNeeded(canControlDevice: Bool) {
        guard canControlDevice, !isDismissed, !isPresented else { return }
        isPresentedOnMainScreen = true
    }

    /// 設定頁「首次設定」的「一步一步設定」。
    func presentFromSettings() {
        isPresentedInSettings = true
    }

    func goForward() {
        if let next = step.next { step = next }
    }

    func goBack() {
        if let previous = step.previous { step = previous }
    }

    /// 「關閉」，或把畫面往下拉關掉。停在現在這一步，下次從設定頁打開時接着做。
    func close() {
        isDismissed = true
        isPresentedOnMainScreen = false
        isPresentedInSettings = false
    }

    /// 最後一步的「完成」。下次從設定頁打開時由第 1 步開始。
    func finish() {
        step = .showDeveloperMode
        close()
    }
}

/// 首次設定引導的字。iPhone 畫面上的名稱照 2026-10-20 iOS 27 實機（香港繁體中文）的截圖
/// （docs/APP_STORE_PLAN.md 第一階段的「iOS 27 實機畫面」）；還沒有截圖的畫面（開啟開發者模式和重新開機的提示、
/// 加入 VPN 設定的詢問）不寫按鈕的名稱，見 docs/APP_STORE_PLAN.md「第 14 項的進度」。
/// GFlyer 自己的按鈕和結論直接用畫面上的同一個常數。
enum FirstSetupText {
    static let navigationTitle = "首次設定"
    /// 設定頁「首次設定」打開引導的按鈕。
    static let entryTitle = "一步一步設定"
    static let entrySubtitle = "開發者模式、配對、本機通道和 DDI，第一次使用時照着做一次"
    static let closeButton = "關閉"
    static let backButton = "上一步"
    static let nextButton = "下一步"
    static let finishButton = "完成"
    static let reopenNote = "關閉之後，可以在設定頁「首次設定」按「\(entryTitle)」再打開。"
    /// 第 1 步的按鈕：和「在這支 iPhone 上配對」是同一個動作。
    static let showDeveloperModeButton = "顯示開發者模式"
    /// 第 1 步按鈕下面的說明：按鈕也開始了配對，但要等開發者模式開了、重新開機之後才配對。
    static let showDeveloperModeNote = "現在不用配對：開啟開發者模式、重新開機之後，第 3 步才配對。"
    static let developerModePath = "「設定」>「私隱與保安」>「開發者模式」"

    static func progress(_ step: FirstSetupStep) -> String {
        "第 \(step.number) 步，共 \(FirstSetupStep.allCases.count) 步"
    }

    /// `pairsOnDevice`：iOS 27 以上，可以在手機上配對（`OnDevicePairingController.isAvailable`）。
    static func title(_ step: FirstSetupStep, pairsOnDevice: Bool) -> String {
        switch step {
        case .showDeveloperMode: return showDeveloperModeButton
        case .enableDeveloperMode: return "開啟開發者模式並重新開機"
        case .pair: return pairsOnDevice ? OnDevicePairingController.continuedTaskTitle : "匯入 Pairing File"
        case .tunnel: return "開啟本機通道"
        case .developerDiskImage: return "下載 DDI"
        case .teleport: return "傳送一次並確認"
        case .restore: return "清除並恢復真實位置"
        }
    }

    /// 這一步要做的事，一句一段。
    static func instructions(_ step: FirstSetupStep, pairsOnDevice: Bool) -> [String] {
        switch step {
        case .showDeveloperMode:
            guard pairsOnDevice else {
                return [
                    "GFlyer 要用 iPhone 的開發者模式傳送位置。",
                    "iOS 26 或以下，\(developerModePath)要用電腦才叫得出來。把 iPhone 更新到 iOS 27 或以上，就可以在手機上完成，不用電腦。",
                    "已經看到「開發者模式」的話，按「\(nextButton)」。",
                ]
            }
            return [
                "GFlyer 要用 iPhone 的開發者模式傳送位置。從 App Store 安裝的 App，「設定」不會自己顯示「開發者模式」。",
                "1. 按下面的「\(showDeveloperModeButton)」。GFlyer 會開始等待配對，最多 \(OnDevicePairingController.timeoutSeconds / 60) 分鐘。",
                "2. 打開 iPhone 的「設定」>「私隱與保安」，在「保安」一組找「開發者模式」。",
                "3. 找到了就回到 GFlyer，按「\(nextButton)」。",
                "「開發者模式」右邊已經寫「開啟」的話，開發者模式已經開了，第 2 步不用做。",
                "按了之後還是找不到「開發者模式」，請到設定頁「關於」按「聯絡我們」告訴我們。",
            ]
        case .enableDeveloperMode:
            return [
                "1. 打開\(developerModePath)，打開最上面的開關。",
                "2. 照 iPhone 的提示重新開機。",
                "3. 重新開機後解鎖 iPhone，iPhone 會再問一次要不要開啟開發者模式：選開啟，再輸入 iPhone 的密碼。",
                "4. 打開 GFlyer，會回到這一步，按「\(nextButton)」。",
                "「開發者模式」右邊已經寫「開啟」的話，不用再做，直接按「\(nextButton)」。",
                pairsOnDevice
                    ? "「私隱與保安」裏沒有「開發者模式」的話，按「\(backButton)」，再按一次「\(showDeveloperModeButton)」。"
                    : "「私隱與保安」裏沒有「開發者模式」的話，要先用電腦叫出來，見上一步。",
            ]
        case .pair:
            guard pairsOnDevice else {
                return [
                    "iOS 26 或以下不能在手機上配對：",
                    "1. 用電腦產生這支 iPhone 的 Pairing File。",
                    "2. 把檔案傳到 iPhone，例如存進「檔案」。",
                    "3. 按下面的「匯入 Pairing File」，選這個檔。",
                    "「Pairing File」變成「已匯入」後，按「\(nextButton)」。",
                ]
            }
            return [
                "這支 iPhone 可以在手機上配對，不用電腦。照下面的步驟做。",
                "配對完成後「Pairing File」會變成「已匯入」，再按「\(nextButton)」。",
                "重裝 GFlyer 之前匯出過 Pairing File 的話，也可以按「匯入 Pairing File」選那個檔。",
            ]
        case .tunnel:
            return [
                "1. 按「開啟本機通道」。",
                "2. 第一次開啟時，iOS 會詢問可否加入 VPN 設定，要允許才能使用。",
                "3. 「通道狀態」變成「已連線」後，按「\(nextButton)」。",
            ]
        case .developerDiskImage:
            return [
                "1. 按「\(Edition.developerDiskImageDownloadTitle)」。iPhone 要連得上網絡。",
                "2. 「DDI 狀態」變成「已下載」後，按「\(nextButton)」。",
            ]
        case .teleport:
            return [
                "試傳送一次，確認其他 App 收到的是 GFlyer 送出的位置。",
                "1. 按下面的「\(LocationCheckText.title)」。",
                "2. 在那一頁按「\(LocationCheckText.teleportButton)」。",
                "3. 等幾秒，結論變成「\(LocationCheckVerdict.matches.text)」就成功了。",
                "結論寫「\(LocationCheckVerdict.needsPermission.text)」的話，先按「\(LocationCheckText.grantPermissionButton)」。",
                "也可以打開 iPhone 的「地圖」App，看藍點是不是在選取的位置。",
                "選取的位置是主畫面地圖上選的點。之後在地圖上選別的點，再按開始就可以。",
            ]
        case .restore:
            return [
                "測試完，要讓其他 App 回到真實位置時：",
                "1. 按「完整清除模擬定位」，等「清除結果」出現。",
                "2. 按「\(LocationCheckText.title)」，結論是「\(LocationCheckVerdict.realLocation.text)」就完成了。",
                "之後在設定頁的「恢復」也可以按「完整清除模擬定位」。",
            ]
        }
    }

    /// 「下一步」按不到時的說明。
    static func waitingNote(_ step: FirstSetupStep) -> String? {
        switch step {
        case .pair: return "「Pairing File」變成「已匯入」之後，才能按「\(nextButton)」。"
        case .tunnel: return "「通道狀態」變成「已連線」之後，才能按「\(nextButton)」。"
        case .developerDiskImage: return "「DDI 狀態」變成「已下載」之後，才能按「\(nextButton)」。"
        case .showDeveloperMode, .enableDeveloperMode, .teleport, .restore: return nil
        }
    }
}
