import MapKit
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: SimulationController
    @ObservedObject var messageBoard: MessageBoardController
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )
    @State private var showSetup = false
    @State private var showFavorites = false
    @State private var showRoutes = false
    @State private var showJoystick = false
    @State private var showMessageBoard = false
    @State private var showBoardShare = false
    @State private var isPanelExpanded = true
    @State private var suppressNextRecenter = false
    @State private var feedbackMessage: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var cameraDistance: CLLocationDistance = 5_000

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position, interactionModes: .all) {
                        UserAnnotation()

                        Annotation("選取位置", coordinate: controller.selectedCoordinate.clLocationCoordinate) {
                            Image("GFlyerMarker")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .shadow(radius: 2)
                        }

                        if let active = controller.status.coordinate {
                            Annotation("模擬位置", coordinate: active.clLocationCoordinate) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.blue, in: Circle())
                            }
                        }

                        ForEach(Array(controller.routePoints.enumerated()), id: \.offset) { index, point in
                            Marker("路線點 \(index + 1)", coordinate: point.clLocationCoordinate)
                                .tint(.orange)
                        }

                        if controller.routePoints.count >= 2 {
                            MapPolyline(coordinates: controller.routePoints.map(\.clLocationCoordinate))
                                .stroke(.orange, lineWidth: 4)
                        }
                        if controller.explorationPreview.count >= 2 {
                            MapPolyline(coordinates: controller.explorationPreview.map(\.clLocationCoordinate))
                                .stroke(.purple.opacity(0.75), style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        suppressNextRecenter = true
                        controller.select(GeoCoordinate(coordinate))
                    }
                }

                VStack(spacing: 0) {
                    SearchBar(controller: controller) { coordinate in
                        position = .region(region(around: coordinate, span: 0.04))
                    }
                    if controller.searchResults.isEmpty {
                        HStack {
                        Spacer()
                        MapToolBar(
                            controller: controller,
                            showJoystick: $showJoystick,
                            isPanelExpanded: $isPanelExpanded,
                            showFavorites: $showFavorites,
                            showRoutes: $showRoutes,
                            showBoardShare: $showBoardShare,
                            position: $position,
                            cameraDistance: $cameraDistance,
                            onLocate: locateCurrentPosition,
                            onFeedback: announce
                        )
                        }
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 112)

                if showJoystick {
                    JoystickPad(controller: controller)
                        .frame(width: 132, height: 132)
                        .padding(.leading, 18)
                        .padding(.bottom, isPanelExpanded ? 258 : 120)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ControlPanel(controller: controller, isExpanded: $isPanelExpanded)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .navigationTitle("GFlyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label(
                        controller.canControlDeviceLocation ? "裝置模式" : "預覽模式",
                        systemImage: controller.canControlDeviceLocation ? "iphone.gen3" : "eye"
                    )
                    .font(.caption)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image("GFlyerIcon").resizable().scaledToFill().frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text("GFlyer").font(.headline)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showMessageBoard = true } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .overlay(alignment: .topTrailing) {
                                if messageBoard.unreadCount > 0 {
                                    Text(messageBoard.unreadCount > 99 ? "99+" : "\(messageBoard.unreadCount)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .background(.red, in: Capsule())
                                        .offset(x: 8, y: -8)
                                }
                            }
                    }
                    .accessibilityLabel("留言板，\(messageBoard.unreadCount) 個未讀項目")
                    Button { showSetup = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showSetup) { SetupView(controller: controller) }
            .sheet(isPresented: $showFavorites) { SavedPlacesView(controller: controller) }
            .sheet(isPresented: $showRoutes) { SavedRoutesView(controller: controller) }
            .sheet(isPresented: $showMessageBoard) {
                MessageBoardView(board: messageBoard, simulation: controller)
            }
            .sheet(isPresented: $showBoardShare) {
                ShareToMessageBoardView(board: messageBoard, simulation: controller)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { messageBoard.refreshInBackground() }
            }
            .onChange(of: controller.selectedCoordinate) { _, coordinate in
                if suppressNextRecenter {
                    suppressNextRecenter = false
                    return
                }
                position = .region(region(around: coordinate, span: 0.04))
            }
            .onChange(of: isPanelExpanded) { _, expanded in
                if expanded { showJoystick = false }
            }
            .overlay(alignment: .top) {
                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 4, y: 2)
                        .padding(.top, 84)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert(
                "操作失敗",
                isPresented: Binding(
                    get: { controller.lastError != nil },
                    set: { if !$0 { controller.lastError = nil } }
                )
            ) {
                Button("確定", role: .cancel) { controller.lastError = nil }
            } message: {
                Text(controller.lastError ?? "未知錯誤")
            }
        }
    }

    private func region(around coordinate: GeoCoordinate, span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate.clLocationCoordinate,
                           span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }

    private func locateCurrentPosition() {
        controller.requestCurrentLocation { coordinate in
            cameraDistance = 5_000
            position = .region(region(around: coordinate, span: 0.04))
            announce("已定位到目前位置")
        }
    }

    private func announce(_ message: String) {
        feedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { feedbackMessage = message }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                if feedbackMessage == message { feedbackMessage = nil }
            }
        }
    }
}

private struct SearchBar: View {
    @ObservedObject var controller: SimulationController
    let onChoose: (GeoCoordinate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋地點或輸入座標", text: $controller.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { controller.search() }
                if controller.isSearching { ProgressView().controlSize(.small) }
                if !controller.searchQuery.isEmpty {
                    Button { controller.searchQuery = ""; controller.search() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("清除搜尋")
                }
                Button { controller.search() } label: { Image(systemName: "arrow.right.circle.fill") }
                    .disabled(controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("搜尋")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            if !controller.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(controller.searchResults) { result in
                            Button {
                                controller.chooseSearchResult(result)
                                onChoose(result.coordinate)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).font(.subheadline.weight(.medium))
                                    Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            }
        }
    }
}

private struct MapToolBar: View {
    @ObservedObject var controller: SimulationController
    @Binding var showJoystick: Bool
    @Binding var isPanelExpanded: Bool
    @Binding var showFavorites: Bool
    @Binding var showRoutes: Bool
    @Binding var showBoardShare: Bool
    @Binding var position: MapCameraPosition
    @Binding var cameraDistance: CLLocationDistance
    let onLocate: () -> Void
    let onFeedback: (String) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                mapButton("plus", label: "放大") { zoom(0.5) }
                mapButton("minus", label: "縮小") { zoom(2) }
            }
            HStack(spacing: 4) {
                mapButton("location.fill", label: "前往目前位置", action: onLocate)
                mapButton(showJoystick ? "gamecontroller.fill" : "gamecontroller", label: "搖桿") {
                    showJoystick.toggle()
                    if showJoystick { isPanelExpanded = false }
                }
            }
            HStack(spacing: 4) {
                let isFavorite = controller.favorites.contains { $0.coordinate == controller.selectedCoordinate }
                mapButton(isFavorite ? "star.fill" : "star", label: "收藏目前位置") {
                    controller.addFavorite()
                    onFeedback(isFavorite ? "已更新收藏位置" : "已加入收藏")
                }
                mapButton("star.circle", label: "收藏與歷史") { showFavorites = true }
            }
            HStack(spacing: 4) {
                mapButton("point.3.filled.connected.trianglepath.dotted", label: "已儲存路線") { showRoutes = true }
                mapButton("square.and.arrow.up", label: "分享到留言板") { showBoardShare = true }
            }
        }
        .padding(6)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func mapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 32, height: 32) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func zoom(_ factor: Double) {
        cameraDistance = min(max(cameraDistance * factor, 250), 100_000)
        position = .camera(MapCamera(centerCoordinate: controller.selectedCoordinate.clLocationCoordinate,
                                     distance: cameraDistance,
                                     heading: 0,
                                     pitch: 0))
    }
}

private struct ControlPanel: View {
    @ObservedObject var controller: SimulationController
    @Binding var isExpanded: Bool
    @State private var showSaveRoute = false
    @State private var routeName = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.status.message).font(.subheadline.weight(.semibold))
                    Text(controller.status.coordinate?.display ?? controller.selectedCoordinate.display)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.status.isActive {
                    Circle().fill(controller.status.isPaused ? .orange : .green).frame(width: 10, height: 10)
                }
                Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "收合控制面板" : "展開控制面板")
            }

            if isExpanded {
                Picker("模式", selection: Binding(get: { controller.mode }, set: controller.setMode)) {
                    ForEach(SimulationMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)

                if controller.mode.isRoute { routeControls }
                if controller.mode == .explore { exploreControls }

                HStack(spacing: 10) {
                    Button { controller.start() } label: {
                        Label(controller.status.isActive ? "重新開始" : "開始", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button { controller.togglePause() } label: {
                        Image(systemName: controller.status.isPaused ? "play.fill" : "pause.fill")
                    }.buttonStyle(.bordered).disabled(!controller.status.isActive)
                        .accessibilityLabel(controller.status.isPaused ? "繼續" : "暫停")
                    Button(role: .destructive) { controller.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.bordered)
                        .disabled(!controller.status.isActive && !controller.canControlDeviceLocation)
                        .accessibilityLabel("停止")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .alert("儲存路線", isPresented: $showSaveRoute) {
            TextField("路線名稱", text: $routeName)
            Button("儲存") { controller.saveRoute(name: routeName); routeName = "" }
            Button("取消", role: .cancel) { }
        } message: { Text("為目前路線點建立一個可重用的路線") }
    }

    private var routeControls: some View {
        VStack(spacing: 9) {
            HStack {
                Label("\(controller.routePoints.count) 個路線點", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                Spacer()
                Button { controller.removeLastRoutePoint() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(controller.routePoints.isEmpty).accessibilityLabel("移除最後路線點")
                Button(role: .destructive) { controller.clearRoute() } label: { Image(systemName: "trash") }
                    .disabled(controller.routePoints.isEmpty).accessibilityLabel("清除路線")
                Button {
                    routeName = ""
                    showSaveRoute = true
                } label: { Image(systemName: "square.and.arrow.down") }
                    .disabled(controller.routePoints.count < 2).accessibilityLabel("儲存路線")
            }
            speedControls
            Toggle("循環路線", isOn: Binding(get: { controller.loopRoute }, set: controller.setLoopRoute))
            if controller.loopRoute {
                Picker("循環方式", selection: Binding(get: { controller.loopTransitionMode }, set: controller.setLoopTransitionMode)) {
                    ForEach(LoopTransitionMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented)
            }
        }
    }

    private var exploreControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("以選取位置為中心持續螺旋探索", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.secondary)
            speedControls
        }
    }

    private var speedControls: some View {
        VStack(spacing: 6) {
            HStack {
                Text("速度")
                Slider(value: Binding(get: {
                    SpeedScale.toSliderPosition(controller.speedKilometresPerHour)
                }, set: controller.setSpeedFromSlider), in: 0...1)
                Text(String(format: "%.1f km/h", controller.speedKilometresPerHour))
                    .font(.caption.monospacedDigit()).frame(width: 78, alignment: .trailing)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(controller.quickSpeedPresets) { preset in
                        Button(preset.name) { controller.applySpeedPreset(preset) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            if SpeedScale.exceedsFlowerLimit(controller.speedKilometresPerHour) {
                Label("速度高於 20 km/h，部分遊戲可能忽略定位更新", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}

private struct JoystickPad: View {
    @ObservedObject var controller: SimulationController
    @State private var knob = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                Circle().fill(.regularMaterial).overlay(Circle().stroke(.secondary.opacity(0.35), lineWidth: 1))
                Circle().fill(.blue.opacity(0.72)).frame(width: radius * 0.72, height: radius * 0.72)
                    .offset(knob)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let vector = CGVector(dx: value.translation.width, dy: value.translation.height)
                    let length = min(CGFloat(hypot(vector.dx, vector.dy)), radius * 0.7)
                    let angle = atan2(vector.dy, vector.dx)
                    knob = CGSize(width: cos(angle) * length, height: sin(angle) * length)
                    controller.startJoystick(bearingDegrees: Double(angle * 180 / .pi + 90).truncatingRemainder(dividingBy: 360))
                }
                .onEnded { _ in
                    knob = .zero
                    controller.stopJoystick()
                })
        }
        .accessibilityLabel("搖桿")
    }
}
