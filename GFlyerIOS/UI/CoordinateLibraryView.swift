import SwiftUI

struct CoordinateLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: CoordinateLibraryController
    // 只在按鈕動作中呼叫，不觀察：模擬狀態每 250ms 更新，觀察會讓整個清單跟著重繪
    let simulation: SimulationController
    @State private var reportTarget: LibraryCoordinate?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                tabChips
                if !library.subcategories.isEmpty { subcategoryChips }
                searchField
                let listing = library.listing
                // 圖鑑資料還沒載入時不顯示;「⏲ 提醒中」分頁沒有 countLabel,整列不顯示
                if library.library != nil, let countLabel = listing.countLabel {
                    hideTeleportedRow(countLabel: countLabel)
                }
                content(listing)
            }
            .navigationTitle("座標圖鑑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        library.refreshManually()
                    } label: {
                        if library.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(library.isLoading)
                    .accessibilityLabel("更新圖鑑資料")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $reportTarget) { coordinate in
                ReportOutdatedSheet(coordinate: coordinate) { reason, message in
                    library.reportOutdated(coordinate, reason: reason, message: message)
                }
            }
            .alert(
                "座標圖鑑",
                isPresented: Binding(
                    get: { library.infoMessage != nil || library.errorMessage != nil },
                    set: { if !$0 { library.infoMessage = nil; library.errorMessage = nil } }
                )
            ) {
                Button("確定", role: .cancel) {
                    library.infoMessage = nil
                    library.errorMessage = nil
                }
            } message: {
                Text(library.errorMessage ?? library.infoMessage ?? "")
            }
        }
        .onAppear {
            library.loadIfNeeded()
            library.markNewCoordinatesSeen()
        }
        // 開著時拿到的新座標會直接出現在清單上，關閉時也算看過（coordinate-library-new-badge.md 3.2）
        .onDisappear { library.markNewCoordinatesSeen() }
    }

    /// 圖鑑頂端的兩行小字，和 Android 一字不差（GFlyer-Suite docs/features/coordinate-library-refresh.md 3.5）：
    /// 「更新」是資料最後一次有變動的日期，官網沒有新資料時不會變；第二行的最後檢查時間讓人看得出有在檢查。
    @ViewBuilder
    private var statusHeader: some View {
        if let current = library.library {
            VStack(alignment: .leading, spacing: 2) {
                Text(CoordinateLibraryStatusText.summary(current))
                Text(CoordinateLibraryStatusText.checked(library.lastCheckedAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)
        }
    }

    private var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(library.tabs, id: \.self) { tab in
                    Button {
                        library.selectedTab = tab
                        library.selectedSubcategoryID = nil
                    } label: {
                        Text(library.title(for: tab))
                            .font(.subheadline)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                library.selectedTab == tab
                                    ? Color.accentColor.opacity(0.18)
                                    : Color(uiColor: .secondarySystemBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    private var subcategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                chip("全部", selected: library.selectedSubcategoryID == nil) {
                    library.selectedSubcategoryID = nil
                }
                ForEach(library.subcategories) { subcategory in
                    chip(subcategory.name, selected: library.selectedSubcategoryID == subcategory.id) {
                        library.selectedSubcategoryID = subcategory.id
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    selected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜尋名稱或說明", text: $library.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !library.searchText.isEmpty {
                Button { library.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("清除搜尋")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: Metrics.corner))
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    /// 搜尋框下方、清單上方;清單是空的時候也顯示(「已前往 0 / 0」)。
    private func hideTeleportedRow(countLabel: String) -> some View {
        HStack(spacing: Spacing.md) {
            chip(
                library.hideTeleported ? LibraryTeleportHistory.hideToggleOn : LibraryTeleportHistory.hideToggleOff,
                selected: library.hideTeleported
            ) {
                library.setHideTeleported(!library.hideTeleported)
            }
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private func content(_ listing: LibraryTeleportListing) -> some View {
        if library.library == nil {
            emptyState(
                icon: "books.vertical",
                title: library.isLoading ? "正在下載圖鑑資料…" : "尚未取得圖鑑資料",
                caption: "座標圖鑑需要網路下載一次資料，之後會保留在本機並自動更新。"
            )
        } else if listing.isEmptyBecauseAllTeleported {
            emptyState(
                icon: "eye.slash",
                title: LibraryTeleportHistory.allTeleportedEmpty,
                caption: nil
            )
        } else if listing.visible.isEmpty {
            emptyState(
                icon: "square.stack.3d.up.slash",
                title: LibraryTeleportHistory.noMatchEmpty,
                caption: emptyCaption
            )
        } else {
            List(listing.visible) { coordinate in
                LibraryCoordinateRow(
                    library: library,
                    coordinate: coordinate,
                    onUse: { startImmediately in use(coordinate, startImmediately: startImmediately) },
                    onReport: { reportTarget = coordinate }
                )
            }
            .listStyle(.plain)
        }
    }

    private var emptyCaption: String {
        switch library.selectedTab {
        case .favorites: return "在座標上按星號即可加入最愛。"
        case .reminders: return "標記「已去過」且該座標有提醒天數時，會出現在這裡。"
        case .category: return "換一個分類或清除搜尋條件試試。"
        }
    }

    private func emptyState(icon: String, title: String, caption: String?) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title)
                .font(.labelEmphasis)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// 「傳送」的前往紀錄在關閉之前就記好了(`CoordinateLibraryController.use`)。
    private func use(_ coordinate: LibraryCoordinate, startImmediately: Bool) {
        if library.use(coordinate, startImmediately: startImmediately, simulation: simulation) {
            dismiss()
        }
    }
}

private struct LibraryCoordinateRow: View {
    @ObservedObject var library: CoordinateLibraryController
    let coordinate: LibraryCoordinate
    let onUse: (Bool) -> Void
    let onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    if let icon = coordinate.icon { Text(icon) }
                    Text(coordinate.name).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                if !coordinate.note.isEmpty {
                    Text(coordinate.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !coordinate.period.isEmpty {
                    Text(coordinate.period).font(.caption2).foregroundStyle(.secondary)
                }
                reminderBadge
                teleportSummary
                HStack(spacing: Spacing.md) {
                    Button("預覽") { onUse(false) }
                    Button("傳送") { onUse(true) }
                    Menu {
                        Button {
                            library.markVisited(coordinate.id)
                        } label: {
                            Label("標記已去過（現在）", systemImage: "checkmark.circle")
                        }
                        if library.marks[coordinate.id] != nil {
                            Button(role: .destructive) {
                                library.clearMark(coordinate.id)
                            } label: {
                                Label("清除到訪標記", systemImage: "xmark.circle")
                            }
                        }
                        if coordinate.canReportOutdated {
                            Button {
                                onReport()
                            } label: {
                                Label("回報資料已過時", systemImage: "exclamationmark.triangle")
                            }
                        }
                        // iOS 沒有詳情頁:完整時間當 Section 標題,「清除紀錄」放在它底下,
                        // 和上面的「清除到訪標記」分開。清除後不彈提示,列上那一行消失就是回饋。
                        if let record = library.teleports[coordinate.id] {
                            Section(
                                LibraryTeleportHistory.summary(
                                    record,
                                    time: LibraryTeleportHistory.formatFull(epochMs: record.lastAtEpochMs)
                                )
                            ) {
                                Button(role: .destructive) {
                                    library.clearTeleport(coordinate.id)
                                } label: {
                                    Label(LibraryTeleportHistory.clearButton, systemImage: "arrow.uturn.backward.circle")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
            Button {
                library.toggleFavorite(coordinate.id)
            } label: {
                Image(systemName: library.favorites.contains(coordinate.id) ? "star.fill" : "star")
                    .foregroundStyle(Color.statusFavorite)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("最愛")
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = coordinate.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").foregroundStyle(.secondary)
                default:
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        }
    }

    /// 有前往紀錄才多這一行;同一年省略年份,時區與「現在」都是畫面繪製當下的。
    @ViewBuilder
    private var teleportSummary: some View {
        if let record = library.teleports[coordinate.id] {
            Text(
                LibraryTeleportHistory.summary(
                    record,
                    time: LibraryTeleportHistory.formatShort(epochMs: record.lastAtEpochMs)
                )
            )
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var reminderBadge: some View {
        if let state = library.reminderState(for: coordinate) {
            switch state {
            case .ready:
                Label("可以再去了", systemImage: "checkmark.seal.fill")
                    .font(.caption2).foregroundStyle(Color.statusOK)
            case let .waiting(nextAvailableAt, daysLeft, hoursLeft):
                Label(
                    "還要等 \(daysLeft) 天 \(hoursLeft) 小時（\(VisitReminder.format(nextAvailableAt))）",
                    systemImage: "clock"
                )
                .font(.caption2).foregroundStyle(Color.statusAttention)
            }
        }
    }
}

/// 文字、原因與預設值照 Android 的詳情彈窗(GFlyer-Suite docs/features/coordinate-stale-report.md)。
/// 每次打開都是預設值;送出後立刻關閉,在背景送出。
private struct ReportOutdatedSheet: View {
    let coordinate: LibraryCoordinate
    let onSubmit: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = OutdatedReport.reasons[0]
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("回報座標") {
                    Text(coordinate.name)
                    Picker("原因", selection: $reason) {
                        ForEach(OutdatedReport.reasons, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("補充說明（選填）", text: $message, axis: .vertical)
                        .lineLimit(3...5)
                        .onChange(of: message) { _, value in
                            if let capped = value.codePointsCapped(at: BoardTextLimits.reportMessage) {
                                message = capped
                            }
                        }
                }
            }
            .navigationTitle("回報資料已過時")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出回報") {
                        onSubmit(reason, message)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
