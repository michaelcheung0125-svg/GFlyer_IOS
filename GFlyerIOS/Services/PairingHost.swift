import Darwin
import dnssd
import Foundation

// 「在這支 iPhone 上配對」的網路部分（docs/APP_STORE_PLAN.md 第 4 項）。
//
// iOS 27 起，iPhone 可以在「設定」裏自己開始配對：它用 Bonjour 找
// `_remotepairing-pairable-host._tcp`，連上去之後由對方當配對主機。GFlyer 在同一支 iPhone 上當這個主機。
// 分工照上游 idevice 的 `ffi/src/pairing_host.rs`：Rust 只負責配對本身（產生主機身分、跑 SRP），
// 開 socket、廣播和 accept 都在這裏用系統 API 做。不要改用上游的 `pairable_host_accept`：
// 它用 Rust 自己送 multicast 封包，iOS App 要 Apple 個別核准的 multicast 權限才可以這樣做。
//
// 這個檔案不依賴 idevice，預覽 scheme 也會編譯，測試用假的 engine 驗證流程。

/// 配對主機的身分和配對本身。idevice 版是 `IdevicePairingHostEngine`。
/// 只在 `PairingHostSession` 自己的執行緒上使用。
protocol PairingHostEngine: AnyObject {
    /// Bonjour 的服務名稱，也是配對檔裏主機的識別碼。
    var serviceName: String { get }
    /// 要放進 Bonjour TXT 的鍵值，包含裝置用來核對主機的 `authTag`。
    var txtRecord: [String: String] { get }
    /// 跑完一次配對。會一直擋住，直到配對成功、失敗或連線被關掉。
    /// `onPIN` 在裝置要求 PIN 時呼叫，使用者要在「設定」輸入這組數字。
    func pair(overConnection socket: Int32, onPIN: @escaping (String) -> Void) throws -> PairingHostResult
}

struct PairingHostResult: Equatable, Sendable {
    /// 配對檔的內容（XML plist），格式和匯入的 Pairing File 相同。
    let pairingFile: Data
}

enum PairingHostOutcome: Equatable, Sendable {
    case paired(PairingHostResult)
    case cancelled
    case failed(String)
}

enum PairingHostError: LocalizedError, Equatable {
    case cancelled
    case socket(call: String, code: Int32)
    case advertise(code: Int32)
    case txtRecord(String)
    case idevice(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消配對。"
        case let .socket(call, code):
            return "無法開啟配對用的連線（\(call) 失敗：\(String(cString: strerror(code)))）。"
        case let .advertise(code):
            return "無法讓「設定」找到 GFlyer（Bonjour 錯誤 \(code)）。"
        case let .txtRecord(detail):
            return "配對主機的資料格式不對：\(detail)"
        case let .idevice(message):
            return message
        }
    }
}

// MARK: - TXT

/// Bonjour TXT 的編碼（RFC 6763 第 6 節）：每一項是一個長度位元組加上 `key=value`。
enum PairingHostTXTRecord {
    /// 上游 `pairable_host_prepare` 交回的 TXT 是一份 XML plist，鍵和值都是字串。
    static func dictionary(fromPropertyList data: Data) throws -> [String: String] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = object as? [String: Any] else {
            throw PairingHostError.txtRecord("不是 dictionary")
        }
        var result: [String: String] = [:]
        for (key, value) in dictionary {
            guard let string = value as? String else {
                throw PairingHostError.txtRecord("\(key) 的值不是字串")
            }
            result[key] = string
        }
        return result
    }

    /// 依鍵排序，同一份資料每次編出來都一樣。
    static func encode(_ entries: [String: String]) throws -> Data {
        var data = Data()
        for key in entries.keys.sorted() {
            guard !key.isEmpty, !key.contains("=") else {
                throw PairingHostError.txtRecord("鍵「\(key)」不合法")
            }
            let entry = Data("\(key)=\(entries[key] ?? "")".utf8)
            guard entry.count <= Int(UInt8.max) else {
                throw PairingHostError.txtRecord("\(key) 超過 255 位元組")
            }
            data.append(UInt8(entry.count))
            data.append(entry)
        }
        guard data.count <= Int(UInt16.max) else {
            throw PairingHostError.txtRecord("整份超過 65535 位元組")
        }
        return data
    }
}

// MARK: - Socket

/// 配對用的 TCP listener。用 IPv6 的 socket 並關掉 `IPV6_V6ONLY`，IPv4 和 IPv6 的連線都收得到：
/// 還不知道「設定」會用哪一種位址連進來。port 由系統挑。
final class PairingHostListener {
    let port: UInt16
    private let socketDescriptor: Int32
    private var isStopped = false

    init() throws {
        let descriptor = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else { throw PairingHostError.socket(call: "socket", code: errno) }
        do {
            // init 還沒初始化完所有屬性，用型別名稱而不是 Self 呼叫。
            try PairingHostListener.setOption(descriptor, IPPROTO_IPV6, IPV6_V6ONLY, 0, name: "IPV6_V6ONLY")
            try PairingHostListener.setOption(descriptor, SOL_SOCKET, SO_REUSEADDR, 1, name: "SO_REUSEADDR")

            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_addr = in6addr_any
            address.sin6_port = 0
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            guard bound == 0 else { throw PairingHostError.socket(call: "bind", code: errno) }
            guard listen(descriptor, 4) == 0 else { throw PairingHostError.socket(call: "listen", code: errno) }

            var actual = sockaddr_in6()
            var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
            let named = withUnsafeMutablePointer(to: &actual) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(descriptor, $0, &length)
                }
            }
            guard named == 0 else { throw PairingHostError.socket(call: "getsockname", code: errno) }
            port = UInt16(bigEndian: actual.sin6_port)
            socketDescriptor = descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit { stop() }

    /// 最多等 `timeout` 秒。有連線時回傳它的 file descriptor，由呼叫端負責關掉；沒有連線時回傳 nil。
    func waitForConnection(timeout: TimeInterval) throws -> Int32? {
        var descriptor = pollfd(fd: socketDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Int32(timeout * 1000))
        if ready < 0 {
            if errno == EINTR { return nil }
            throw PairingHostError.socket(call: "poll", code: errno)
        }
        guard ready > 0 else { return nil }

        let connection = Darwin.accept(socketDescriptor, nil, nil)
        if connection < 0 {
            if errno == EINTR || errno == EAGAIN || errno == ECONNABORTED { return nil }
            throw PairingHostError.socket(call: "accept", code: errno)
        }
        // 對方先斷線時，寫入會送出 SIGPIPE，預設會直接結束整個 App。Rust 那邊是從這個 fd 複製出去的，
        // 共用同一個 socket，所以在這裏設一次就夠了。
        do {
            try Self.setOption(connection, SOL_SOCKET, SO_NOSIGPIPE, 1, name: "SO_NOSIGPIPE")
        } catch {
            Darwin.close(connection)
            throw error
        }
        return connection
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        Darwin.close(socketDescriptor)
    }

    private static func setOption(
        _ descriptor: Int32,
        _ level: Int32,
        _ option: Int32,
        _ value: Int32,
        name: String
    ) throws {
        var value = value
        guard setsockopt(descriptor, level, option, &value, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw PairingHostError.socket(call: "setsockopt \(name)", code: errno)
        }
    }
}

// MARK: - Bonjour

enum PairingHostAdvertiserState: Equatable, Sendable {
    case registered
    /// 使用者還沒允許、或拒絕了「本機網路」權限。允許之後系統會繼續註冊。
    case waitingForPermission
    case failed(code: Int32)
}

protocol PairingHostAdvertising: AnyObject {
    func stop()
}

typealias PairingHostAdvertiserFactory = (
    _ name: String,
    _ port: UInt16,
    _ txtRecord: Data,
    _ onState: @escaping @Sendable (PairingHostAdvertiserState) -> Void
) throws -> PairingHostAdvertising

/// 用 dns_sd 註冊 Bonjour 服務。不用 `NetService`：它已經被標為 deprecated，
/// 而且 dns_sd 就是它底下用的 API。callback 都在自己的 queue 上，`stop()` 也在同一個 queue 上拆掉。
final class PairingHostAdvertiser: PairingHostAdvertising, @unchecked Sendable {
    static let serviceType = "_remotepairing-pairable-host._tcp"

    private static let noError = DNSServiceErrorType(kDNSServiceErr_NoError)
    /// kDNSServiceErr_PolicyDenied：沒有「本機網路」權限。
    private static let policyDenied: DNSServiceErrorType = -65570

    private let queue = DispatchQueue(label: "com.geopilot.gflyer.pairing-host.bonjour")
    private let onState: @Sendable (PairingHostAdvertiserState) -> Void
    private var service: DNSServiceRef?

    static func make(
        name: String,
        port: UInt16,
        txtRecord: Data,
        onState: @escaping @Sendable (PairingHostAdvertiserState) -> Void
    ) throws -> PairingHostAdvertising {
        let advertiser = PairingHostAdvertiser(onState: onState)
        try advertiser.register(name: name, port: port, txtRecord: txtRecord)
        return advertiser
    }

    private init(onState: @escaping @Sendable (PairingHostAdvertiserState) -> Void) {
        self.onState = onState
    }

    deinit { stop() }

    func stop() {
        queue.sync {
            guard let service else { return }
            DNSServiceRefDeallocate(service)
            self.service = nil
        }
    }

    private func register(name: String, port: UInt16, txtRecord: Data) throws {
        try queue.sync {
            var reference: DNSServiceRef?
            let context = Unmanaged.passUnretained(self).toOpaque()
            let registered = txtRecord.withUnsafeBytes { txt in
                DNSServiceRegister(
                    &reference,
                    0,
                    0,
                    name,
                    Self.serviceType,
                    nil,
                    nil,
                    port.bigEndian,
                    UInt16(txt.count),
                    txt.baseAddress,
                    { _, _, errorCode, _, _, _, context in
                        guard let context else { return }
                        Unmanaged<PairingHostAdvertiser>.fromOpaque(context)
                            .takeUnretainedValue()
                            .registrationChanged(errorCode)
                    },
                    context
                )
            }
            guard registered == Self.noError, let reference else {
                throw PairingHostError.advertise(code: registered)
            }
            let attached = DNSServiceSetDispatchQueue(reference, queue)
            guard attached == Self.noError else {
                DNSServiceRefDeallocate(reference)
                throw PairingHostError.advertise(code: attached)
            }
            service = reference
        }
    }

    /// 在 `queue` 上呼叫。
    private func registrationChanged(_ errorCode: DNSServiceErrorType) {
        switch errorCode {
        case Self.noError: onState(.registered)
        case Self.policyDenied: onState(.waitingForPermission)
        default: onState(.failed(code: errorCode))
        }
    }
}

// MARK: - Session

/// 一次「在這支 iPhone 上配對」：開 socket、廣播，等「設定」連進來，再把連線交給 engine。
/// 全部在自己的執行緒上跑，因為 `waitForConnection` 和 engine 的配對都會一直擋住。
/// 一次連線沒有配對成功（例如 PIN 打錯、使用者在「設定」按了取消）就繼續等下一次，
/// 直到配對成功或被 `cancel()`。逾時由呼叫端決定，時間到就呼叫 `cancel()`。
final class PairingHostSession: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        case advertising
        case waitingForLocalNetworkPermission
        case deviceConnected
        case pin(String)
        case attemptFailed(String)
    }

    private let makeEngine: () throws -> PairingHostEngine
    private let makeAdvertiser: PairingHostAdvertiserFactory
    private let onEvent: @Sendable (Event) -> Void
    private let onFinish: @Sendable (PairingHostOutcome) -> Void

    private let lock = NSLock()
    private var isCancelled = false
    /// 正在配對的連線。`cancel()` 對它呼叫 `shutdown`，讓擋住的配對返回。
    /// engine 會複製這個 fd，只 `close` 原本的不會影響複製出來的那個，所以一定要用 `shutdown`。
    private var activeConnection: Int32 = -1
    private var advertiserFailure: Int32?

    init(
        makeEngine: @escaping () throws -> PairingHostEngine,
        makeAdvertiser: @escaping PairingHostAdvertiserFactory = PairingHostAdvertiser.make,
        onEvent: @escaping @Sendable (Event) -> Void,
        onFinish: @escaping @Sendable (PairingHostOutcome) -> Void
    ) {
        self.makeEngine = makeEngine
        self.makeAdvertiser = makeAdvertiser
        self.onEvent = onEvent
        self.onFinish = onFinish
    }

    func start() {
        let thread = Thread { [self] in
            onFinish(run())
        }
        thread.name = "GFlyer pairing host"
        thread.start()
    }

    /// 可以在任何執行緒呼叫。結束時一樣會呼叫 `onFinish`，結果是 `.cancelled`。
    func cancel() {
        lock.withLock {
            isCancelled = true
            if activeConnection >= 0 { shutdown(activeConnection, SHUT_RDWR) }
        }
    }

    private var wasCancelled: Bool { lock.withLock { isCancelled } }

    private func run() -> PairingHostOutcome {
        do {
            return .paired(try pair())
        } catch {
            if wasCancelled { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    private func pair() throws -> PairingHostResult {
        let engine = try makeEngine()
        let listener = try PairingHostListener()
        defer { listener.stop() }
        let txtRecord = try PairingHostTXTRecord.encode(engine.txtRecord)
        let advertiser = try makeAdvertiser(engine.serviceName, listener.port, txtRecord) { [weak self] state in
            self?.advertiserChanged(state)
        }
        defer { advertiser.stop() }

        while true {
            try checkStillRunning()
            guard let connection = try listener.waitForConnection(timeout: 0.5) else { continue }
            if let result = try pair(over: connection, with: engine) { return result }
        }
    }

    /// 回傳 nil 代表這次連線沒有配對成功，要繼續等下一次。
    private func pair(over connection: Int32, with engine: PairingHostEngine) throws -> PairingHostResult? {
        // defer 倒序執行：先從 activeConnection 拿掉，才關掉 fd，
        // 免得 cancel() 對一個已經關掉、可能被重用的 fd 號碼呼叫 shutdown。
        defer { Darwin.close(connection) }
        let adopted = lock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            activeConnection = connection
            return true
        }
        guard adopted else { throw PairingHostError.cancelled }
        defer { lock.withLock { activeConnection = -1 } }

        onEvent(.deviceConnected)
        do {
            return try engine.pair(overConnection: connection) { [onEvent] pin in
                onEvent(.pin(pin))
            }
        } catch {
            if wasCancelled { throw PairingHostError.cancelled }
            onEvent(.attemptFailed(error.localizedDescription))
            return nil
        }
    }

    private func checkStillRunning() throws {
        try lock.withLock {
            if isCancelled { throw PairingHostError.cancelled }
            if let advertiserFailure { throw PairingHostError.advertise(code: advertiserFailure) }
        }
    }

    private func advertiserChanged(_ state: PairingHostAdvertiserState) {
        switch state {
        case .registered:
            onEvent(.advertising)
        case .waitingForPermission:
            onEvent(.waitingForLocalNetworkPermission)
        case let .failed(code):
            lock.withLock { advertiserFailure = code }
        }
    }
}
