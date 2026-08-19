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
        XCTAssertEqual(
            BoardTagNormalizer.normalize("#Raid, raid， night ,abcdefghijklmnopqrstuvw,extra,ignored"),
            ["Raid", "night", "abcdefghijklmnopqrst", "extra", "ignored"]
        )
        XCTAssertEqual(BoardInviteCodeNormalizer.normalize(" ab-c_12!? "), "AB-C_12")
        XCTAssertEqual(BoardInviteCodeNormalizer.normalizeAdminCode("a1２3-45"), "1345")
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
        XCTAssertEqual(controller.savedRoutes.map(\.name), [
            "Harbour route (Android user)",
            "Harbour route (Android user) 2",
        ])

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
