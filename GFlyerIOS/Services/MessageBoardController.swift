import Combine
import Foundation

@MainActor
final class MessageBoardController: ObservableObject {
    @Published private(set) var member: BoardMember?
    @Published private(set) var posts: [BoardPost] = []
    @Published private(set) var invitations: [BoardInvitation] = []
    @Published private(set) var managedMembers: [BoardManagedMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var unreadCount = 0
    @Published private(set) var generatedInviteCode: String?
    @Published private(set) var shareRevision = 0
    @Published var errorMessage: String?
    @Published var username: String

    let api: MessageBoardAPIClient
    private let sessionStore: MessageBoardSessionStore
    private var refreshTask: Task<Void, Never>?
    private var isVisible = false

    init(
        api: MessageBoardAPIClient = MessageBoardAPIClient(),
        sessionStore: MessageBoardSessionStore = MessageBoardSessionStore()
    ) {
        self.api = api
        self.sessionStore = sessionStore
        username = sessionStore.username
        Task { [weak self] in await self?.restoreSession() }
    }

    var isConfigured: Bool { api.isConfigured }
    var isAuthenticated: Bool { member != nil && sessionStore.token != nil }
    var canManage: Bool { member?.role == .admin }

    func restoreSession() async {
        guard isConfigured, let token = sessionStore.token else { return }
        isLoading = true
        do {
            let currentMember = try await api.sessionMember(token: token)
            member = currentMember
            username = currentMember.username
            refresh()
        } catch {
            isLoading = false
            if let error = error as? MessageBoardAPIError, error.unauthorized {
                clearLocalSession()
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func authenticate(code: String, username: String, asAdmin: Bool) {
        let normalizedName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            errorMessage = "請輸入使用者名稱。"
            return
        }
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let validAdminCode = normalizedCode.count == 4 && normalizedCode.allSatisfy { ("0"..."9").contains($0) }
        guard asAdmin ? validAdminCode : normalizedCode.count >= 4 else {
            errorMessage = asAdmin ? "管理員啟用碼必須是 4 位數字。" : "共用邀請碼至少需要 4 個字元。"
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let authentication = try await (asAdmin
                    ? api.authenticateAdmin(code: normalizedCode, username: normalizedName)
                    : api.authenticateInvite(code: normalizedCode, username: normalizedName))
                try sessionStore.save(token: authentication.token, username: authentication.member.username)
                member = authentication.member
                self.username = authentication.member.username
                isSubmitting = false
                refresh()
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func refresh(silently: Bool = false) {
        refreshTask?.cancel()
        guard let token = sessionStore.token else {
            member = nil
            posts = []
            unreadCount = 0
            isLoading = false
            return
        }
        isLoading = !silently
        if !silently { errorMessage = nil }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let currentMember = api.sessionMember(token: token)
                async let currentPosts = api.posts(token: token)
                let (loadedMember, loadedPosts) = try await (currentMember, currentPosts)
                guard !Task.isCancelled else { return }
                member = loadedMember
                username = loadedMember.username
                posts = loadedPosts.sorted(by: Self.sortPosts)
                if isVisible {
                    sessionStore.markRead()
                    unreadCount = 0
                } else {
                    unreadCount = MessageBoardUnreadCounter.count(
                        posts: loadedPosts,
                        lastReadAt: sessionStore.lastReadAt
                    )
                }
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                handle(error, showMessage: !silently)
            }
        }
    }

    func refreshInBackground() {
        guard isConfigured, sessionStore.token != nil else { return }
        refresh(silently: true)
    }

    func markVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            sessionStore.markRead()
            unreadCount = 0
        }
    }

    func leave() {
        do { try sessionStore.clearSession() } catch { errorMessage = error.localizedDescription }
        clearLocalSession()
    }

    func shareCoordinate(
        coordinate: GeoCoordinate,
        name: String?,
        remark: String,
        duration: BoardShareDuration,
        tags: [String]
    ) {
        guard let token = sessionStore.token else { errorMessage = "請先加入留言板。"; return }
        submit {
            try await self.api.shareCoordinate(
                token: token,
                coordinate: coordinate,
                name: name,
                remark: remark,
                duration: duration,
                tags: tags
            )
        }
    }

    func shareRoute(
        route: SavedRoute,
        remark: String,
        duration: BoardShareDuration,
        tags: [String]
    ) {
        guard let token = sessionStore.token else { errorMessage = "請先加入留言板。"; return }
        submit {
            try await self.api.shareRoute(token: token, route: route, remark: remark, duration: duration, tags: tags)
        }
    }

    func createAnnouncement(message: String, duration: BoardShareDuration, tags: [String]) {
        guard let token = sessionStore.token else { errorMessage = "請先加入留言板。"; return }
        submit {
            try await self.api.createAnnouncement(token: token, message: message, duration: duration, tags: tags)
        }
    }

    func reply(to postID: String, message: String) {
        guard let token = sessionStore.token else { errorMessage = "請先加入留言板。"; return }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await api.reply(token: token, postID: postID, message: normalized)
                isSubmitting = false
                refresh()
            } catch {
                isSubmitting = false
                handle(error)
            }
        }
    }

    func deletePost(_ postID: String) {
        guard let token = sessionStore.token else { return }
        perform {
            try await self.api.deletePost(token: token, postID: postID)
        }
    }

    func deleteReply(_ replyID: String) {
        guard let token = sessionStore.token else { return }
        perform {
            try await self.api.deleteReply(token: token, replyID: replyID)
        }
    }

    func setPinned(postID: String, pinned: Bool) {
        guard let token = sessionStore.token else { return }
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await api.setPinned(token: token, postID: postID, pinned: pinned)
                isSubmitting = false
                refresh()
            } catch {
                isSubmitting = false
                handle(error)
            }
        }
    }

    func refreshAdmin() {
        guard let token = sessionStore.token, canManage else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                async let loadedInvitations = api.invitations(token: token)
                async let loadedMembers = api.managedMembers(token: token)
                let (newInvitations, newMembers) = try await (loadedInvitations, loadedMembers)
                invitations = newInvitations
                managedMembers = newMembers
                isLoading = false
            } catch {
                isLoading = false
                handle(error)
            }
        }
    }

    func createInvitation(code: String) {
        guard let token = sessionStore.token else { return }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count >= 4, normalized.count <= 32,
              BoardInviteCodeNormalizer.normalize(normalized) == normalized else {
            errorMessage = "共用邀請碼只可使用 4 至 32 個英文字母、數字、- 或 _。"
            return
        }
        isSubmitting = true
        generatedInviteCode = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let invitation = try await api.createInvitation(token: token, code: normalized)
                generatedInviteCode = invitation.code
                isSubmitting = false
                refreshAdmin()
            } catch {
                isSubmitting = false
                handle(error)
            }
        }
    }

    func clearGeneratedInviteCode() { generatedInviteCode = nil }

    func revokeInvitation(_ invitationID: String) {
        guard let token = sessionStore.token else { return }
        performAdmin {
            try await self.api.revokeInvitation(token: token, invitationID: invitationID)
        }
    }

    func promoteMember(_ memberID: String) {
        guard let token = sessionStore.token else { return }
        performAdmin {
            try await self.api.promoteMember(token: token, memberID: memberID)
        }
    }

    func revokeMember(_ memberID: String) {
        guard let token = sessionStore.token else { return }
        performAdmin {
            try await self.api.revokeMember(token: token, memberID: memberID)
        }
    }

    private func submit(_ action: @escaping () async throws -> BoardPost) {
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let post = try await action()
                posts = ([post] + posts.filter { $0.id != post.id }).sorted(by: Self.sortPosts)
                shareRevision += 1
                isSubmitting = false
            } catch {
                isSubmitting = false
                handle(error)
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await action()
                isSubmitting = false
                refresh()
            } catch {
                isSubmitting = false
                handle(error)
            }
        }
    }

    private func performAdmin(_ action: @escaping () async throws -> Void) {
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await action()
                isSubmitting = false
                refreshAdmin()
            } catch {
                isSubmitting = false
                handle(error)
            }
        }
    }

    private func handle(_ error: Error, showMessage: Bool = true) {
        if let apiError = error as? MessageBoardAPIError, apiError.unauthorized {
            clearLocalSession()
        } else if showMessage {
            errorMessage = error.localizedDescription
        }
    }

    private func clearLocalSession() {
        refreshTask?.cancel()
        try? sessionStore.clearSession()
        member = nil
        posts = []
        invitations = []
        managedMembers = []
        unreadCount = 0
        isLoading = false
        isSubmitting = false
    }

    private static func sortPosts(_ lhs: BoardPost, _ rhs: BoardPost) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        return lhs.createdAt > rhs.createdAt
    }
}
