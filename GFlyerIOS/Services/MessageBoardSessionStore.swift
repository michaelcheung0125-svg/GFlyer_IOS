import Foundation
import Security

enum MessageBoardSessionStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "無法安全保存留言板登入資料：\(detail)"
        }
    }
}

final class MessageBoardSessionStore {
    private let defaults: UserDefaults
    private let service: String
    private let tokenAccount = "message-board-session-token"
    private let usernameKey = "gflyer.message-board.username"
    private let lastReadKey = "gflyer.message-board.last-read"

    init(
        defaults: UserDefaults = .standard,
        service: String = Bundle.main.bundleIdentifier ?? "com.geopilot.gflyer.ios"
    ) {
        self.defaults = defaults
        self.service = service
    }

    var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    var username: String { defaults.string(forKey: usernameKey) ?? "" }

    var lastReadAt: Date {
        let value = defaults.double(forKey: lastReadKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : .distantPast
    }

    func save(token: String, username: String) throws {
        try removeToken(allowMissing: true)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw MessageBoardSessionStoreError.keychain(status) }
        setUsername(username)
    }

    func setUsername(_ username: String) {
        defaults.set(username, forKey: usernameKey)
    }

    func markRead(at date: Date = .now) {
        defaults.set(date.timeIntervalSince1970, forKey: lastReadKey)
    }

    func clearSession() throws {
        try removeToken(allowMissing: true)
    }

    private func removeToken(allowMissing: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && !(allowMissing && status == errSecItemNotFound) {
            throw MessageBoardSessionStoreError.keychain(status)
        }
    }
}
