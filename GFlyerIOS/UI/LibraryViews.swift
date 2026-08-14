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
                                    .accessibilityLabel("新增收藏資料夾")
                                    .alert("新增資料夾", isPresented: $showFolderPrompt) {
                                        TextField("資料夾名稱", text: $folderName)
                                        Button("新增") { _ = controller.createFavoriteFolder(name: folderName); folderName = "" }
                                        Button("取消", role: .cancel) { }
                                    }
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
                Button("取消", role: .cancel) { renamingPlaceID = nil }
            }
        }
    }

    private func placeRow(_ place: SavedPlace) -> some View {
        HStack(spacing: 10) {
            Button {
                controller.useSavedPlace(place)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).foregroundStyle(.primary)
                    Text(place.coordinate.display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).foregroundStyle(.primary)
                Text(place.coordinate.display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).foregroundStyle(.primary)
                                Text("\(route.points.count) 點 · \(route.loop ? "循環" : "單程")")
                                    .font(.caption).foregroundStyle(.secondary)
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
