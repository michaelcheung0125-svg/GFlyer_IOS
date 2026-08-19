import SwiftUI
import UIKit

struct MessageBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var board: MessageBoardController
    @ObservedObject var simulation: SimulationController
    @State private var query = ""
    @State private var selectedTag: String?
    @State private var showAdmin = false

    private var activePosts: [BoardPost] { board.posts.filter(\.isActive) }
    private var tags: [String] { Array(Set(activePosts.flatMap(\.tags))).sorted() }
    private var visiblePosts: [BoardPost] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return activePosts.filter { post in
            (selectedTag == nil || post.tags.contains(selectedTag!))
                && (normalized.isEmpty || post.searchText.contains(normalized))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !board.isConfigured {
                    ContentUnavailableView(
                        "留言板尚未設定",
                        systemImage: "exclamationmark.icloud",
                        description: Text("App 沒有有效的 HTTPS 留言板伺服器設定。")
                    )
                } else if board.member == nil {
                    if board.isLoading {
                        ProgressView("正在恢復留言板登入")
                    } else {
                        MessageBoardAccessView(board: board)
                    }
                } else {
                    postList
                }
            }
            .navigationTitle("留言板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if board.canManage {
                        Button { showAdmin = true } label: { Image(systemName: "shield") }
                            .accessibilityLabel("管理留言板")
                    }
                    Button { board.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(board.isLoading || board.member == nil)
                        .accessibilityLabel("重新整理留言板")
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdmin) { MessageBoardAdminView(board: board) }
            .onAppear {
                board.markVisible(true)
                if board.member != nil { board.refresh() }
            }
            .onDisappear { board.markVisible(false) }
            .alert(
                "留言板操作失敗",
                isPresented: Binding(
                    get: { board.errorMessage != nil },
                    set: { if !$0 { board.errorMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) { board.errorMessage = nil }
            } message: {
                Text(board.errorMessage ?? "未知錯誤")
            }
        }
    }

    private var postList: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(board.member?.username ?? "")
                            .font(.headline)
                        Text(board.member?.role.label ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("登出", role: .destructive) { board.leave() }
                }
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜尋留言、分享者、座標或路線", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("清除搜尋")
                    }
                }
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagButton("全部", tag: nil)
                            ForEach(tags, id: \.self) { tag in tagButton("#\(tag)", tag: tag) }
                        }
                    }
                }
            }

            if visiblePosts.isEmpty && !board.isLoading {
                ContentUnavailableView("目前沒有有效分享", systemImage: "bubble.left.and.bubble.right")
            } else {
                ForEach(visiblePosts) { post in
                    MessageBoardPostRow(
                        post: post,
                        canPin: board.canManage,
                        submitting: board.isSubmitting,
                        onPreview: { use(post, startImmediately: false) },
                        onStart: { use(post, startImmediately: true) },
                        onSave: { save(post) },
                        onReply: { board.reply(to: post.id, message: $0) },
                        onDeleteReply: board.deleteReply,
                        onDelete: { board.deletePost(post.id) },
                        onSetPinned: { board.setPinned(postID: post.id, pinned: $0) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { board.refresh() }
        .overlay {
            if board.isLoading && board.member != nil {
                ProgressView().padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func tagButton(_ title: String, tag: String?) -> some View {
        Button(title) { selectedTag = tag }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(selectedTag == tag ? Color.accentColor : Color.secondary)
    }

    private func use(_ post: BoardPost, startImmediately: Bool) {
        let succeeded: Bool
        switch post.kind {
        case .coordinate:
            succeeded = post.coordinate.map {
                simulation.previewBoardCoordinate($0, startImmediately: startImmediately)
            } ?? false
        case .route:
            succeeded = post.route.map {
                simulation.previewBoardRoute($0, startImmediately: startImmediately)
            } ?? false
        case .announcement:
            succeeded = false
        }
        if succeeded { dismiss() }
    }

    private func save(_ post: BoardPost) {
        if let coordinate = post.coordinate {
            let remark = post.remark.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = post.payload.name ?? (remark.isEmpty ? "\(post.authorName) 分享的位置" : remark)
            simulation.saveBoardCoordinate(coordinate, name: name)
        } else if let route = post.route {
            simulation.saveBoardRoute(route, authorName: post.authorName)
        }
    }
}

private struct MessageBoardAccessView: View {
    @ObservedObject var board: MessageBoardController
    @State private var code = ""
    @State private var adminMode = false

    var body: some View {
        Form {
            Section("加入私人留言板") {
                TextField("使用者名稱", text: $board.username)
                    .textInputAutocapitalization(.never)
                    .onChange(of: board.username) { _, value in
                        if value.count > 30 { board.username = String(value.prefix(30)) }
                    }
                if adminMode {
                    SecureField("管理員啟用碼（4 位數字）", text: $code)
                        .keyboardType(.numberPad)
                        .onChange(of: code) { _, value in
                            code = BoardInviteCodeNormalizer.normalizeAdminCode(value)
                        }
                } else {
                    TextField("朋友共用邀請碼", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) { _, value in
                            code = BoardInviteCodeNormalizer.normalize(value)
                        }
                }
                Toggle("以管理員身分啟用這台裝置", isOn: $adminMode)
                    .onChange(of: adminMode) { _, _ in code = "" }
                Button {
                    board.authenticate(code: code, username: board.username, asAdmin: adminMode)
                } label: {
                    if board.isSubmitting {
                        HStack { ProgressView(); Text("正在加入") }
                    } else {
                        Label(adminMode ? "啟用管理員" : "加入留言板", systemImage: "person.badge.key")
                    }
                }
                .disabled(
                    board.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (adminMode ? code.count != 4 : code.count < 4)
                        || board.isSubmitting
                )
            }
            Section {
                Text("使用者名稱會顯示給留言板成員。這部 iPhone 會建立獨立 session；登入 token 只保存在 iOS Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MessageBoardPostRow: View {
    let post: BoardPost
    let canPin: Bool
    let submitting: Bool
    let onPreview: () -> Void
    let onStart: () -> Void
    let onSave: () -> Void
    let onReply: (String) -> Void
    let onDeleteReply: (String) -> Void
    let onDelete: () -> Void
    let onSetPinned: (Bool) -> Void
    @State private var replyText = ""
    @State private var repliesExpanded = false
    @State private var showDeleteConfirmation = false
    @State private var savedFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if post.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                        Text(post.authorName).font(.headline)
                        Text(post.kind.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(expiryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if post.kind != .announcement {
                        Button {
                            onSave()
                            savedFeedback = true
                        } label: {
                            Label("儲存到本機", systemImage: "square.and.arrow.down")
                        }
                    }
                    if canPin {
                        Button { onSetPinned(!post.pinned) } label: {
                            Label(post.pinned ? "取消置頂" : "置頂", systemImage: post.pinned ? "pin.slash" : "pin")
                        }
                    }
                    if post.canDelete {
                        Button(role: .destructive) { showDeleteConfirmation = true } label: {
                            Label("刪除分享", systemImage: "trash")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("分享操作")
            }

            if !detail.isEmpty { Text(detail).font(.subheadline.weight(.medium)) }
            if !post.remark.isEmpty { Text(post.remark).font(.body) }

            if !post.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.tags, id: \.self) { tag in
                            Text("#\(tag)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if post.kind != .announcement {
                HStack(spacing: 8) {
                    Button(action: onPreview) {
                        Label(post.kind == .coordinate ? "查看" : "載入", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                    Button(action: onStart) {
                        Label(post.kind == .coordinate ? "傳送" : "開始路線", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        onSave()
                        savedFeedback = true
                    } label: {
                        Image(systemName: savedFeedback ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("儲存到本機")
                }
            }

            DisclosureGroup(isExpanded: $repliesExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(post.replies) { reply in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reply.authorName).font(.caption.weight(.semibold))
                                Text(reply.message).font(.subheadline)
                                Text(reply.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if reply.canDelete {
                                Button(role: .destructive) { onDeleteReply(reply.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("刪除回覆")
                            }
                        }
                        if reply.id != post.replies.last?.id { Divider() }
                    }
                    HStack {
                        TextField("輸入回覆", text: $replyText, axis: .vertical)
                            .lineLimit(1...3)
                            .onChange(of: replyText) { _, value in
                                if value.count > 300 { replyText = String(value.prefix(300)) }
                            }
                        Button {
                            let message = replyText
                            replyText = ""
                            onReply(message)
                        } label: { Image(systemName: "paperplane.fill") }
                            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                            .accessibilityLabel("送出回覆")
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("\(post.replies.count) 個回覆", systemImage: "bubble.left")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("確定刪除這個分享？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("刪除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) { }
        }
    }

    private var detail: String {
        switch post.kind {
        case .coordinate:
            return [post.payload.name, post.coordinate?.display].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .route:
            guard let route = post.route else { return "路線資料無效" }
            return "\(route.name) · \(route.points.count) 個座標點\(route.loop ? " · 循環" : "")"
        case .announcement:
            return "管理員公告"
        }
    }

    private var expiryLabel: String {
        let created = post.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard let expiry = post.expiresAt else { return "\(created) · 永久" }
        let minutes = max(Int(expiry.timeIntervalSinceNow / 60), 0)
        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(created) · 剩餘 \(hours > 0 ? "\(hours) 小時 " : "")\(remainder) 分鐘"
    }
}

struct ShareToMessageBoardView: View {
    private enum ContentKind: String, CaseIterable, Identifiable {
        case current = "目前座標"
        case favorite = "收藏座標"
        case route = "收藏路線"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var board: MessageBoardController
    @ObservedObject var simulation: SimulationController
    @State private var contentKind: ContentKind = .current
    @State private var selectedFavoriteID: UUID?
    @State private var selectedRouteID: UUID?
    @State private var duration: BoardShareDuration = .twelveHours
    @State private var remark = ""
    @State private var tags = ""

    private var selectedFavorite: SavedPlace? { simulation.favorites.first { $0.id == selectedFavoriteID } }
    private var selectedRoute: SavedRoute? { simulation.savedRoutes.first { $0.id == selectedRouteID } }
    private var currentCoordinate: GeoCoordinate { simulation.status.coordinate ?? simulation.selectedCoordinate }

    var body: some View {
        NavigationStack {
            Group {
                if !board.isConfigured {
                    ContentUnavailableView(
                        "留言板尚未設定",
                        systemImage: "exclamationmark.icloud",
                        description: Text("App 沒有有效的 HTTPS 留言板伺服器設定。")
                    )
                } else if board.member == nil {
                    MessageBoardAccessView(board: board)
                } else {
                    shareForm
                }
            }
            .navigationTitle("分享到留言板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear {
                selectedFavoriteID = selectedFavoriteID ?? simulation.favorites.first?.id
                selectedRouteID = selectedRouteID ?? simulation.savedRoutes.first?.id
            }
            .onChange(of: board.shareRevision) { oldValue, newValue in
                if newValue > oldValue { dismiss() }
            }
            .alert(
                "留言板操作失敗",
                isPresented: Binding(
                    get: { board.errorMessage != nil },
                    set: { if !$0 { board.errorMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) { board.errorMessage = nil }
            } message: { Text(board.errorMessage ?? "未知錯誤") }
        }
    }

    private var shareForm: some View {
        Form {
            Section("分享內容") {
                Picker("內容", selection: $contentKind) {
                    ForEach(ContentKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }
                .pickerStyle(.segmented)

                switch contentKind {
                case .current:
                    LabeledContent("目前座標", value: currentCoordinate.display)
                case .favorite:
                    if simulation.favorites.isEmpty {
                        Text("目前沒有收藏座標。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("收藏座標", selection: $selectedFavoriteID) {
                            ForEach(simulation.favorites) { place in
                                Text(place.name).tag(Optional(place.id))
                            }
                        }
                    }
                case .route:
                    if simulation.savedRoutes.isEmpty {
                        Text("目前沒有收藏路線。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("收藏路線", selection: $selectedRouteID) {
                            ForEach(simulation.savedRoutes) { route in
                                Text("\(route.name) · \(route.points.count) 點").tag(Optional(route.id))
                            }
                        }
                    }
                }
            }

            Section("分享設定") {
                Picker("期限", selection: $duration) {
                    ForEach(BoardShareDuration.allCases) { item in Text(item.label).tag(item) }
                }
                .pickerStyle(.segmented)
                TextField("留言或備註（選填）", text: $remark, axis: .vertical)
                    .lineLimit(3...5)
                    .onChange(of: remark) { _, value in
                        if value.count > 300 { remark = String(value.prefix(300)) }
                    }
                TextField("標籤，以逗號分隔（最多 5 個）", text: $tags)
                    .onChange(of: tags) { _, value in
                        if value.count > 120 { tags = String(value.prefix(120)) }
                    }
            }

            Section {
                Button(action: submit) {
                    if board.isSubmitting {
                        HStack { ProgressView(); Text("正在分享") }.frame(maxWidth: .infinity)
                    } else {
                        Label("發布到留言板", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                }
                .disabled(!hasContent || board.isSubmitting)
            }
        }
    }

    private var hasContent: Bool {
        switch contentKind {
        case .current: return true
        case .favorite: return selectedFavorite != nil
        case .route: return selectedRoute != nil
        }
    }

    private func submit() {
        let normalizedTags = BoardTagNormalizer.normalize(tags)
        switch contentKind {
        case .current:
            board.shareCoordinate(
                coordinate: currentCoordinate,
                name: nil,
                remark: remark,
                duration: duration,
                tags: normalizedTags
            )
        case .favorite:
            guard let place = selectedFavorite else { return }
            board.shareCoordinate(
                coordinate: place.coordinate,
                name: place.name,
                remark: remark,
                duration: duration,
                tags: normalizedTags
            )
        case .route:
            guard let route = selectedRoute else { return }
            board.shareRoute(route: route, remark: remark, duration: duration, tags: normalizedTags)
        }
    }
}

private struct MessageBoardAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var board: MessageBoardController
    @State private var inviteCode = ""
    @State private var showAnnouncement = false

    var body: some View {
        NavigationStack {
            List {
                Section("公告") {
                    Button { showAnnouncement = true } label: {
                        Label("發布置頂公告", systemImage: "megaphone")
                    }
                }

                Section("朋友共用邀請碼") {
                    TextField("4 至 32 個英文字母、數字、- 或 _", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: inviteCode) { _, value in
                            inviteCode = BoardInviteCodeNormalizer.normalize(value)
                        }
                    Button {
                        board.createInvitation(code: inviteCode)
                        inviteCode = ""
                    } label: { Label("設定新邀請碼", systemImage: "key") }
                        .disabled(inviteCode.count < 4 || board.isSubmitting)

                    ForEach(board.invitations) { invitation in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(invitation.label).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(invitation.revokedAt == nil ? "使用中" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(invitation.revokedAt == nil ? .green : .secondary)
                            }
                            Text("已使用 \(invitation.useCount) 次")
                                .font(.caption).foregroundStyle(.secondary)
                            if invitation.revokedAt == nil {
                                Button("停用", role: .destructive) { board.revokeInvitation(invitation.id) }
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section("已加入裝置") {
                    ForEach(board.managedMembers) { managed in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(managed.username).font(.headline)
                                Text(managed.role.label).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if managed.revokedAt != nil {
                                    Text("已撤銷").font(.caption).foregroundStyle(.red)
                                } else if managed.id != board.member?.id {
                                    Menu {
                                        if managed.role == .member {
                                            Button { board.promoteMember(managed.id) } label: {
                                                Label("設為管理員", systemImage: "shield")
                                            }
                                        }
                                        Button(role: .destructive) { board.revokeMember(managed.id) } label: {
                                            Label("撤銷裝置", systemImage: "trash")
                                        }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                }
                            }
                            Text(managed.deviceLabel.isEmpty ? "未知裝置" : managed.deviceLabel)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("最後使用：\(managed.lastActiveAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("留言板管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { board.refreshAdmin() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("重新整理管理資料")
                    Button("完成") { dismiss() }
                }
            }
            .overlay { if board.isLoading { ProgressView() } }
            .sheet(isPresented: $showAnnouncement) { BoardAnnouncementView(board: board) }
            .onAppear { board.refreshAdmin() }
            .alert(
                "邀請碼已設定",
                isPresented: Binding(
                    get: { board.generatedInviteCode != nil },
                    set: { if !$0 { board.clearGeneratedInviteCode() } }
                )
            ) {
                Button("複製") {
                    UIPasteboard.general.string = board.generatedInviteCode
                    board.clearGeneratedInviteCode()
                }
                Button("完成", role: .cancel) { board.clearGeneratedInviteCode() }
            } message: { Text(board.generatedInviteCode ?? "") }
            .alert(
                "留言板操作失敗",
                isPresented: Binding(
                    get: { board.errorMessage != nil },
                    set: { if !$0 { board.errorMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) { board.errorMessage = nil }
            } message: {
                Text(board.errorMessage ?? "未知錯誤")
            }
        }
    }
}

private struct BoardAnnouncementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var board: MessageBoardController
    @State private var message = ""
    @State private var duration: BoardShareDuration = .permanent
    @State private var tags = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("公告內容") {
                    TextField("輸入公告", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: message) { _, value in
                            if value.count > 300 { message = String(value.prefix(300)) }
                        }
                }
                Section("設定") {
                    Picker("期限", selection: $duration) {
                        ForEach(BoardShareDuration.allCases) { item in Text(item.label).tag(item) }
                    }.pickerStyle(.segmented)
                    TextField("標籤，以逗號分隔", text: $tags)
                }
            }
            .navigationTitle("發布公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("發布") {
                        board.createAnnouncement(
                            message: message,
                            duration: duration,
                            tags: BoardTagNormalizer.normalize(tags)
                        )
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || board.isSubmitting)
                }
            }
            .onChange(of: board.shareRevision) { oldValue, newValue in
                if newValue > oldValue { dismiss() }
            }
            .alert(
                "留言板操作失敗",
                isPresented: Binding(
                    get: { board.errorMessage != nil },
                    set: { if !$0 { board.errorMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) { board.errorMessage = nil }
            } message: {
                Text(board.errorMessage ?? "未知錯誤")
            }
        }
    }
}
