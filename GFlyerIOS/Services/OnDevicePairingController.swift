import BackgroundTasks
import Combine
import Foundation
import UIKit
import UserNotifications

enum PairingHostEngineFactory {
    /// 預覽版沒有 idevice，回傳 nil，設定頁就不顯示「在這支 iPhone 上配對」。
    static func makeDefault() -> (() throws -> PairingHostEngine)? {
        #if GFLYER_IDEVICE
        return { try IdevicePairingHostEngine() }
        #else
        return nil
        #endif
    }
}

/// 「在這支 iPhone 上配對」（docs/APP_STORE_PLAN.md 第 4 項）。iOS 27 起，iPhone 可以在「設定」的
/// 開發者模式頁自己開始配對：GFlyer 當配對主機，使用者輸入 GFlyer 給的 PIN，GFlyer 收到配對檔就存起來，
/// 不用電腦。網路的部分在 `PairingHostSession`。
///
/// 使用者按下按鈕後要切去「設定」，GFlyer 會進入背景。為了在背景繼續等，用 iOS 26 起的
/// `BGContinuedProcessingTask`：它是給使用者自己開始、要在背景做完的工作用的，系統會顯示進度。
/// 不用無聲音訊或背景定位之類的做法（審查指南 2.5.4）。PIN 用本機通知顯示，在「設定」裏就看得到。
///
/// 由 SimulationController 持有而不是設定頁，關掉設定頁時配對才不會中斷。
@MainActor
final class OnDevicePairingController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case waitingForDevice
        case deviceConnected
        case enterPIN(String)
        case succeeded
        case failed(String)

        var isActive: Bool {
            switch self {
            case .starting, .waitingForDevice, .deviceConnected, .enterPIN: return true
            case .idle, .succeeded, .failed: return false
            }
        }
    }

    /// 等「設定」完成配對的時間，到了就停止並說明。說明文字也用到，所以不限主執行緒。
    nonisolated static let timeoutSeconds = 300
    nonisolated static let continuedTaskTitle = "在這支 iPhone 上配對"
    private static let pinNotificationIdentifier = "gflyer.on-device-pairing.pin"
    private static let finishedNotificationIdentifier = "gflyer.on-device-pairing.finished"

    @Published private(set) var phase: Phase = .idle
    /// 上一次連線沒有配對成功的原因（例如 PIN 打錯）。還在等下一次連線時顯示，結束時清掉。
    @Published private(set) var lastAttemptMessage: String?
    /// 還沒有「本機網路」權限：沒有它，「設定」找不到 GFlyer。允許之後系統會自己繼續。
    @Published private(set) var needsLocalNetworkPermission = false
    @Published private(set) var secondsRemaining = 0

    /// 只有 idevice 版、iOS 27 以上才有這個功能。
    let isAvailable: Bool

    private let pairingStore: PairingFileStore
    private let makeEngine: (() throws -> PairingHostEngine)?
    private var session: PairingHostSession?
    /// 每次開始加一。舊的 session 和背景工作送來的事件比對不上就丟掉。
    private var generation = 0
    private var endReason: EndReason?
    private var deadline = Date.distantPast
    private var countdown: Task<Void, Never>?
    /// iOS 26 起是 `BGContinuedProcessingTask`。stored property 不能標 @available，所以存成 AnyObject。
    private var continuedTask: AnyObject?
    private var continuedTaskSubtitle = ""
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private enum EndReason {
        case userCancelled
        case timedOut
        /// 使用者在系統顯示的進度（Live Activity）上按了停止，或 iOS 收回了背景執行時間。
        /// 兩種都只會呼叫 expirationHandler，分不出來。
        case backgroundExpired
    }

    init(
        pairingStore: PairingFileStore,
        makeEngine: (() throws -> PairingHostEngine)? = PairingHostEngineFactory.makeDefault()
    ) {
        self.pairingStore = pairingStore
        self.makeEngine = makeEngine
        if #available(iOS 27, *) {
            isAvailable = makeEngine != nil
        } else {
            isAvailable = false
        }
    }

    func start() {
        guard isAvailable, !phase.isActive, let makeEngine else { return }
        generation += 1
        let generation = self.generation
        endReason = nil
        lastAttemptMessage = nil
        needsLocalNetworkPermission = false
        deadline = Date().addingTimeInterval(TimeInterval(Self.timeoutSeconds))
        secondsRemaining = Self.timeoutSeconds
        continuedTaskSubtitle = "正在準備"
        phase = .starting

        requestNotificationPermission()
        beginBackgroundExecution(generation: generation)

        let session = PairingHostSession(
            makeEngine: makeEngine,
            onEvent: { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.handle(event, generation: generation) }
                }
            },
            onFinish: { [weak self] outcome in
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.finish(outcome, generation: generation) }
                }
            }
        )
        self.session = session
        session.start()
        startCountdown(generation: generation)
    }

    func cancel() {
        end(.userCancelled, generation: generation)
    }

    /// 取消、逾時或背景時間用完，都經這裏讓 session 停下來；結果由 `finish` 處理。
    private func end(_ reason: EndReason, generation: Int) {
        guard generation == self.generation, phase.isActive, let session else { return }
        if endReason == nil { endReason = reason }
        session.cancel()
    }

    private func handle(_ event: PairingHostSession.Event, generation: Int) {
        guard generation == self.generation, phase.isActive else { return }
        switch event {
        case .advertising:
            needsLocalNetworkPermission = false
            if phase == .starting { phase = .waitingForDevice }
            updateContinuedTask(subtitle: "等待「設定」連線")
        case .waitingForLocalNetworkPermission:
            needsLocalNetworkPermission = true
        case .deviceConnected:
            phase = .deviceConnected
            updateContinuedTask(subtitle: "「設定」已連線")
        case let .pin(pin):
            phase = .enterPIN(pin)
            postNotification(
                identifier: Self.pinNotificationIdentifier,
                title: "GFlyer 配對",
                body: "在「設定」輸入 PIN：\(pin)"
            )
            updateContinuedTask(subtitle: "PIN：\(pin)")
        case let .attemptFailed(message):
            lastAttemptMessage = message
            phase = .waitingForDevice
            removeNotifications([Self.pinNotificationIdentifier])
            updateContinuedTask(subtitle: "等待「設定」連線")
        }
    }

    private func finish(_ outcome: PairingHostOutcome, generation: Int) {
        guard generation == self.generation else { return }
        session = nil
        countdown?.cancel()
        countdown = nil
        removeNotifications([Self.pinNotificationIdentifier])

        let succeeded: Bool
        switch outcome {
        case let .paired(result):
            do {
                try pairingStore.save(result.pairingFile)
                phase = .succeeded
                succeeded = true
            } catch {
                phase = .failed("配對成功了，但無法儲存 Pairing File：\(error.localizedDescription)")
                succeeded = false
            }
        case .cancelled:
            phase = Self.phase(afterCancelling: endReason, lastAttempt: lastAttemptMessage)
            succeeded = false
        case let .failed(message):
            phase = .failed(message)
            succeeded = false
        }
        lastAttemptMessage = nil
        needsLocalNetworkPermission = false

        if UIApplication.shared.applicationState != .active, endReason != .userCancelled {
            postNotification(
                identifier: Self.finishedNotificationIdentifier,
                title: succeeded ? "GFlyer 配對完成" : "GFlyer 配對沒有成功",
                body: succeeded ? "已存好新的 Pairing File，可以回到 GFlyer。" : "回到 GFlyer 查看原因。"
            )
        }
        endBackgroundExecution(success: succeeded)
    }

    /// 使用者自己取消時回到一開始的樣子；逾時和背景時間用完要說明。
    private static func phase(afterCancelling reason: EndReason?, lastAttempt: String?) -> Phase {
        switch reason {
        case nil, .userCancelled?:
            return .idle
        case .timedOut?:
            var message = "\(timeoutSeconds / 60) 分鐘內沒有完成配對，已經停止。要再試，請再按「\(continuedTaskTitle)」。"
            if let lastAttempt { message += "\n上一次的錯誤：\(lastAttempt)" }
            return .failed(message)
        case .backgroundExpired?:
            return .failed("配對在背景被停止了：可能是在系統顯示的配對進度上按了停止，或 iOS 收回了 GFlyer 的背景執行時間。要再試，請再按「\(continuedTaskTitle)」。")
        }
    }

    // MARK: - 倒數

    private func startCountdown(generation: Int) {
        countdown?.cancel()
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick(generation: generation)
            }
        }
    }

    private func tick(generation: Int) {
        guard generation == self.generation, phase.isActive else { return }
        secondsRemaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
        updateContinuedTaskProgress()
        if secondsRemaining == 0 { end(.timedOut, generation: generation) }
    }

    // MARK: - 背景執行

    private func beginBackgroundExecution(generation: Int) {
        endFallbackBackgroundTask()
        // 送出 BGContinuedProcessingTask 到它開始之間，以及它被拒絕時，至少還有這段時間。
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: Self.continuedTaskTitle) { [weak self] in
            MainActor.assumeIsolated { self?.endFallbackBackgroundTask() }
        }
        if #available(iOS 26, *) {
            submitContinuedTask(generation: generation)
        }
    }

    @available(iOS 26, *)
    private func submitContinuedTask(generation: Int) {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        guard let identifier = Self.continuedTaskIdentifier(permitted: permitted) else { return }
        // BGContinuedProcessingTask 可以在使用者按下按鈕時才註冊，不用在啟動時。每次用新的識別碼，
        // 因為同一個識別碼註冊第二次會出錯。
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.attach(continued, generation: generation)
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: Self.continuedTaskTitle,
            subtitle: continuedTaskSubtitle
        )
        // 不能馬上開始就不要排隊：配對要在使用者等的時候進行。
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 只剩前景和 beginBackgroundTask 的時間。
        }
    }

    /// Info.plist 的 `BGTaskSchedulerPermittedIdentifiers` 有一項 `<bundle id>.pairing.*`。前綴從這份清單讀，
    /// 不用執行時的 bundle id，因為重簽的工具可能改掉 bundle id，卻不會改這份清單。
    nonisolated static func continuedTaskIdentifier(permitted: [String]?, uuid: UUID = UUID()) -> String? {
        guard let wildcard = permitted?.first(where: { $0.hasSuffix(".pairing.*") }) else { return nil }
        return String(wildcard.dropLast()) + uuid.uuidString
    }

    @available(iOS 26, *)
    private func attach(_ task: BGContinuedProcessingTask, generation: Int) {
        guard generation == self.generation, phase.isActive else {
            task.setTaskCompleted(success: false)
            return
        }
        continuedTask = task
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.end(.backgroundExpired, generation: generation) }
            }
        }
        // 沒有回報進度的工作會被系統結束。等待本身沒有工作量，所以用經過的秒數當進度。
        task.progress.totalUnitCount = Int64(Self.timeoutSeconds)
        updateContinuedTaskProgress()
        task.updateTitle(Self.continuedTaskTitle, subtitle: continuedTaskSubtitle)
    }

    private func updateContinuedTask(subtitle: String) {
        continuedTaskSubtitle = subtitle
        if #available(iOS 26, *), let task = continuedTask as? BGContinuedProcessingTask {
            task.updateTitle(Self.continuedTaskTitle, subtitle: subtitle)
        }
    }

    private func updateContinuedTaskProgress() {
        if #available(iOS 26, *), let task = continuedTask as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = Int64(Self.timeoutSeconds - secondsRemaining)
        }
    }

    private func endBackgroundExecution(success: Bool) {
        if #available(iOS 26, *), let task = continuedTask as? BGContinuedProcessingTask {
            if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
            task.setTaskCompleted(success: success)
        }
        continuedTask = nil
        endFallbackBackgroundTask()
    }

    private func endFallbackBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - 通知

    private func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func postNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }

    private func removeNotifications(_ identifiers: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
