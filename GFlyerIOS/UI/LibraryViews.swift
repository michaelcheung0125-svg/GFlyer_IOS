import SwiftUI

struct SavedPlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: SimulationController
    @State private var selectedTab = 0
    @State private var showFolderPrompt = false
    @State private var folderName = ""
    @State private var showRenamePrompt = false
    @State private var renamingPlaceID: UUID?
    @State private var placeName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("收藏內容", selection: $selectedTab) {
                    Text("收藏").tag(0)
                    Text("歷史").tag(1)
                }.pickerStyle(.segmented).padding()
                List {
                    if selectedTab == 0 {
                        Section("未分類") {
                            ForEach(controller.favorites.filter { $0.folderID == nil }) { place in
                                placeRow(place)
                            }
                        }
                        Section {
                            HStack {
                                Text("資料夾")
                                Spacer()
                                Button { showFolderPrompt = true } label: { Image(systemName: "folder.badge.plus") }
                                    .disabled(controller.favoriteFolders.count >= FavoriteFolder.maxCount)
                                    .accessibilityLabel("新增收藏資料夾")
                                    .alert("新增資料夾", isPresented: $showFolderPrompt) {
                                        TextField("資料夾名稱", text: $folderName)
                                        Button("新增") { _ = controller.createFavoriteFolder(name: folderName); folderName = "" }
                                        Button("取消", role: .cancel) { }
                                    }
                            }
                            if controller.favoriteFolders.count >= FavoriteFolder.maxCount {
                                Text("收藏資料夾最多 \(FavoriteFolder.maxCount) 個")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(controller.favoriteFolders) { folder in
                            Section(folder.name) {
                                ForEach(controller.favorites.filter { $0.folderID == folder.id }) { place in placeRow(place) }
                                Button("刪除資料夾", role: .destructive) { controller.removeFavoriteFolder(folder.id) }
                            }
                        }
                    } else {
                        Section("最近使用") {
                            ForEach(controller.history) { place in historyRow(place) }
                        }
                        if !controller.history.isEmpty {
                            Button("清除歷史", role: .destructive) { controller.clearHistory() }
                        }
                    }
                }.listStyle(.insetGrouped)
            }
            .navigationTitle("地點")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("重新命名收藏", isPresented: $showRenamePrompt) {
                TextField("收藏名稱", text: $placeName)
                Button("儲存") {
                    if let id = renamingPlaceID { controller.renameFavorite(id, name: placeName) }
                    renamingPlaceID = nil
                    placeName = ""
                }
                // 空白名稱不能儲存,和 Android 相同;真正把關的是 LocalDataStore.renameFavorite
                .disabled(placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("取消", role: .cancel) { renamingPlaceID = nil }
            }
        }
    }

    private func placeRow(_ place: SavedPlace) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                controller.useSavedPlace(place)
                dismiss()
            } label: {
                libraryRowLabel(place, savedPrefix: LibraryRowText.favoriteSavedPrefix)
            }
            .buttonStyle(.plain)
            Menu {
                Button("重新命名") {
                    renamingPlaceID = place.id
                    placeName = place.name
                    showRenamePrompt = true
                }
                Button("移至未分類") { controller.moveFavorite(place.id, folderID: nil) }
                ForEach(controller.favoriteFolders) { folder in
                    Button(folder.name) { controller.moveFavorite(place.id, folderID: folder.id) }
                }
                Divider()
                Button("刪除", role: .destructive) { controller.removeFavorite(place.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("收藏操作")
        }
    }

    private func historyRow(_ place: SavedPlace) -> some View {
        Button {
            controller.useSavedPlace(place)
            dismiss()
        } label: {
            // 定位歷史不送出查詢,標籤只來自快取(剛好和某個收藏落在同一格時才有)
            libraryRowLabel(place, savedPrefix: LibraryRowText.historySavedPrefix)
        }
    }

    /// 名稱一行;座標與「國家 · 城市」一行;「收藏於／定位於 <日期時間>」小字一行,不限行數。
    private func libraryRowLabel(_ place: SavedPlace, savedPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(place.name).foregroundStyle(.primary).lineLimit(1)
            Text(LibraryRowText.place(place.coordinate, labels: controller.regionLabels))
                .font(.numericCaption).foregroundStyle(.secondary).lineLimit(1)
            Text(LibraryRowText.saved(savedPrefix, at: place.createdAt))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SavedRoutesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: SimulationController

    var body: some View {
        NavigationStack {
            List {
                if controller.savedRoutes.isEmpty {
                    ContentUnavailableView("尚無儲存路線", systemImage: "point.3.connected.trianglepath.dotted")
                } else {
                    ForEach(controller.savedRoutes) { route in
                        Button {
                            controller.loadSavedRoute(route)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(route.name).foregroundStyle(.primary).lineLimit(1)
                                Text(LibraryRowText.route(route, labels: controller.regionLabels))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(LibraryRowText.saved(LibraryRowText.routeSavedPrefix, at: route.createdAt))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { controller.removeSavedRoute(route.id) } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("儲存路線")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

/// 收藏位置、定位歷史與收藏路線清單每一列的說明文字,和 Android 一字不差
/// (GFlyer-Suite docs/features/region-labels.md §3.8)。
enum LibraryRowText {
    static let favoriteSavedPrefix = "收藏於"
    static let historySavedPrefix = "定位於"
    static let routeSavedPrefix = "儲存於"

    /// 「25.033900, 121.564500  ·  臺灣 · 臺北市」:座標後面是兩個空白 + U+00B7 + 兩個空白,
    /// 和標籤內部的「 · 」不同。還沒查到標籤時只有座標。
    static func place(_ coordinate: GeoCoordinate, labels: [String: String]) -> String {
        let parts: [String?] = [coordinate.display, RegionLabel.label(in: labels, for: coordinate)]
        return parts.compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// 「12 個點 · 循環 · 臺灣 · 臺北市」:整條路線只看第一點的標籤,沒有就只有「12 個點 · 循環」。
    static func route(_ route: SavedRoute, labels: [String: String]) -> String {
        let summary = "\(route.points.count) 個點 · \(route.loop ? "循環" : "單程")"
        let parts: [String?] = [summary, route.points.first.flatMap { RegionLabel.label(in: labels, for: $0) }]
        return parts.compactMap { $0 }.joined(separator: RegionLabel.separator)
    }

    /// 「收藏於 2026年9月24日 下午1:40」:前綴、一個半形空白,再接系統語言與時區的中等日期 + 短時間,
    /// 和 Android 的 `DateFormat.getDateTimeInstance(MEDIUM, SHORT)` 相同。
    static func saved(_ prefix: String, at date: Date) -> String {
        "\(prefix) \(savedAtFormatter.string(from: date))"
    }

    private static let savedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
