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

/// 留言板每個字串欄位的上限,單位是 Unicode code point(伺服器先去掉前後空白再數),
/// 和 Android、Worker 相同(GFlyer-Suite docs/features/message-board-limits.md)。
/// 截斷用 `prefixCodePoints`、計數用 `unicodeScalars.count`,不要用 `prefix` / `count`(字素)。
enum BoardTextLimits {
    static let inviteCode = 32
    static let inviteCodeMinimum = 4
    static let adminCode = 4
    static let username = 30
    static let deviceLabel = 80
    static let clientRequestID = 80
    static let reportCoordinateID = 60
    static let reportCoordinateName = 80
    static let reportReason = 40
    static let reportMessage = 300
    static let remark = 300
    static let tag = 20
    static let maxTags = 5
    static let sharedCoordinateName = 80
    static let routeName = 80
    static let reply = 300
    /// 只在客戶端的輸入框上限(伺服器不檢查)。
    static let tagsInput = 120
    static let boardSearch = 80

    /// 以 contracts/fixtures/text/message-board-limits.json 的 `id` 為鍵(`fields[]` 與
    /// `clientInputCaps[]`)。iOS CI 看不到 Suite,SharedContractTests 照抄 fixture 逐一比對,
    /// 改 fixture 時兩邊都要跟著改。
    static let maxLengthByFixtureID: [String: Int] = [
        "auth.inviteCode": inviteCode,
        "auth.adminCode": adminCode,
        "auth.username": username,
        "auth.deviceLabel": deviceLabel,
        "coordReport.clientRequestId": clientRequestID,
        "coordReport.coordinateId": reportCoordinateID,
        "coordReport.coordinateName": reportCoordinateName,
        "coordReport.reason": reportReason,
        "coordReport.message": reportMessage,
        "post.clientRequestId": clientRequestID,
        "post.remark": remark,
        "post.tag": tag,
        "post.coordinate.name": sharedCoordinateName,
        "post.route.name": routeName,
        "reply.message": reply,
        "invite.code": inviteCode,
        "ui.tagsInput": tagsInput,
        "ui.boardSearch": boardSearch,
    ]
}

/// 和 Android 的 `normalizeBoardTags` 相同:逗號分隔 → 去前後空白 → 去掉開頭一個 # → 截到 20 個
/// code point → 略過空白 → 去重(區分大小寫,和 Android、伺服器相同)→ 前 5 個。
enum BoardTagNormalizer {
    static func normalize(_ value: String) -> [String] {
        var result: [String] = []
        for rawTag in value.split(whereSeparator: { $0 == "," || $0 == "，" }) {
            let tag = String(rawTag)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^#", with: "", options: .regularExpression)
            let shortened = tag.prefixCodePoints(BoardTextLimits.tag)
            // 截斷後可能只剩空白(「#」後面接一串空白),伺服器會回「請輸入標籤」
            guard !shortened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  // 逐個 code point 比:String 的 == 會把正規等價的字當成相同,伺服器不會
                  !result.contains(where: { $0.unicodeScalars.elementsEqual(shortened.unicodeScalars) }) else {
                continue
            }
            result.append(shortened)
            if result.count == BoardTextLimits.maxTags { break }
        }
        return result
    }
}

enum BoardInviteCodeNormalizer {
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    /// 過濾之後只剩 ASCII,字素、code point、UTF-16 三種數法相同。
    static func normalize(_ value: String, limit: Int = BoardTextLimits.inviteCode) -> String {
        String(value.uppercased().filter { allowedCharacters.contains($0) }.prefix(limit))
    }

    static func normalizeAdminCode(_ value: String) -> String {
        String(value.filter { ("0"..."9").contains($0) }.prefix(BoardTextLimits.adminCode))
    }
}
