import Foundation
import XCTest
@testable import GFlyerIOS

final class MessageBoardTests: XCTestCase {
    func testDecodesAndroidCoordinatePostWithReplyAndFractionalDates() throws {
        let post: BoardPost = try decode(
            #"""
            {
              "id": "coordinate-1",
              "authorName": "Android user",
              "kind": "COORDINATE",
              "remark": "Meet here",
              "payload": {
                "latitude": 22.3193,
                "longitude": 114.1694,
                "name": "Mong Kok"
              },
              "createdAt": "2026-08-19T12:34:56.123Z",
              "expiresAt": "2026-08-20T00:34:56.123Z",
              "canDelete": false,
              "tags": ["raid", "night"],
              "pinned": false,
              "isOwn": false,
              "replies": [
                {
                  "id": "reply-1",
                  "authorName": "iOS user",
                  "message": "On my way",
                  "createdAt": "2026-08-19T12:35:00Z",
                  "canDelete": true,
                  "isOwn": true
                }
              ]
            }
            """#
        )

        XCTAssertEqual(post.kind, .coordinate)
        XCTAssertEqual(post.coordinate, GeoCoordinate(latitude: 22.3193, longitude: 114.1694))
        XCTAssertEqual(post.payload.name, "Mong Kok")
        XCTAssertEqual(post.tags, ["raid", "night"])
        XCTAssertEqual(post.replies.first?.message, "On my way")
        XCTAssertNotNil(post.expiresAt)
    }

    func testDecodesAndroidRouteAndAnnouncementPosts() throws {
        let route: BoardPost = try decode(
            #"""
            {
              "id": "route-1",
              "authorName": "Android user",
              "kind": "ROUTE",
              "remark": "Two stops",
              "payload": {
                "name": "Harbour route",
                "loop": true,
                "points": [
                  {"latitude": 22.2819, "longitude": 114.1589},
                  {"latitude": 22.2976, "longitude": 114.1722}
                ]
              },
              "createdAt": "2026-08-19T13:00:00Z",
              "expiresAt": null,
              "canDelete": true,
              "tags": [],
              "pinned": false,
              "isOwn": true,
              "replies": []
            }
            """#
        )
        let announcement: BoardPost = try decode(
            #"""
            {
              "id": "announcement-1",
              "authorName": "Admin",
              "kind": "ANNOUNCEMENT",
              "remark": "Maintenance tonight",
              "payload": {},
              "createdAt": "2026-08-19T13:01:00.5Z",
              "expiresAt": null,
              "canDelete": false,
              "tags": ["notice"],
              "pinned": true,
              "isOwn": false,
              "replies": []
            }
            """#
        )

        XCTAssertEqual(route.route?.name, "Harbour route")
        XCTAssertEqual(route.route?.points.count, 2)
        XCTAssertEqual(route.route?.loop, true)
        XCTAssertEqual(announcement.kind, .announcement)
        XCTAssertTrue(announcement.pinned)
        XCTAssertNil(announcement.coordinate)
        XCTAssertNil(announcement.route)
    }

    func testDecodesMemberAndAdminRecords() throws {
        let member: BoardMember = try decode(
            #"""
            {
              "id": "member-1",
              "username": "iOS user",
              "role": "MEMBER",
              "deviceLabel": "Apple iOS device",
              "createdAt": "2026-08-19T13:00:00Z",
              "lastActiveAt": "2026-08-19T13:02:00.123Z",
              "revokedAt": null
            }
            """#
        )
        let managed: BoardManagedMember = try decode(
            #"""
            {
              "id": "member-2",
              "username": "Android user",
              "role": "ADMIN",
              "deviceLabel": "Google Pixel",
              "createdAt": "2026-08-18T13:00:00Z",
              "lastActiveAt": "2026-08-19T13:03:00Z",
              "revokedAt": null,
              "inviteLabel": "Friends"
            }
            """#
        )

        XCTAssertEqual(member.role, .member)
        XCTAssertEqual(managed.role, .admin)
        XCTAssertEqual(managed.inviteLabel, "Friends")
    }

    func testUnreadCounterCountsForeignPostsAndRepliesOnly() {
        let lastRead = Date(timeIntervalSince1970: 1_000)
        let foreignReply = makeReply(createdAt: 1_020, isOwn: false)
        let ownReply = makeReply(id: "own-reply", createdAt: 1_030, isOwn: true)
        let foreignPost = makePost(id: "foreign", createdAt: 1_010, isOwn: false, replies: [foreignReply, ownReply])
        let ownPost = makePost(id: "own", createdAt: 1_040, isOwn: true)
        let oldPost = makePost(id: "old", createdAt: 900, isOwn: false)

        XCTAssertEqual(
            MessageBoardUnreadCounter.count(posts: [foreignPost, ownPost, oldPost], lastReadAt: lastRead),
            2
        )
    }

    func testTagAndInviteCodeNormalizationMatchesBackendLimits() {
        // 去重區分大小寫,和 Android 的 distinct() 與伺服器相同
        XCTAssertEqual(
            BoardTagNormalizer.normalize("#Raid, raid， night ,abcdefghijklmnopqrstuvw,extra,ignored"),
            ["Raid", "raid", "night", "abcdefghijklmnopqrst", "extra"]
        )
        XCTAssertEqual(BoardTagNormalizer.normalize("Raid,#Raid,raid"), ["Raid", "raid"])
        // 20 個 code point:emoji 不被切成一半
        let walker = "\u{1F6B6}"
        XCTAssertEqual(
            BoardTagNormalizer.normalize(String(repeating: walker, count: 25)),
            [String(repeating: walker, count: 20)]
        )
        // 截斷後只剩空白的標籤略過,伺服器會回「請輸入標籤」
        XCTAssertEqual(BoardTagNormalizer.normalize("#" + String(repeating: " ", count: 20) + "x,ok"), ["ok"])
        XCTAssertEqual(BoardInviteCodeNormalizer.normalize(" ab-c_12!? "), "AB-C_12")
        XCTAssertEqual(BoardInviteCodeNormalizer.normalizeAdminCode("a1２3-45"), "1345")
    }

    /// 本機訊息和 Android(或 Android 送出後顯示的伺服器訊息)一字不差,不加句號。
    @MainActor
    func testAuthenticationMessagesMatchAndroid() {
        let suiteName = "gflyer.board-auth-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let board = MessageBoardController(
            api: MessageBoardAPIClient(baseURLString: ""),
            sessionStore: MessageBoardSessionStore(defaults: defaults, service: suiteName)
        )

        board.authenticate(code: "ABCD", username: "  ", asAdmin: false)
        XCTAssertEqual(board.errorMessage, "請輸入使用者名稱及共用邀請碼")
        board.authenticate(code: " ", username: "Amy", asAdmin: false)
        XCTAssertEqual(board.errorMessage, "請輸入使用者名稱及共用邀請碼")
        board.authenticate(code: "", username: "Amy", asAdmin: true)
        XCTAssertEqual(board.errorMessage, "請輸入使用者名稱及管理員啟用碼")
        board.authenticate(code: "ABC", username: "Amy", asAdmin: false)
        XCTAssertEqual(board.errorMessage, "共用邀請碼至少需要 4 個字元")
        board.authenticate(code: "123", username: "Amy", asAdmin: true)
        XCTAssertEqual(board.errorMessage, "管理員啟用碼必須是 4 位數字")

        XCTAssertEqual(MessageBoardController.invitationCodeProblem("ABC"), "共用邀請碼需為 4 至 32 個字元")
        XCTAssertEqual(
            MessageBoardController.invitationCodeProblem(String(repeating: "A", count: 33)),
            "共用邀請碼需為 4 至 32 個字元"
        )
        XCTAssertEqual(MessageBoardController.invitationCodeProblem("AB CD"), "共用邀請碼只可使用英文字母、數字、- 或 _")
        XCTAssertNil(MessageBoardController.invitationCodeProblem("AB-C_12"))
        // 伺服器數轉大寫之後的 code point:「ßß」變成「SSSS」,長度與字元都合法
        XCTAssertNil(MessageBoardController.invitationCodeProblem("ßß".uppercased()))
    }

    /// 分享收藏座標與路線時,送出前把名稱正規化到 80 個 code point(舊資料可能超過)。
    func testSharedNamesAreLimitedBeforeSending() {
        let walker = "\u{1F6B6}"
        XCTAssertNil(MessageBoardAPIClient.sharedCoordinateName(nil))
        XCTAssertNil(MessageBoardAPIClient.sharedCoordinateName("   "))
        XCTAssertEqual(MessageBoardAPIClient.sharedCoordinateName("  旺角  "), "旺角")
        XCTAssertEqual(
            MessageBoardAPIClient.sharedCoordinateName(String(repeating: walker, count: 90)),
            String(repeating: walker, count: 80)
        )
        XCTAssertEqual(SavedRoute.normalizedName(String(repeating: walker, count: 90)), String(repeating: walker, count: 80))
    }

    @MainActor
    func testControllerLoadsAndSavesSharedBoardContent() {
        let suiteName = "gflyer.message-board-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SimulationController(
            backend: PreviewLocationSimulationBackend(),
            dataStore: LocalDataStore(defaults: defaults)
        )
        let route = SharedBoardRoute(
            name: "Harbour route",
            points: [
                GeoCoordinate(latitude: 22.2819, longitude: 114.1589),
                GeoCoordinate(latitude: 22.2976, longitude: 114.1722),
            ],
            loop: true
        )

        XCTAssertTrue(controller.previewBoardRoute(route, startImmediately: false))
        XCTAssertEqual(controller.mode, .multiRoute)
        XCTAssertEqual(controller.routePoints, route.points)
        XCTAssertTrue(controller.loopRoute)

        controller.saveBoardRoute(route, authorName: "Android user")
        controller.saveBoardRoute(route, authorName: "Android user")
        XCTAssertEqual(Set(controller.savedRoutes.map(\.name)), Set([
            "Harbour route (Android user)",
            "Harbour route (Android user) 2",
        ]))
        XCTAssertEqual(controller.savedRoutes.count, 2)

        let coordinate = GeoCoordinate(latitude: 22.3193, longitude: 114.1694)
        controller.saveBoardCoordinate(coordinate, name: "Shared place")
        XCTAssertEqual(controller.favorites.last?.name, "Shared place")
        XCTAssertEqual(controller.favorites.last?.coordinate, coordinate)
    }

    private func decode<Value: Decodable>(_ json: String) throws -> Value {
        try MessageBoardJSON.makeDecoder().decode(Value.self, from: Data(json.utf8))
    }

    private func makeReply(id: String = "reply", createdAt: TimeInterval, isOwn: Bool) -> BoardReply {
        BoardReply(
            id: id,
            authorName: "Member",
            message: "Reply",
            createdAt: Date(timeIntervalSince1970: createdAt),
            canDelete: isOwn,
            isOwn: isOwn
        )
    }

    private func makePost(
        id: String,
        createdAt: TimeInterval,
        isOwn: Bool,
        replies: [BoardReply] = []
    ) -> BoardPost {
        BoardPost(
            id: id,
            authorName: "Member",
            kind: .announcement,
            remark: "Notice",
            payload: BoardPostPayload(),
            createdAt: Date(timeIntervalSince1970: createdAt),
            expiresAt: nil,
            canDelete: isOwn,
            tags: [],
            pinned: false,
            isOwn: isOwn,
            replies: replies
        )
    }
}
