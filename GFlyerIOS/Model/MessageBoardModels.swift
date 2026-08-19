import Foundation

enum BoardRole: String, Codable, Sendable {
    case member = "MEMBER"
    case admin = "ADMIN"

    var label: String { self == .admin ? "管理員" : "會員" }
}

enum BoardPostKind: String, Codable, Sendable {
    case coordinate = "COORDINATE"
    case route = "ROUTE"
    case announcement = "ANNOUNCEMENT"

    var label: String {
        switch self {
        case .coordinate: return "座標"
        case .route: return "路線"
        case .announcement: return "公告"
        }
    }
}

enum BoardShareDuration: String, CaseIterable, Identifiable, Sendable {
    case twelveHours
    case twentyFourHours
    case permanent

    var id: Self { self }

    var hours: Int? {
        switch self {
        case .twelveHours: return 12
        case .twentyFourHours: return 24
        case .permanent: return nil
        }
    }

    var label: String {
        switch self {
        case .twelveHours: return "12 小時"
        case .twentyFourHours: return "24 小時"
        case .permanent: return "永久"
        }
    }
}

struct BoardMember: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let role: BoardRole
    let deviceLabel: String
    let createdAt: Date
    let lastActiveAt: Date
    let revokedAt: Date?
}

struct BoardReply: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let authorName: String
    let message: String
    let createdAt: Date
    let canDelete: Bool
    let isOwn: Bool
}

struct BoardPostPayload: Codable, Equatable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let name: String?
    let loop: Bool?
    let points: [GeoCoordinate]?

    init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        name: String? = nil,
        loop: Bool? = nil,
        points: [GeoCoordinate]? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.loop = loop
        self.points = points
    }
}

struct SharedBoardRoute: Equatable, Sendable {
    let name: String
    let points: [GeoCoordinate]
    let loop: Bool
}

struct BoardPost: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let authorName: String
    let kind: BoardPostKind
    let remark: String
    let payload: BoardPostPayload
    let createdAt: Date
    let expiresAt: Date?
    let canDelete: Bool
    let tags: [String]
    let pinned: Bool
    let isOwn: Bool
    let replies: [BoardReply]

    var coordinate: GeoCoordinate? {
        guard kind == .coordinate,
              let latitude = payload.latitude,
              let longitude = payload.longitude,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else { return nil }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    var route: SharedBoardRoute? {
        guard kind == .route,
              let name = payload.name,
              let points = payload.points,
              points.count >= 2 else { return nil }
        return SharedBoardRoute(name: name, points: points, loop: payload.loop ?? false)
    }

    var isActive: Bool { expiresAt.map { $0 > .now } ?? true }

    var searchText: String {
        var values = [authorName, remark, tags.joined(separator: " ")]
        if let coordinate {
            values.append(coordinate.display)
            values.append(payload.name ?? "")
        }
        if let route {
            values.append(route.name)
            values.append(route.points.map(\.display).joined(separator: " "))
        }
        values.append(contentsOf: replies.flatMap { [$0.authorName, $0.message] })
        return values.joined(separator: " ").lowercased()
    }
}

struct BoardInvitation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let createdAt: Date
    let expiresAt: Date?
    let maxUses: Int?
    let useCount: Int
    let revokedAt: Date?
    var code: String?
}

struct BoardManagedMember: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let role: BoardRole
    let deviceLabel: String
    let createdAt: Date
    let lastActiveAt: Date
    let revokedAt: Date?
    let inviteLabel: String?
}

struct BoardAuthentication: Codable, Equatable, Sendable {
    let token: String
    let member: BoardMember
}

enum MessageBoardUnreadCounter {
    static func count(posts: [BoardPost], lastReadAt: Date) -> Int {
        posts.reduce(into: 0) { total, post in
            if !post.isOwn, post.createdAt > lastReadAt { total += 1 }
            total += post.replies.filter { !$0.isOwn && $0.createdAt > lastReadAt }.count
        }
    }
}

enum BoardTagNormalizer {
    static func normalize(_ value: String) -> [String] {
        var result: [String] = []
        for rawTag in value.split(whereSeparator: { $0 == "," || $0 == "，" }) {
            let tag = String(rawTag)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^#", with: "", options: .regularExpression)
            let shortened = String(tag.prefix(20))
            guard !shortened.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(shortened) == .orderedSame }) else {
                continue
            }
            result.append(shortened)
            if result.count == 5 { break }
        }
        return result
    }
}

enum BoardInviteCodeNormalizer {
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    static func normalize(_ value: String, limit: Int = 32) -> String {
        String(value.uppercased().filter { allowedCharacters.contains($0) }.prefix(limit))
    }

    static func normalizeAdminCode(_ value: String) -> String {
        String(value.filter { ("0"..."9").contains($0) }.prefix(4))
    }
}
