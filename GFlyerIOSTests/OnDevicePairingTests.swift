import Darwin
import XCTest
@testable import GFlyerIOS

/// 「在這支 iPhone 上配對」不靠 idevice 的部分：TXT 編碼、listener、session 的重試和取消。
/// 真正的配對要 iOS 27 實機（docs/APP_STORE_PLAN.md 第 4 項），這裏用假的 engine 和假的 Bonjour。
final class OnDevicePairingTests: XCTestCase {
    // MARK: - TXT

    func testTXTRecordIsLengthPrefixedAndSortedByKey() throws {
        let data = try PairingHostTXTRecord.encode(["ver": "26", "authTag": "AbC=", "name": "GFlyer"])
        var expected = Data()
        for entry in ["authTag=AbC=", "name=GFlyer", "ver=26"] {
            expected.append(UInt8(entry.utf8.count))
            expected.append(Data(entry.utf8))
        }
        XCTAssertEqual(data, expected)
    }

    func testTXTRecordCountsBytesNotCharacters() throws {
        let data = try PairingHostTXTRecord.encode(["name": "配對"])
        XCTAssertEqual(data.first, UInt8("name=配對".utf8.count))
        XCTAssertEqual(data.count, 1 + "name=配對".utf8.count)
    }

    func testTXTRecordRejectsEntriesItCannotEncode() {
        XCTAssertThrowsError(try PairingHostTXTRecord.encode(["name": String(repeating: "a", count: 251)]))
        XCTAssertThrowsError(try PairingHostTXTRecord.encode(["": "x"]))
        XCTAssertThrowsError(try PairingHostTXTRecord.encode(["a=b": "x"]))
        XCTAssertNoThrow(try PairingHostTXTRecord.encode(["name": String(repeating: "a", count: 250)]))
    }

    func testTXTDictionaryComesFromTheXMLPropertyList() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["identifier": "ABC", "minVer": "17"],
            format: .xml,
            options: 0
        )
        XCTAssertEqual(
            try PairingHostTXTRecord.dictionary(fromPropertyList: plist),
            ["identifier": "ABC", "minVer": "17"]
        )

        let notStrings = try PropertyListSerialization.data(fromPropertyList: ["flags": 1], format: .xml, options: 0)
        XCTAssertThrowsError(try PairingHostTXTRecord.dictionary(fromPropertyList: notStrings))
        let notADictionary = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        XCTAssertThrowsError(try PairingHostTXTRecord.dictionary(fromPropertyList: notADictionary))
    }

    // MARK: - Listener

    func testListenerAcceptsIPv4AndIPv6Connections() throws {
        let listener = try PairingHostListener()
        defer { listener.stop() }
        XCTAssertNotEqual(listener.port, 0)
        XCTAssertNil(try listener.waitForConnection(timeout: 0.05))

        for ipv6 in [false, true] {
            let client = try connect(to: listener.port, ipv6: ipv6)
            defer { Darwin.close(client) }
            let accepted = try XCTUnwrap(try listener.waitForConnection(timeout: 2), "ipv6: \(ipv6)")
            Darwin.close(accepted)
        }
    }

    // MARK: - Session

    func testSessionKeepsWaitingAfterAFailedAttemptAndReturnsThePairingFile() throws {
        let engine = FakeEngine { attempt, _, onPIN in
            onPIN(attempt == 1 ? "111111" : "222222")
            if attempt == 1 { throw PairingHostError.idevice("SRP auth failed") }
            return PairingHostResult(pairingFile: Data("paired".utf8))
        }
        let run = SessionRun(engine: engine)
        run.session.start()
        let port = try run.waitUntilAdvertised()
        XCTAssertEqual(run.advertisedName, "TEST-SERVICE")
        XCTAssertEqual(
            run.advertisedTXT,
            try PairingHostTXTRecord.encode(["authTag": "tag", "name": "GFlyer"])
        )

        let first = try connect(to: port, ipv6: false)
        defer { Darwin.close(first) }
        let second = try connect(to: port, ipv6: true)
        defer { Darwin.close(second) }

        XCTAssertEqual(run.waitForOutcome(), .paired(PairingHostResult(pairingFile: Data("paired".utf8))))
        XCTAssertEqual(run.recorder.events, [
            .advertising,
            .deviceConnected,
            .pin("111111"),
            .attemptFailed("SRP auth failed"),
            .deviceConnected,
            .pin("222222"),
        ])
        XCTAssertTrue(run.advertiser.isStopped)
    }

    /// engine 會複製 fd，所以取消一定要對連線呼叫 shutdown，擋住的讀取才會返回。
    func testCancelDuringPairingShutsDownTheConnection() throws {
        let engine = FakeEngine { _, socket, _ in
            var byte: UInt8 = 0
            let count = read(socket, &byte, 1)
            throw PairingHostError.idevice("read returned \(count)")
        }
        let run = SessionRun(engine: engine)
        let connected = expectation(description: "device connected")
        run.recorder.onEvent = { if $0 == .deviceConnected { connected.fulfill() } }
        run.session.start()
        let client = try connect(to: try run.waitUntilAdvertised(), ipv6: false)
        defer { Darwin.close(client) }
        wait(for: [connected], timeout: 5)

        run.session.cancel()
        XCTAssertEqual(run.waitForOutcome(), .cancelled)
        XCTAssertFalse(run.recorder.events.contains { if case .attemptFailed = $0 { return true } else { return false } })
    }

    func testCancelWhileWaitingForTheDevice() throws {
        let run = SessionRun(engine: FakeEngine { _, _, _ in XCTFail("no device connects"); throw PairingHostError.cancelled })
        run.session.start()
        _ = try run.waitUntilAdvertised()
        run.session.cancel()
        XCTAssertEqual(run.waitForOutcome(), .cancelled)
        XCTAssertTrue(run.advertiser.isStopped)
    }

    func testBonjourFailureEndsTheSession() throws {
        let run = SessionRun(engine: FakeEngine { _, _, _ in throw PairingHostError.cancelled }, advertiserState: .failed(code: -65563))
        run.session.start()
        _ = try run.waitUntilAdvertised()
        XCTAssertEqual(
            run.waitForOutcome(),
            .failed(PairingHostError.advertise(code: -65563).localizedDescription)
        )
    }

    func testWaitingForLocalNetworkPermissionIsReportedAndKeepsWaiting() throws {
        let run = SessionRun(engine: FakeEngine { _, _, _ in throw PairingHostError.cancelled }, advertiserState: .waitingForPermission)
        run.session.start()
        _ = try run.waitUntilAdvertised()
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertNil(run.recorder.outcome, "沒有權限時要繼續等，使用者允許之後系統會繼續註冊")
        XCTAssertEqual(run.recorder.events, [.waitingForLocalNetworkPermission])
        run.session.cancel()
        XCTAssertEqual(run.waitForOutcome(), .cancelled)
    }

    func testEngineThatCannotStartFailsTheSession() {
        let finished = expectation(description: "finished")
        let recorder = EventRecorder()
        let session = PairingHostSession(
            makeEngine: { throw PairingHostError.idevice("無法準備配對。") },
            makeAdvertiser: { _, _, _, _ in
                XCTFail("不應該廣播")
                return FakeAdvertiser()
            },
            onEvent: { recorder.record($0) },
            onFinish: { recorder.finish($0); finished.fulfill() }
        )
        session.start()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(recorder.outcome, .failed("無法準備配對。"))
    }

    // MARK: - 背景工作

    func testContinuedTaskIdentifierUsesThePrefixFromInfoPlist() {
        let uuid = UUID()
        XCTAssertEqual(
            OnDevicePairingController.continuedTaskIdentifier(
                permitted: ["com.example.other", "com.example.app.pairing.*"],
                uuid: uuid
            ),
            "com.example.app.pairing.\(uuid.uuidString)"
        )
        XCTAssertNil(OnDevicePairingController.continuedTaskIdentifier(permitted: ["com.example.app.export.*"]))
        XCTAssertNil(OnDevicePairingController.continuedTaskIdentifier(permitted: nil))
    }

    /// Info.plist 的 `$(PRODUCT_BUNDLE_IDENTIFIER)` 要在建置時展開，識別碼才會以 bundle id 開頭。
    func testAppInfoPlistPermitsThePairingTaskAndBonjourService() throws {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        let identifier = try XCTUnwrap(OnDevicePairingController.continuedTaskIdentifier(permitted: permitted))
        let bundleIdentifier = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertTrue(identifier.hasPrefix("\(bundleIdentifier).pairing."), identifier)

        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        XCTAssertEqual(services, [PairingHostAdvertiser.serviceType])
    }

    @MainActor
    func testPairingIsUnavailableWithoutTheIdeviceEngine() {
        let controller = OnDevicePairingController(pairingStore: PairingFileStore(), makeEngine: nil)
        XCTAssertFalse(controller.isAvailable)
        controller.start()
        XCTAssertEqual(controller.phase, .idle)
    }

    // MARK: - 輔助

    private func connect(to port: UInt16, ipv6: Bool) throws -> Int32 {
        let descriptor = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else { throw PairingHostError.socket(call: "socket", code: errno) }
        let result: Int32
        if ipv6 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = in6addr_loopback
            result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw PairingHostError.socket(call: "connect", code: code)
        }
        return descriptor
    }
}

// MARK: - 假的 engine 和 Bonjour

private final class FakeEngine: PairingHostEngine {
    typealias Behaviour = (_ attempt: Int, _ socket: Int32, _ onPIN: (String) -> Void) throws -> PairingHostResult

    let serviceName = "TEST-SERVICE"
    let txtRecord = ["name": "GFlyer", "authTag": "tag"]
    private let behaviour: Behaviour
    private var attempts = 0

    init(_ behaviour: @escaping Behaviour) {
        self.behaviour = behaviour
    }

    /// 只在 session 的執行緒上呼叫。
    func pair(overConnection socket: Int32, onPIN: @escaping (String) -> Void) throws -> PairingHostResult {
        attempts += 1
        return try behaviour(attempts, socket, onPIN)
    }
}

private final class FakeAdvertiser: PairingHostAdvertising, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool { lock.withLock { stopped } }

    func stop() {
        lock.withLock { stopped = true }
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [PairingHostSession.Event] = []
    private var recordedOutcome: PairingHostOutcome?
    private var eventHook: ((PairingHostSession.Event) -> Void)?

    var events: [PairingHostSession.Event] { lock.withLock { recordedEvents } }
    var outcome: PairingHostOutcome? { lock.withLock { recordedOutcome } }
    var onEvent: ((PairingHostSession.Event) -> Void)? {
        get { lock.withLock { eventHook } }
        set { lock.withLock { eventHook = newValue } }
    }

    func record(_ event: PairingHostSession.Event) {
        let hook = lock.withLock { () -> ((PairingHostSession.Event) -> Void)? in
            recordedEvents.append(event)
            return eventHook
        }
        hook?(event)
    }

    func finish(_ outcome: PairingHostOutcome) {
        lock.withLock { recordedOutcome = outcome }
    }
}

/// 一次 session 和它的假 Bonjour：記下廣播的 port、名稱和 TXT。
private final class SessionRun: @unchecked Sendable {
    let recorder = EventRecorder()
    let advertiser = FakeAdvertiser()
    private(set) var session: PairingHostSession!
    private let lock = NSLock()
    private var advertisement: (name: String, port: UInt16, txt: Data)?
    private let advertised = XCTestExpectation(description: "advertised")
    private let finished = XCTestExpectation(description: "finished")

    var advertisedName: String? { lock.withLock { advertisement?.name } }
    var advertisedTXT: Data? { lock.withLock { advertisement?.txt } }

    init(engine: FakeEngine, advertiserState: PairingHostAdvertiserState = .registered) {
        session = PairingHostSession(
            makeEngine: { engine },
            makeAdvertiser: { [self] name, port, txt, onState in
                lock.withLock { advertisement = (name, port, txt) }
                onState(advertiserState)
                advertised.fulfill()
                return advertiser
            },
            onEvent: { [recorder] in recorder.record($0) },
            onFinish: { [recorder, finished] in
                recorder.finish($0)
                finished.fulfill()
            }
        )
    }

    func waitUntilAdvertised() throws -> UInt16 {
        XCTAssertEqual(XCTWaiter.wait(for: [advertised], timeout: 5), .completed)
        return try XCTUnwrap(lock.withLock { advertisement?.port })
    }

    func waitForOutcome() -> PairingHostOutcome? {
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 5), .completed)
        return recorder.outcome
    }
}
