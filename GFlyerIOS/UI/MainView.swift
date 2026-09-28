import MapKit
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: SimulationController
    @ObservedObject var messageBoard: MessageBoardController
    @ObservedObject var coordinateLibrary: CoordinateLibraryController
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject var stepRecorder: StepRecorderController
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
    @State private var showMessageBoard = false
    @State private var showBoardShare = false
    @State private var showLibrary = false
    @State private var showStepRecorder = false
    @State private var showAirplaneAssist = false
    @State private var isPanelExpanded = true
    /// 右側工具列收起後只剩一個貼在畫面右邊的箭咀，關掉 App 也記住
    @AppStorage("gflyer.map-toolbar-expanded") private var isToolBarExpanded = true
    @State private var suppressNextRecenter = false
    @State private var feedbackMessage: String?
    @State private var feedbackTask: Task<Void, Never>?
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
                    "跨日期提醒",
                    isPresented: crossDateAlertBinding,
                    presenting: controller.pendingCrossDateWarning
                ) { _ in
                    Button("仍要傳送") { controller.confirmCrossDateStart() }
                    Button("取消", role: .cancel) { controller.cancelCrossDateStart() }
                } message: { warning in
                    Text(Self.crossDateMessage(for: warning))
                }
                .alert(
                    "有新版本",
                    isPresented: $updateChecker.showsPrompt,
                    presenting: updateChecker.availableUpdate
                ) { update in
                    Button("用 SideStore 更新") { updateChecker.openInstaller(for: update) }
                    Button("今日不再顯示") { updateChecker.snoozeForToday() }
                    Button("稍後", role: .cancel) { updateChecker.dismissPrompt() }
                } message: { update in
                    Text(updateMessage(for: update))
                }
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

    /// 升級後只出現一次的提示。和其他 alert 分開一層,理由同 body 上面的說明。
    private var contentWithNotices: some View {
        contentWithSheets
            .alert(SimulationController.arrivalRulesNoticeTitle, isPresented: arrivalRulesNoticeBinding) {
                Button("知道了", role: .cancel) { controller.dismissArrivalRulesNotice() }
            } message: {
                Text(SimulationController.arrivalRulesNoticeMessage)
            }
    }

    private var contentWithSheets: some View {
        contentWithChrome
            .sheet(isPresented: $showSetup) {
                SetupView(
                    controller: controller,
                    updateChecker: updateChecker,
                    stepRecorder: stepRecorder
                )
            }
            .sheet(isPresented: $showFavorites) { SavedPlacesView(controller: controller) }
            .sheet(isPresented: $showRoutes) { SavedRoutesView(controller: controller) }
            .sheet(isPresented: $showMessageBoard) {
                MessageBoardView(board: messageBoard, simulation: controller)
            }
            .sheet(isPresented: $showBoardShare) {
                ShareToMessageBoardView(board: messageBoard, simulation: controller)
            }
            .sheet(isPresented: $showLibrary) {
                CoordinateLibraryView(library: coordinateLibrary, simulation: controller)
            }
            .sheet(isPresented: $showStepRecorder) { StepRecorderView(recorder: stepRecorder) }
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
                messageBoard.refreshInBackground()
                updateChecker.checkIfDue()
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
            // 工具列的一鍵補錄不會開啟補錄畫面，結果要在主畫面回報。開著補錄
            // 畫面時交給它自己的 alert，這裡不重複顯示。
            .onChange(of: stepRecorder.lastMessage) { _, message in
                guard let message, !showStepRecorder else { return }
                announce(message)
                stepRecorder.lastMessage = nil
            }
            .onChange(of: stepRecorder.lastError) { _, error in
                guard let error, !showStepRecorder else { return }
                controller.lastError = error
                stepRecorder.lastError = nil
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
                    Annotation("選取位置", coordinate: controller.selectedCoordinate.clLocationCoordinate) {
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
                        stepRecorder: stepRecorder,
                        airplaneAssist: airplaneAssist,
                        isExpanded: $isToolBarExpanded,
                        showJoystick: $showJoystick,
                        isPanelExpanded: $isPanelExpanded,
                        showFavorites: $showFavorites,
                        showRoutes: $showRoutes,
                        showBoardShare: $showBoardShare,
                        showLibrary: $showLibrary,
                        showStepRecorder: $showStepRecorder,
                        showAirplaneAssist: $showAirplaneAssist,
                        position: $position,
                        cameraDistance: $cameraDistance,
                        isLocating: isLocating,
                        onLocate: locateCurrentPosition,
                        onFeedback: announce
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
            Button { showMessageBoard = true } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .overlay(alignment: .topTrailing) { unreadBadge }
            }
            .accessibilityLabel("留言板，\(messageBoard.unreadCount) 個未讀項目")
            Button { showSetup = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("設定")
        }
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if messageBoard.unreadCount > 0 {
            Text(messageBoard.unreadCount > 99 ? "99+" : "\(messageBoard.unreadCount)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xs)
                .frame(minWidth: 14, minHeight: 14)
                // 這個紅色是 iOS 未讀徽章的慣例，不是 statusDanger。綁上狀態色的話，
                // 哪天調整「危險」的顏色，徽章會跟著變成一個不再像徽章的東西。
                .background(.red, in: Capsule())
                .offset(x: 8, y: -8)
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
                    && !updateChecker.showsPrompt
            },
            set: { if !$0 { controller.dismissArrivalRulesNotice() } }
        )
    }

    private static func crossDateMessage(for warning: CrossDateWarning) -> String {
        "目的地當地日期約為 \(warning.destinationDateText)，與本機日期 \(warning.deviceDateText) 不同。部分遊戲的每日任務或獎勵可能受影響。"
    }

    private func updateMessage(for update: AvailableUpdate) -> String {
        var text = "GFlyer \(update.displayVersion) 已發佈（目前為 \(updateChecker.displayVersion)）。"
        if !update.releaseNotes.isEmpty {
            text += "\n\n\(update.releaseNotes)"
        }
        text += "\n\n更新會交給 SideStore 下載並用你的 Apple ID 重新簽名。"
        return text
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
    @ObservedObject var stepRecorder: StepRecorderController
    @ObservedObject var airplaneAssist: AirplaneAssistController
    @Binding var isExpanded: Bool
    @Binding var showJoystick: Bool
    @Binding var isPanelExpanded: Bool
    @Binding var showFavorites: Bool
    @Binding var showRoutes: Bool
    @Binding var showBoardShare: Bool
    @Binding var showLibrary: Bool
    @Binding var showStepRecorder: Bool
    @Binding var showAirplaneAssist: Bool
    @Binding var position: MapCameraPosition
    @Binding var cameraDistance: CLLocationDistance
    let isLocating: Bool
    let onLocate: () -> Void
    let onFeedback: (String) -> Void

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
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                mapButton("plus", label: "放大") { zoom(0.5) }
                mapButton("minus", label: "縮小") { zoom(2) }
            }
            HStack(spacing: Spacing.xs) {
                mapButton(
                    "location.fill",
                    label: "前往目前位置",
                    isBusy: isLocating,
                    action: onLocate
                )
                mapButton(showJoystick ? "gamecontroller.fill" : "gamecontroller", label: "搖桿") {
                    showJoystick.toggle()
                    if showJoystick { isPanelExpanded = false }
                }
            }
            HStack(spacing: Spacing.xs) {
                let isFavorite = controller.favorites.contains { $0.coordinate == controller.selectedCoordinate }
                mapButton(isFavorite ? "star.fill" : "star", label: "收藏目前位置") {
                    onFeedback(controller.addFavorite())
                }
                mapButton("star.circle", label: "收藏與歷史") { showFavorites = true }
            }
            HStack(spacing: Spacing.xs) {
                mapButton("point.3.filled.connected.trianglepath.dotted", label: "已儲存路線") { showRoutes = true }
                mapButton("square.and.arrow.up", label: "分享到留言板") { showBoardShare = true }
            }
            HStack(spacing: Spacing.xs) {
                mapButton("books.vertical", label: "座標圖鑑") { showLibrary = true }
                stepRecordButton
            }
            HStack(spacing: Spacing.xs) {
                airplaneAssistButton
                mapButton("chevron.right", label: "收起地圖工具列") {
                    withAnimation(Motion.panel) { isExpanded = false }
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

    /// 一鍵補錄。捷徑還沒成功跑過一次時不直接送出，改為帶使用者去設定頁——
    /// 在那之前送出只會開啟一個找不到的捷徑，使用者也不知道要去哪裡修。
    private var stepRecordButton: some View {
        let isReady = stepRecorder.isQuickRecordReady
        return mapButton(
            "figure.walk",
            label: isReady ? "補錄 \(stepRecorder.quickStepCount) 步" : "設定補錄步數",
            tint: isReady ? nil : Color.secondary
        ) {
            guard isReady else {
                showStepRecorder = true
                return
            }
            let steps = stepRecorder.quickStepCount
            stepRecorder.record(steps: steps)
            onFeedback("正在用捷徑補錄 \(steps) 步")
        }
    }

    /// 行動網絡下才需要飛航模式那串操作，所以只在偵測到行動網絡時強調它。
    private var airplaneAssistButton: some View {
        mapButton(
            "airplane",
            label: "飛航模式輔助",
            tint: airplaneAssist.connection.needsAssist ? Color.statusAttention : nil
        ) {
            showAirplaneAssist = true
        }
    }

    private func mapButton(
        _ icon: String,
        label: String,
        tint: Color? = nil,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: icon)
                }
            }
            // .plain 的按鈕不會自動上 accent 色，所以未指定時維持原本的 primary
            .foregroundStyle(tint ?? Color.primary)
            .frame(width: Metrics.tapTarget, height: Metrics.tapTarget)
            // 沒有這行時，可點區域只有圖示筆畫本身而不是整個方框
            .contentShape(Rectangle())
        }
        // 原本是 .plain，那會連按壓高亮一起拿掉，所以按下去畫面毫無變化。
        .buttonStyle(PressFeedbackButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(isBusy ? "定位中" : "")
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
            if SpeedScale.exceedsFlowerLimit(controller.speedKilometresPerHour) {
                Label("注意: 超過 20 km/h 將無法種花", systemImage: "exclamationmark.triangle.fill")
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
