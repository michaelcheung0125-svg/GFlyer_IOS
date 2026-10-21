import MapKit
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: SimulationController
    @ObservedObject var edition: EditionModel
    @ObservedObject var airplaneAssist: AirplaneAssistController
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
    @State private var showAirplaneAssist = false
    @State private var isPanelExpanded = true
    /// 右側工具列收起後只剩一個貼在畫面右邊的箭咀，關掉 App 也記住
    @AppStorage("gflyer.map-toolbar-expanded") private var isToolBarExpanded = true
    @State private var suppressNextRecenter = false
    @State private var feedbackMessage: String?
    @State private var feedbackTask: Task<Void, Never>?
    /// 地圖工具列 ☆ 的命名 sheet:按 ☆ 那一刻記下的座標與預填。放在一直存在的這一層,
    /// 不放在 `MapToolBar`:工具列在搜尋結果出現時會離開畫面,打到一半的名稱會無聲消失
    /// (GFlyer-Suite docs/features/favorite-add.md §5)。名稱欄位的文字是 sheet 自己的狀態。只在記憶體,不存檔。
    @State private var favoriteNameRequest: FavoriteNameRequest?
    /// 定位要花幾秒，期間按鈕要換成轉圈，否則使用者不知道有沒有按到。
    @State private var isLocating = false
    @State private var locateTimeoutTask: Task<Void, Never>?
    @State private var cameraDistance: CLLocationDistance = 5_000
    /// 什麼時候把鏡頭縮放到整條探索預覽:上一次縮放時的起點(和 Android 的 `lastExplorationPreviewCenter`
    /// 相同)與剛縮放過、還要等控制面板排好版面的起點。
    @State private var explorationFit = ExplorationFitTrigger()
    /// 地圖、搜尋列與控制面板在 `mapArea` 座標空間裡的位置,用來算出地圖上沒被蓋住的那一塊。
    @State private var mapFrame: CGRect = .zero
    @State private var searchBarFrame: CGRect = .zero
    @State private var controlPanelFrame: CGRect = .zero
    @FocusState private var searchFieldFocused: Bool

    private static let mapArea = "mapArea"

    /// CI 的截圖步驟用 `xcrun simctl launch … -GFlyerScreenshotMode` 啟動 App。
    /// 只用來關掉會發出網路請求的啟動動作，不影響任何版面——否則截圖會隨著
    /// 線上有沒有新版本、留言板有沒有未讀而改變，看起來像版面動了。
    static let isCapturingScreenshots =
        ProcessInfo.processInfo.arguments.contains("-GFlyerScreenshotMode")

    // 這個畫面的 body 拆成幾層小的計算屬性。整串堆在一起時 Swift 的型別
    // 檢查器會在 MainView.body 上放棄（unable to type-check in reasonable
    // time），加新的 sheet 或 alert 前請維持這個分層。
    var body: some View {
        NavigationStack {
            contentWithNotices
                .alert(
                    "操作失敗",
                    isPresented: errorAlertBinding
                ) {
                    Button("確定", role: .cancel) { controller.lastError = nil }
                } message: {
                    Text(controller.lastError ?? "未知錯誤")
                }
                .alert(
                    CrossDateWarningText.title,
                    isPresented: crossDateAlertBinding,
                    presenting: controller.pendingCrossDateWarning
                ) { _ in
                    Button(CrossDateWarningText.confirmButton) { controller.confirmCrossDateStart() }
                    Button(CrossDateWarningText.cancelButton, role: .cancel) { controller.cancelCrossDateStart() }
                } message: { warning in
                    Text(CrossDateWarningText.message(for: warning))
                }
                .modifier(edition.mainScreenPresentations(simulation: controller, feedback: editionFeedback))
                .alert(
                    "恢復上次模擬？",
                    isPresented: resumeAlertBinding,
                    presenting: controller.pendingResumeSession
                ) { snapshot in
                    Button("恢復") { controller.resumeInterruptedSession(snapshot) }
                    Button("放棄", role: .cancel) { controller.discardInterruptedSession() }
                } message: { snapshot in
                    Text(Self.resumeMessage(for: snapshot))
                }
        }
        // 鍵盤彈出時整個畫面都不要被推上去。這一行要加在 NavigationStack
        // 外面：只加在裡面的 ZStack 上，搜尋列與右側工具列仍會被頂一下
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// 升級後只出現一次的提示與 ☆ 的命名 sheet。和其他 alert 分開一層,理由同 body 上面的說明。
    private var contentWithNotices: some View {
        contentWithSheets
            .alert(SimulationController.arrivalRulesNoticeTitle, isPresented: arrivalRulesNoticeBinding) {
                Button("知道了", role: .cancel) { controller.dismissArrivalRulesNotice() }
            } message: {
                Text(SimulationController.arrivalRulesNoticeMessage)
            }
            .modifier(FavoriteNameSheet(
                request: $favoriteNameRequest,
                lookUp: { await controller.favoriteNameLabel(for: $0) },
                onConfirm: confirmFavorite
            ))
    }

    private var contentWithSheets: some View {
        contentWithChrome
            .sheet(isPresented: $showSetup) {
                SetupView(controller: controller, edition: edition)
            }
            .sheet(isPresented: $showFavorites) { SavedPlacesView(controller: controller) }
            .sheet(isPresented: $showRoutes) { SavedRoutesView(controller: controller) }
            .sheet(isPresented: $showAirplaneAssist) {
                AirplaneAssistView(assist: airplaneAssist, simulation: controller)
            }
    }

    private var contentWithChrome: some View {
        contentStack
            // 搜尋列在畫面頂端，不需要鍵盤避讓；少了這行，鍵盤（或 sheet 關閉後
            // 殘留的鍵盤 inset）會把底部控制列往上頂到畫面中間。
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle("GFlyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { mainToolbar }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !Self.isCapturingScreenshots else { return }
                edition.appDidBecomeActive()
            }
            .onChange(of: controller.selectedCoordinate) { _, coordinate in
                if suppressNextRecenter {
                    suppressNextRecenter = false
                    return
                }
                // 探索模式沒有在探索時,選取點就是預覽的起點,鏡頭改由 fitExplorationPreviewIfNeeded 縮放
                guard explorationFitStart != coordinate else { return }
                position = .region(region(around: coordinate, span: 0.04))
            }
            .onChange(of: explorationFitStart) { _, _ in fitExplorationPreviewIfNeeded() }
            .onChange(of: controlPanelFrame) { _, _ in refitExplorationPreviewForPanel() }
            .onChange(of: isPanelExpanded) { _, expanded in
                if expanded { showJoystick = false }
            }
            .overlay(alignment: .top) { feedbackOverlay }
    }

    private var contentStack: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            if showJoystick {
                JoystickPad(controller: controller)
                    .frame(width: Layout.joystickDiameter, height: Layout.joystickDiameter)
                    .padding(.leading, Layout.joystickLeadingInset)
                    .padding(.bottom, isPanelExpanded ? Layout.joystickBottomInsetPanelExpanded : Layout.joystickBottomInsetPanelCollapsed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ControlPanel(controller: controller, isExpanded: $isPanelExpanded)
                .reportFrame(in: Self.mapArea) { controlPanelFrame = $0 }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)
        }
        // 用 overlay 把搜尋列與工具列釘在最上面，不參與 ZStack 的底部對齊
        .overlay(alignment: .top) { searchAndToolsLayer }
        .coordinateSpace(.named(Self.mapArea))
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: .all) {
                UserAnnotation()

                // 多點模式的點都畫成路線點；再畫選取位置只會多一個看似
                // 屬於路線、其實不在路線上的標記
                if controller.mode != .multiRoute {
                    // 定位針的針尖在圖的 96% 高度（scripts/make_brand_art.py），對準選取的座標
                    Annotation(
                        "選取位置",
                        coordinate: controller.selectedCoordinate.clLocationCoordinate,
                        anchor: UnitPoint(x: 0.5, y: 0.96)
                    ) {
                        Image("GFlyerMarker")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .shadow(radius: 2)
                    }
                }

                if let active = controller.status.coordinate {
                    Annotation("模擬位置", coordinate: active.clLocationCoordinate) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.white)
                            .padding(Spacing.sm)
                            .background(Color.statusActive, in: Circle())
                    }
                }

                ForEach(Array(controller.routePoints.enumerated()), id: \.offset) { index, point in
                    Marker("路線點 \(index + 1)", coordinate: point.clLocationCoordinate)
                        .tint(Color.routeStroke)
                }

                if controller.routePoints.count >= 2 {
                    MapPolyline(coordinates: controller.routePoints.map(\.clLocationCoordinate))
                        .stroke(Color.routeStroke, lineWidth: 4)
                }
                if controller.explorationPreview.count >= 2 {
                    MapPolyline(coordinates: controller.explorationPreview.map(\.clLocationCoordinate))
                        .stroke(Color.routeAlternate.opacity(0.75), style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            // 點地圖選點後立刻拖動，不要變成單指縮放
            .background(OneHandedZoomDisabler())
            .onTapGesture { point in
                // 點地圖同時收鍵盤，避免鍵盤佔住畫面又沒有明顯的關閉方式
                searchFieldFocused = false
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                // 一般點地圖不移動鏡頭;探索模式改了預覽起點時另外縮放到整條預覽(§3.5)
                suppressNextRecenter = true
                controller.select(GeoCoordinate(coordinate))
            }
        }
        .reportFrame(in: Self.mapArea) { mapFrame = $0 }
    }

    private var searchAndToolsLayer: some View {
        VStack(spacing: 0) {
            SearchBar(controller: controller, isFocused: $searchFieldFocused) { coordinate in
                guard explorationFitStart != coordinate else { return }
                position = .region(region(around: coordinate, span: 0.04))
            }
            // 只記沒有搜尋結果時的高度:選了結果之後清單才收起來,縮放時要用收起來的高度
            .reportFrame(in: Self.mapArea) { frame in
                if controller.searchResults.isEmpty { searchBarFrame = frame }
            }
            if controller.searchResults.isEmpty {
                HStack {
                    Spacer()
                    MapToolBar(
                        controller: controller,
                        airplaneAssist: airplaneAssist,
                        isExpanded: $isToolBarExpanded,
                        showJoystick: $showJoystick,
                        isPanelExpanded: $isPanelExpanded,
                        showFavorites: $showFavorites,
                        showRoutes: $showRoutes,
                        showAirplaneAssist: $showAirplaneAssist,
                        position: $position,
                        cameraDistance: $cameraDistance,
                        isLocating: isLocating,
                        editionItems: edition.mapToolItems(feedback: editionFeedback),
                        onLocate: locateCurrentPosition,
                        onFavorite: requestFavorite
                    )
                }
                .padding(.top, Spacing.sm)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        // 這一塊只佔自己的高度。之前用 Spacer 撐到畫面底再留 112 的底部內距，
        // 工具列展開時整塊比鍵盤讓出的空間還高，SwiftUI 放不下就把它往上推，
        // 搜尋列因此跳動；工具列收起時高度夠小，所以看起來沒事。
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let feedbackMessage {
            Text(feedbackMessage)
                .font(.labelEmphasis)
                .foregroundStyle(.primary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4, y: 2)
                .padding(.top, Layout.feedbackToastTopInset)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Label(
                controller.canControlDeviceLocation ? "裝置模式" : "預覽模式",
                systemImage: controller.canControlDeviceLocation ? "iphone.gen3" : "eye"
            )
            .font(.caption)
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: Spacing.sm) {
                Image("GFlyerIcon").resizable().scaledToFill().frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("GFlyer").font(.headline)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            edition.navigationBarButtons
            Button { showSetup = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("設定")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.lastError != nil },
            set: { if !$0 { controller.lastError = nil } }
        )
    }

    private var crossDateAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.pendingCrossDateWarning != nil },
            set: { if !$0 { controller.cancelCrossDateStart() } }
        )
    }

    private var resumeAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.pendingResumeSession != nil },
            set: { if !$0 { controller.clearResumePrompt() } }
        )
    }

    /// 啟動時可能同時有恢復、更新或錯誤的 alert;等它們都關掉才顯示,免得互相擋掉。
    private var arrivalRulesNoticeBinding: Binding<Bool> {
        Binding(
            get: {
                controller.playbackSettings.pendingArrivalRulesNotice
                    && controller.pendingResumeSession == nil
                    && controller.pendingCrossDateWarning == nil
                    && controller.lastError == nil
                    && !edition.isPresentingAlert
            },
            set: { if !$0 { controller.dismissArrivalRulesNotice() } }
        )
    }

    private static func resumeMessage(for snapshot: ActiveSessionSnapshot) -> String {
        let minutes = max(Int(Date().timeIntervalSince(snapshot.savedAt) / 60), 0)
        return "GFlyer 上次在「\(snapshot.mode.rawValue)」模式中斷（約 \(minutes) 分鐘前）。恢復會重新連線並從中斷位置繼續。"
    }

    private func region(around coordinate: GeoCoordinate, span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate.clLocationCoordinate,
                           span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }

    /// 探索模式、沒有在探索時的預覽起點;其他時候是 nil(不縮放)。
    private var explorationFitStart: GeoCoordinate? {
        ExplorationFitTrigger.fitStart(
            isExploreMode: controller.mode == .explore,
            isExploring: controller.isExploring,
            start: controller.explorationStart
        )
    }

    /// 沒有在探索時,預覽的起點一改變就把鏡頭縮放到整條預覽:切進探索、在探索模式點地圖或選搜尋結果、
    /// 模擬座標改變、探索停止後起點換回選取點都算。只改 Y 或方向不縮放,探索中也不縮放;停止、自動停止與
    /// 完整清除時起點直接是清除之後的那一個(`ExplorationRun.origin`),所以起點沒變就不動鏡頭
    /// (GFlyer-Suite docs/features/serpentine-exploration.md §3.5,和 Android `MainScreen.kt` 相同)。
    private func fitExplorationPreviewIfNeeded() {
        guard let start = explorationFit.startToFit(explorationFitStart, isExploreMode: controller.mode == .explore),
              fitCameraToExplorationPreview() else { return }
        explorationFit.didFit(start, now: ProcessInfo.processInfo.systemUptime)
    }

    /// 切進探索時控制面板在同一次更新裡換成探索的設定,新的高度比上面的縮放晚才量到;剛縮放過、起點沒變,
    /// 就用新的面板高度再縮放一次(`ExplorationFitTrigger.panelSettleSeconds`)。
    private func refitExplorationPreviewForPanel() {
        guard explorationFit.shouldRefitForPanel(
            currentStart: explorationFitStart,
            now: ProcessInfo.processInfo.systemUptime
        ) else { return }
        fitCameraToExplorationPreview()
    }

    /// 把鏡頭縮放到整條預覽,放在搜尋列與控制面板之間。還不知道地圖大小時不動,回傳 false。
    @discardableResult
    private func fitCameraToExplorationPreview() -> Bool {
        guard let rect = ExplorationCamera.visibleRect(
            for: controller.explorationPreview,
            mapSize: mapFrame.size,
            coveredTop: searchBarFrame.maxY - mapFrame.minY,
            coveredBottom: mapFrame.maxY - controlPanelFrame.minY
        ) else { return false }
        position = .rect(rect)
        return true
    }

    private func locateCurrentPosition() {
        // 連按沒有意義，第二次只會疊一個一樣的請求。
        guard !isLocating else { return }
        isLocating = true

        // 保險絲。`onFinish` 蓋得住成功與失敗，但權限還沒決定時
        // `requestCurrentLocation` 會把完成回呼收起來等使用者回答對話框，
        // 如果對話框被略過就永遠不會回來——沒有這一段，轉圈會一直轉下去。
        locateTimeoutTask?.cancel()
        locateTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            isLocating = false
        }

        controller.requestCurrentLocation(onFinish: {
            locateTimeoutTask?.cancel()
            locateTimeoutTask = nil
            isLocating = false
        }) { fix in
            cameraDistance = 5_000
            position = .region(region(around: fix.coordinate, span: 0.04))
            if fix.isSimulatedBySoftware {
                // 全機模擬生效時，「目前位置」就是模擬座標——照實說，
                // 不讓使用者誤以為定位到了真實位置
                announce(controller.status.isActive
                    ? "已定位到模擬位置"
                    : "仍在回報模擬座標，可到設定強制清除")
            } else {
                announce("已定位到目前位置")
            }
        }
    }

    /// 版本專屬的功能（`EditionModelFeatures`）在主畫面回報結果用。
    private var editionFeedback: MainScreenFeedback {
        MainScreenFeedback(announce: announce, reportError: { controller.lastError = $0 })
    }

    private func announce(_ message: String) {
        feedbackTask?.cancel()
        withAnimation(Motion.feedbackIn) { feedbackMessage = message }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.feedbackOut) {
                if feedbackMessage == message { feedbackMessage = nil }
            }
        }
    }

    /// 地圖工具列的 ☆:收藏目標座標已經收藏過就只顯示訊息;否則記下按下那一刻的座標與預填,打開命名 sheet
    /// (GFlyer-Suite docs/features/favorite-add.md §3.2、§3.4)。☆ 不轉圈、不等地名:沒有預填時由 sheet 自己插隊反查。
    private func requestFavorite() {
        switch controller.favoritePrompt() {
        case let .alreadySaved(message):
            announce(message)
        case let .askName(request):
            favoriteNameRequest = request
        }
    }

    /// 命名 sheet 的「收藏」:存 sheet 上顯示的那個座標(按 ☆ 時記下的),顯示回傳的訊息。
    private func confirmFavorite(name: String, coordinate: GeoCoordinate) {
        announce(controller.addFavorite(name: name, coordinate: coordinate))
    }
}

private struct SearchBar: View {
    @ObservedObject var controller: SimulationController
    @FocusState.Binding var isFocused: Bool
    let onChoose: (GeoCoordinate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋地點或輸入座標", text: $controller.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        controller.search()
                        isFocused = false
                    }
                if controller.isSearching { ProgressView().controlSize(.small) }
                if !controller.searchQuery.isEmpty {
                    Button { controller.searchQuery = ""; controller.search() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("清除搜尋")
                }
                if isFocused {
                    Button("取消") {
                        isFocused = false
                        controller.cancelSearch()
                    }
                    .font(.subheadline)
                } else {
                    Button { controller.search() } label: { Image(systemName: "arrow.right.circle.fill") }
                        .disabled(controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("搜尋")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.corner))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isFocused = false }
                }
            }

            if !controller.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(controller.searchResults) { result in
                            Button {
                                isFocused = false
                                controller.chooseSearchResult(result)
                                onChoose(result.coordinate)
                            } label: {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(result.title).font(.subheadline.weight(.medium))
                                    Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .frame(maxHeight: Layout.searchResultsMaxHeight)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.corner))
                .padding(.top, Spacing.xs)
            }
        }
    }
}

private struct MapToolBar: View {
    @ObservedObject var controller: SimulationController
    @ObservedObject var airplaneAssist: AirplaneAssistController
    @Binding var isExpanded: Bool
    @Binding var showJoystick: Bool
    @Binding var isPanelExpanded: Bool
    @Binding var showFavorites: Bool
    @Binding var showRoutes: Bool
    @Binding var showAirplaneAssist: Bool
    @Binding var position: MapCameraPosition
    @Binding var cameraDistance: CLLocationDistance
    let isLocating: Bool
    /// 版本專屬的按鈕(`EditionModelFeatures.mapToolItems`),接在「已儲存路線」後面
    let editionItems: [MapToolItem]
    let onLocate: () -> Void
    /// ☆ 只負責觸發;命名 sheet 與它的狀態在 `MainView`,理由見 `MainView.favoriteNameRequest`。
    let onFavorite: () -> Void

    var body: some View {
        if isExpanded {
            expandedToolBar
        } else {
            collapsedTab
        }
    }

    /// 收起後貼在畫面右邊的小箭咀，按一下把整列叫回來。
    private var collapsedTab: some View {
        Button { withAnimation(Motion.panel) { isExpanded = true } } label: {
            Image(systemName: "chevron.left")
                .font(.labelEmphasis)
                .foregroundStyle(Color.primary)
                // 高度留 46 不動：這是一個直立的拉出式頁籤，正方形會失去它的樣子。
                // 寬度原本 28，遠低於下限，那是整個 App 最難按中的一個目標。
                .frame(width: Metrics.tapTarget, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .background(
            .regularMaterial,
            in: UnevenRoundedRectangle(topLeadingRadius: Metrics.corner, bottomLeadingRadius: Metrics.corner)
        )
        // 抵銷外層的水平內距，讓它真的貼住畫面右邊。這個值沒有自己的意義，
        // 它必須永遠等於外層那個內距，所以直接寫同一個 token——先前外層換成
        // Spacing.md 之後這裡還留著 -12，箭咀就多突出去了 2pt。
        .padding(.trailing, -Spacing.md)
        .accessibilityLabel("展開地圖工具列")
    }

    private var expandedToolBar: some View {
        // 兩個一列。只剩一個的最後一列靠右，和收起後的箭咀同一邊
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            let items = toolItems
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                HStack(spacing: Spacing.xs) {
                    ForEach(items[start..<min(start + 2, items.count)]) { mapButton($0) }
                }
            }
        }
        .padding(Spacing.sm)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.corner))
        // 讓整塊工具列（含按鈕之間的空隙與內距）吃掉點擊，
        // 否則點到空隙會穿透到後面的地圖而變成選點
        .contentShape(RoundedRectangle(cornerRadius: Metrics.corner))
    }

    /// 由上到下、每列由左到右。
    private var toolItems: [MapToolItem] {
        let camera: [MapToolItem] = [
            MapToolItem(id: "zoom-in", icon: "plus", label: "放大") { zoom(0.5) },
            MapToolItem(id: "zoom-out", icon: "minus", label: "縮小") { zoom(2) },
            MapToolItem(id: "locate", icon: "location.fill", label: "前往目前位置", isBusy: isLocating, action: onLocate),
            MapToolItem(
                id: "joystick",
                icon: showJoystick ? "gamecontroller.fill" : "gamecontroller",
                label: "搖桿"
            ) {
                showJoystick.toggle()
                if showJoystick { isPanelExpanded = false }
            },
        ]
        // 實心 / 空心看選取點(和 Android 相同);按下去收藏的是收藏目標座標,模擬中是模擬位置
        let isFavorite = controller.favorites.contains { $0.coordinate == controller.selectedCoordinate }
        let places: [MapToolItem] = [
            MapToolItem(
                id: "favorite",
                icon: isFavorite ? "star.fill" : "star",
                label: FavoriteAddTexts.toolbarButtonLabel,
                action: onFavorite
            ),
            MapToolItem(id: "favorites", icon: "star.circle", label: "收藏與歷史") { showFavorites = true },
            MapToolItem(id: "routes", icon: "point.3.filled.connected.trianglepath.dotted", label: "已儲存路線") {
                showRoutes = true
            },
        ]
        let end: [MapToolItem] = [
            // 行動網絡下才需要飛航模式那串操作，所以只在偵測到行動網絡時強調它。
            MapToolItem(
                id: "airplane",
                icon: "airplane",
                label: "飛航模式輔助",
                tint: airplaneAssist.connection.needsAssist ? Color.statusAttention : nil
            ) { showAirplaneAssist = true },
            MapToolItem(id: "collapse", icon: "chevron.right", label: "收起地圖工具列") {
                withAnimation(Motion.panel) { isExpanded = false }
            },
        ]
        return camera + places + editionItems + end
    }

    private func mapButton(_ item: MapToolItem) -> some View {
        Button(action: item.action) {
            Group {
                if item.isBusy {
                    ProgressView()
                } else {
                    Image(systemName: item.icon)
                }
            }
            // .plain 的按鈕不會自動上 accent 色，所以未指定時維持原本的 primary
            .foregroundStyle(item.tint ?? Color.primary)
            .frame(width: Metrics.tapTarget, height: Metrics.tapTarget)
            // 沒有這行時，可點區域只有圖示筆畫本身而不是整個方框
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if let badge = item.badge {
                    // 和親友版留言板按鈕(`MessageBoardNavigationButton`)的未讀徽章同一個寫法:
                    // 系統紅是 iOS 未讀徽章的慣例,不是 statusDanger
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.xs)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(.red, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
        }
        // 原本是 .plain，那會連按壓高亮一起拿掉，所以按下去畫面毫無變化。
        .buttonStyle(PressFeedbackButtonStyle())
        .accessibilityLabel(item.label)
        .accessibilityValue(item.isBusy ? "定位中" : (item.badge ?? ""))
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
        VStack(spacing: Spacing.md) {
            // 整條橫列都是收合／展開的按鈕。原本只有那個箭頭圖示可以按，
            // 實機上回報很難按中——圖示本身大約只有 20pt 寬，而且 .borderless
            // 不會把周圍的空白算進可點範圍。現在標題、座標、狀態點、箭頭連同
            // 它們之間的空隙都能按，箭頭本身也補到 44pt。
            Button {
                withAnimation(Motion.panel) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(controller.status.message).font(.labelEmphasis)
                        Text(controller.status.coordinate?.display ?? controller.selectedCoordinate.display)
                            .font(.numericCaption).foregroundStyle(.secondary)
                        if controller.status.isActive, let stopAt = controller.status.autoStopAt {
                            Text("將於 \(stopAt.formatted(date: .omitted, time: .shortened)) 自動停止")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                    if controller.status.isActive {
                        Circle().fill(controller.status.isPaused ? Color.statusAttention : Color.statusOK).frame(width: Metrics.statusDot, height: Metrics.statusDot)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .frame(width: Metrics.tapTarget, height: Metrics.tapTarget)
                }
                .foregroundStyle(Color.primary)
                // 沒有這行時，橫列裡文字與圖示之間的空白按不到。
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFeedbackButtonStyle(scalesOnPress: false))
            // 不覆寫 accessibilityLabel：整條列的內容本來就是使用者要聽的狀態，
            // 換成「收合控制面板」反而把狀態訊息蓋掉。用 hint 補上按下去會怎樣。
            .accessibilityHint(isExpanded ? "收合控制面板" : "展開控制面板")

            if isExpanded {
                Picker("模式", selection: Binding(get: { controller.mode }, set: controller.setMode)) {
                    ForEach(SimulationMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)

                if controller.mode.isRoute { routeControls }
                if controller.mode == .explore { exploreControls }

                if controller.status.isActive { playbackActionButtons }

                HStack(spacing: Spacing.md) {
                    Button { controller.start() } label: {
                        Label(startButtonTitle, systemImage: "play.fill")
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
        .padding(Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.corner))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .alert("儲存路線", isPresented: $showSaveRoute) {
            TextField("路線名稱", text: $routeName)
            Button("儲存") { controller.saveRoute(name: routeName); routeName = "" }
            Button("取消", role: .cancel) { }
        } message: { Text("為目前路線點建立一個可重用的路線") }
    }

    private var routeControls: some View {
        VStack(spacing: Spacing.md) {
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
            // 單點路線不循環,和 Android 相同:循環與播放選項只在多點模式出現
            if controller.mode == .multiRoute {
                // 播放中的路線在開始時就定了循環設定,改了也不生效;和 Android 一樣停用
                Toggle("循環路線", isOn: Binding(get: { controller.loopRoute }, set: controller.setLoopRoute))
                    .disabled(controller.status.isPlayingRoute)
                if controller.loopRoute {
                    Picker("循環方式", selection: Binding(get: { controller.loopTransitionMode }, set: controller.setLoopTransitionMode)) {
                        ForEach(LoopTransitionMode.allCases) { mode in Text(mode.label).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(controller.status.isPlayingRoute)
                }
                advancedPlaybackOptions
            }
        }
    }

    private var advancedPlaybackOptions: some View {
        DisclosureGroup {
            VStack(spacing: Spacing.sm) {
                Picker("移動方式", selection: Binding(
                    get: { controller.playbackSettings.travelMode },
                    // 第一次切到定點傳送時預先選好繞圈(PlaybackSettings.selectTravelMode)
                    set: { value in controller.updatePlayback { $0.selectTravelMode(value) } }
                )) {
                    ForEach(RouteTravelMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                .pickerStyle(.segmented)
                // 到點動作與手動前進只在定點傳送使用;模擬移動到點不停,直接走向下一點(和 Android 相同)
                if controller.playbackSettings.travelMode == .teleport { teleportArrivalOptions }
            }
            .padding(.top, Spacing.sm)
            // 播放中改了也只影響下一趟,和 Android 一樣整組停用,免得以為已經生效
            .disabled(controller.status.isPlayingRoute)
        } label: {
            Label("進階播放選項", systemImage: "slider.horizontal.3").font(.caption)
        }
    }

    private var teleportArrivalOptions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("到點動作").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Spacing.sm) {
                ForEach(RoutePointAction.selectableCases) { action in pointActionButton(action) }
            }
            Toggle("每點手動前進", isOn: Binding(
                get: { controller.playbackSettings.manualAdvance },
                set: { value in controller.updatePlayback { $0.manualAdvance = value } }
            ))
            Text(controller.playbackSettings.manualAdvance
                 ? "傳送到每個路線點後停下，按「下一點」再繼續。"
                 : "傳送到點後停 \(controller.playbackSettings.dwellSeconds) 秒再動作（設定頁可調整）。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 兩個都沒選取時是 0.6.8 以前留下的「定點傳送 + 無動作」:照舊到點不做動作,和 Android 讀到 NONE
    /// 時一樣。選了其中一個之後就回不到無動作。其他人切到定點傳送時已經預先選好繞圈。
    private func pointActionButton(_ action: RoutePointAction) -> some View {
        let isSelected = controller.playbackSettings.pointAction == action
        return Button {
            controller.updatePlayback { $0.pointAction = action }
        } label: {
            Label(action.label ?? "", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Color.statusActive : Color.secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var playbackActionButtons: some View {
        VStack(spacing: Spacing.sm) {
            if let remaining = controller.status.countdownRemaining {
                Button { controller.skipStartCountdown() } label: {
                    Label("跳過倒數（\(remaining) 秒）", systemImage: "forward.end")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if controller.status.waitingManualAdvance {
                Button { controller.advanceToNextRoutePoint() } label: {
                    Label("下一點", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if controller.status.isOrbiting {
                Button { controller.skipOrbit() } label: {
                    Label("跳過繞圈", systemImage: "forward.end")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// 探索模式和 Android 一樣是「開始探索」;探索中再按一次是從目前位置重新開始。
    private var startButtonTitle: String {
        if controller.mode == .explore { return ExplorationTexts.startButton }
        return controller.status.isActive ? "重新開始" : "開始"
    }

    /// 蛇形探索的設定,文字和 Android 的 `ExplorationControls` 一字不差(GFlyer-Suite
    /// docs/features/serpentine-exploration.md §2、§3.9)。探索中(含暫停)Y 與方向都停用,速度可以即時調整。
    private var exploreControls: some View {
        let verticalLength = controller.playbackSettings.explorationVerticalLengthMetres
        let canEdit = !controller.isExploring
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(controller.status.isActive ? ExplorationTexts.activeTitle : ExplorationTexts.idleTitle)
                    .font(.caption)
                    .foregroundStyle(controller.status.isActive ? Color.statusActive : Color.secondary)
                // Android 這裡是選取點,不是模擬座標
                Text(controller.selectedCoordinate.display).font(.numericCaption)
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(ExplorationTexts.widthHint)
                    .font(.caption2)
                    .foregroundStyle(Color.statusDanger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(ExplorationTexts.horizontalSpacing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: Spacing.sm) {
                Text(ExplorationTexts.verticalLengthLabel).font(.labelEmphasis)
                Button { controller.adjustExplorationVerticalLength(by: -1) } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canEdit || verticalLength <= SerpentinePath.minVerticalLengthMetres)
                .accessibilityLabel(ExplorationTexts.decreaseVerticalLength)
                VStack(spacing: 0) {
                    Text(ExplorationTexts.verticalLength(verticalLength))
                        .font(.numericCaption)
                    Text(ExplorationTexts.previewDistance(verticalLengthMetres: verticalLength))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(minWidth: 84)
                Button { controller.adjustExplorationVerticalLength(by: 1) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canEdit || verticalLength >= SerpentinePath.maxVerticalLengthMetres)
                .accessibilityLabel(ExplorationTexts.increaseVerticalLength)
                // 剩下的寬度都給方向切換;窄螢幕上固定寬度會把整列擠出面板
                Picker("方向", selection: Binding(
                    get: { controller.playbackSettings.explorationDirection },
                    set: controller.setExplorationDirection
                )) {
                    ForEach(ExplorationDirection.allCases) { direction in Text(direction.label).tag(direction) }
                }
                .pickerStyle(.segmented)
                .disabled(!canEdit)
            }
            speedControls
        }
    }

    private var speedControls: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text("速度")
                Slider(value: Binding(get: {
                    SpeedScale.toSliderPosition(controller.speedKilometresPerHour)
                }, set: controller.setSpeedFromSlider), in: 0...1)
                Text(String(format: "%.1f km/h", controller.speedKilometresPerHour))
                    .font(.numericCaption).frame(width: 78, alignment: .trailing)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(controller.quickSpeedPresets) { preset in
                        Button(preset.name) { controller.applySpeedPreset(preset) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            if let hint = Edition.speedHint(kilometresPerHour: controller.speedKilometresPerHour) {
                Label(hint, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(Color.statusAttention)
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
                Circle().fill(Color.statusActive.opacity(0.72)).frame(width: radius * 0.72, height: radius * 0.72)
                    .offset(knob)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let vector = CGVector(dx: value.translation.width, dy: value.translation.height)
                    let maxLength = radius * 0.7
                    let length = min(CGFloat(hypot(vector.dx, vector.dy)), maxLength)
                    let angle = atan2(vector.dy, vector.dx)
                    knob = CGSize(width: cos(angle) * length, height: sin(angle) * length)
                    let rawMagnitude = maxLength > 0 ? Double(length / maxLength) : 0
                    let deadZone = 0.1
                    let magnitude = rawMagnitude <= deadZone
                        ? 0
                        : (rawMagnitude - deadZone) / (1 - deadZone)
                    controller.startJoystick(
                        bearingDegrees: Double(angle * 180 / .pi + 90).truncatingRemainder(dividingBy: 360),
                        magnitude: magnitude
                    )
                }
                .onEnded { _ in
                    knob = .zero
                    controller.stopJoystick()
                })
        }
        .accessibilityLabel("搖桿")
    }
}

private extension View {
    /// 把這個 view 在 `space` 座標空間裡的框交給 `action`:出現時一次,之後每次改變一次。
    func reportFrame(in space: String, _ action: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(space))
                Color.clear
                    .onAppear { action(frame) }
                    .onChange(of: frame) { _, newFrame in action(newFrame) }
            }
        }
    }
}
