import Foundation

struct MessageBoardAPIError: LocalizedError, Equatable, Sendable {
    let message: String
    let unauthorized: Bool

    init(_ message: String, unauthorized: Bool = false) {
        self.message = message
        self.unauthorized = unauthorized
    }

    var errorDescription: String? { message }
}

actor MessageBoardAPIClient {
    nonisolated let isConfigured: Bool
    nonisolated let deviceLabel: String

    private let baseURL: URL?
    private let session: URLSession
    private let encoder = JSONEncoder()

    init(
        baseURLString: String = Bundle.main.object(forInfoDictionaryKey: "GFlyerMessageBoardAPIURL") as? String ?? "",
        session: URLSession = .shared,
        deviceLabel: String = MessageBoardDeviceLabel.current
    ) {
        let normalized = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: normalized)
        if let url,
           url.scheme?.lowercased() == "https",
           url.host?.isEmpty == false,
           url.user == nil,
           url.password == nil {
            baseURL = url
            isConfigured = true
        } else {
            baseURL = nil
            isConfigured = false
        }
        self.session = session
        self.deviceLabel = String(deviceLabel.prefix(80))
    }

    func authenticateInvite(code: String, username: String) async throws -> BoardAuthentication {
        let response: AuthenticationResponse = try await request(
            method: "POST",
            path: "/v1/auth/invite",
            body: AuthenticationRequest(
                inviteCode: code,
                adminCode: nil,
                username: username,
                deviceLabel: deviceLabel
            )
        )
        return BoardAuthentication(token: response.token, member: response.member)
    }

    func authenticateAdmin(code: String, username: String) async throws -> BoardAuthentication {
        let response: AuthenticationResponse = try await request(
            method: "POST",
            path: "/v1/auth/admin",
            body: AuthenticationRequest(
                inviteCode: nil,
                adminCode: code,
                username: username,
                deviceLabel: deviceLabel
            )
        )
        return BoardAuthentication(token: response.token, member: response.member)
    }

    func sessionMember(token: String) async throws -> BoardMember {
        let response: SessionResponse = try await request(method: "GET", path: "/v1/session", token: token)
        return response.member
    }

    func posts(token: String) async throws -> [BoardPost] {
        let response: PostsResponse = try await request(method: "GET", path: "/v1/posts", token: token)
        return response.posts
    }

    func shareCoordinate(
        token: String,
        coordinate: GeoCoordinate,
        name: String?,
        remark: String,
        duration: BoardShareDuration,
        tags: [String]
    ) async throws -> BoardPost {
        let response: PostResponse = try await request(
            method: "POST",
            path: "/v1/posts",
            token: token,
            body: CreatePostRequest(
                clientRequestId: UUID().uuidString,
                kind: .coordinate,
                remark: remark,
                durationHours: duration.hours,
                tags: tags,
                coordinate: SharedCoordinateRequest(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    name: name
                ),
                route: nil
            )
        )
        return response.post
    }

    func shareRoute(
        token: String,
        route: SavedRoute,
        remark: String,
        duration: BoardShareDuration,
        tags: [String]
    ) async throws -> BoardPost {
        let response: PostResponse = try await request(
            method: "POST",
            path: "/v1/posts",
            token: token,
            body: CreatePostRequest(
                clientRequestId: UUID().uuidString,
                kind: .route,
                remark: remark,
                durationHours: duration.hours,
                tags: tags,
                coordinate: nil,
                route: SharedRouteRequest(name: route.name, loop: route.loop, points: route.points)
            )
        )
        return response.post
    }

    func createAnnouncement(
        token: String,
        message: String,
        duration: BoardShareDuration,
        tags: [String]
    ) async throws -> BoardPost {
        let response: PostResponse = try await request(
            method: "POST",
            path: "/v1/posts",
            token: token,
            body: CreatePostRequest(
                clientRequestId: UUID().uuidString,
                kind: .announcement,
                remark: message,
                durationHours: duration.hours,
                tags: tags,
                coordinate: nil,
                route: nil
            )
        )
        return response.post
    }

    func reply(token: String, postID: String, message: String) async throws -> BoardReply {
        let response: ReplyResponse = try await request(
            method: "POST",
            path: "/v1/posts/\(encodedPath(postID))/replies",
            token: token,
            body: ReplyRequest(message: message)
        )
        return response.reply
    }

    func deletePost(token: String, postID: String) async throws {
        let _: SuccessResponse = try await request(
            method: "DELETE",
            path: "/v1/posts/\(encodedPath(postID))",
            token: token
        )
    }

    func deleteReply(token: String, replyID: String) async throws {
        let _: SuccessResponse = try await request(
            method: "DELETE",
            path: "/v1/replies/\(encodedPath(replyID))",
            token: token
        )
    }

    func setPinned(token: String, postID: String, pinned: Bool) async throws -> BoardPost {
        let response: PostResponse = try await request(
            method: "PATCH",
            path: "/v1/admin/posts/\(encodedPath(postID))",
            token: token,
            body: PinRequest(pinned: pinned)
        )
        return response.post
    }

    func invitations(token: String) async throws -> [BoardInvitation] {
        let response: InvitationsResponse = try await request(
            method: "GET",
            path: "/v1/admin/invites",
            token: token
        )
        return response.invites
    }

    func createInvitation(token: String, code: String) async throws -> BoardInvitation {
        let response: InvitationResponse = try await request(
            method: "POST",
            path: "/v1/admin/invites",
            token: token,
            body: InvitationRequest(code: code)
        )
        var invitation = response.invite
        invitation.code = response.code
        return invitation
    }

    func revokeInvitation(token: String, invitationID: String) async throws {
        let _: SuccessResponse = try await request(
            method: "DELETE",
            path: "/v1/admin/invites/\(encodedPath(invitationID))",
            token: token
        )
    }

    func managedMembers(token: String) async throws -> [BoardManagedMember] {
        let response: ManagedMembersResponse = try await request(
            method: "GET",
            path: "/v1/admin/members",
            token: token
        )
        return response.members
    }

    func promoteMember(token: String, memberID: String) async throws {
        let _: SuccessResponse = try await request(
            method: "PATCH",
            path: "/v1/admin/members/\(encodedPath(memberID))",
            token: token,
            body: RoleRequest(role: .admin)
        )
    }

    func revokeMember(token: String, memberID: String) async throws {
        let _: SuccessResponse = try await request(
            method: "DELETE",
            path: "/v1/admin/members/\(encodedPath(memberID))",
            token: token
        )
    }

    private func request<Response: Decodable>(
        method: String,
        path: String,
        token: String? = nil
    ) async throws -> Response {
        try await request(method: method, path: path, token: token, bodyData: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(
        method: String,
        path: String,
        token: String? = nil,
        body: Body
    ) async throws -> Response {
        try await request(method: method, path: path, token: token, bodyData: encoder.encode(body))
    }

    private func request<Response: Decodable>(
        method: String,
        path: String,
        token: String?,
        bodyData: Data?
    ) async throws -> Response {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw MessageBoardAPIError("留言板伺服器尚未設定。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= 2 * 1_024 * 1_024 else {
                throw MessageBoardAPIError("留言板回應內容過大。")
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MessageBoardAPIError("留言板伺服器沒有傳回有效回應。")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = (try? MessageBoardJSON.makeDecoder().decode(ErrorResponse.self, from: data).error)
                    ?? "留言板連線失敗（HTTP \(httpResponse.statusCode)）"
                throw MessageBoardAPIError(message, unauthorized: httpResponse.statusCode == 401)
            }
            do {
                return try MessageBoardJSON.makeDecoder().decode(Response.self, from: data)
            } catch {
                throw MessageBoardAPIError("無法解析留言板回應：\(error.localizedDescription)")
            }
        } catch let error as MessageBoardAPIError {
            throw error
        } catch {
            throw MessageBoardAPIError("無法連接留言板：\(error.localizedDescription)")
        }
    }

    private var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return "GFlyer/\(version) (iOS)"
    }

    private func encodedPath(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum MessageBoardJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date"
            )
        }
        return decoder
    }
}

enum MessageBoardDeviceLabel {
    static var current: String {
        "Apple iOS device (\(ProcessInfo.processInfo.operatingSystemVersionString))"
    }
}

private struct AuthenticationRequest: Encodable {
    let inviteCode: String?
    let adminCode: String?
    let username: String
    let deviceLabel: String
}

private struct AuthenticationResponse: Decodable {
    let token: String
    let member: BoardMember
}

private struct SessionResponse: Decodable { let member: BoardMember }
private struct PostsResponse: Decodable { let posts: [BoardPost] }
private struct PostResponse: Decodable { let post: BoardPost }
private struct ReplyResponse: Decodable { let reply: BoardReply }
private struct InvitationsResponse: Decodable { let invites: [BoardInvitation] }
private struct ManagedMembersResponse: Decodable { let members: [BoardManagedMember] }
private struct SuccessResponse: Decodable { let ok: Bool }
private struct ErrorResponse: Decodable { let error: String }

private struct SharedCoordinateRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let name: String?
}

private struct SharedRouteRequest: Encodable {
    let name: String
    let loop: Bool
    let points: [GeoCoordinate]
}

private struct CreatePostRequest: Encodable {
    let clientRequestId: String
    let kind: BoardPostKind
    let remark: String
    let durationHours: Int?
    let tags: [String]
    let coordinate: SharedCoordinateRequest?
    let route: SharedRouteRequest?
}

private struct ReplyRequest: Encodable { let message: String }
private struct PinRequest: Encodable { let pinned: Bool }
private struct InvitationRequest: Encodable { let code: String }
private struct RoleRequest: Encodable { let role: BoardRole }

private struct InvitationResponse: Decodable {
    let invite: BoardInvitation
    let code: String
}
