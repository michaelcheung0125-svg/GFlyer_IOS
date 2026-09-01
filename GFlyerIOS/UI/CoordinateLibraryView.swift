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
                tabChips
                if !library.subcategories.isEmpty { subcategoryChips }
                searchField
                content
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
        .onAppear { library.loadIfNeeded() }
    }

    private var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(library.tabs, id: \.self) { tab in
                    Button {
                        library.selectedTab = tab
                        library.selectedSubcategoryID = nil
                    } label: {
                        Text(library.title(for: tab))
                            .font(.subheadline)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var subcategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("全部", selected: library.selectedSubcategoryID == nil) {
                    library.selectedSubcategoryID = nil
                }
                ForEach(library.subcategories) { subcategory in
                    chip(subcategory.name, selected: library.selectedSubcategoryID == subcategory.id) {
                        library.selectedSubcategoryID = subcategory.id
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    selected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        let coordinates = library.visibleCoordinates
        if library.library == nil {
            emptyState(
                icon: "books.vertical",
                title: library.isLoading ? "正在下載圖鑑資料…" : "尚未取得圖鑑資料",
                caption: "座標圖鑑需要網路下載一次資料，之後會保留在本機並自動更新。"
            )
        } else if coordinates.isEmpty {
            emptyState(
                icon: "square.stack.3d.up.slash",
                title: "沒有符合的座標",
                caption: emptyCaption
            )
        } else {
            List(coordinates) { coordinate in
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

    private func emptyState(icon: String, title: String, caption: String) -> some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func use(_ coordinate: LibraryCoordinate, startImmediately: Bool) {
        guard let geo = coordinate.geoCoordinate else {
            library.errorMessage = "這筆座標資料無效。"
            return
        }
        if simulation.previewExternalCoordinate(geo, startImmediately: startImmediately, sourceLabel: "圖鑑") {
            dismiss()
        } else {
            library.errorMessage = simulation.lastError
            simulation.lastError = nil
        }
    }
}

private struct LibraryCoordinateRow: View {
    @ObservedObject var library: CoordinateLibraryController
    let coordinate: LibraryCoordinate
    let onUse: (Bool) -> Void
    let onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
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
                HStack(spacing: 12) {
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
                        Button {
                            onReport()
                        } label: {
                            Label("回報資料過期", systemImage: "flag")
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
                    .foregroundStyle(.yellow)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("最愛")
        }
        .padding(.vertical, 3)
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var reminderBadge: some View {
        if let state = library.reminderState(for: coordinate) {
            switch state {
            case .ready:
                Label("可以再去了", systemImage: "checkmark.seal.fill")
                    .font(.caption2).foregroundStyle(.green)
            case let .waiting(nextAvailableAt, daysLeft, hoursLeft):
                Label(
                    "還要等 \(daysLeft) 天 \(hoursLeft) 小時（\(VisitReminder.format(nextAvailableAt))）",
                    systemImage: "clock"
                )
                .font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}

private struct ReportOutdatedSheet: View {
    let coordinate: LibraryCoordinate
    let onSubmit: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "資料過期"
    @State private var message = ""

    private let reasons = ["資料過期", "位置錯誤", "重複或無效", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("回報座標") {
                    Text(coordinate.name)
                    Picker("原因", selection: $reason) {
                        ForEach(reasons, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("補充說明（選填）", text: $message, axis: .vertical)
                        .lineLimit(3...5)
                }
                Section {
                    Text("回報是匿名的，只會送出座標編號、原因與說明，協助作者更新圖鑑資料。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("回報資料過期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出") {
                        onSubmit(reason, message)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
