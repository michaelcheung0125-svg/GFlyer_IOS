import MapKit
import SwiftUI

struct MainView: View {
    @ObservedObject var controller: SimulationController
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position) {
                        Marker("選取位置", coordinate: controller.selectedCoordinate.clLocationCoordinate)
                            .tint(.red)

                        if let active = controller.status.coordinate {
                            Annotation("模擬位置", coordinate: active.clLocationCoordinate) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.blue, in: Circle())
                            }
                        }

                        ForEach(Array(controller.routePoints.enumerated()), id: \.offset) { index, point in
                            Marker("\(index + 1)", coordinate: point.clLocationCoordinate)
                                .tint(.orange)
                        }

                        if controller.routePoints.count >= 2 {
                            MapPolyline(coordinates: controller.routePoints.map(\.clLocationCoordinate))
                                .stroke(.orange, lineWidth: 4)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        controller.select(GeoCoordinate(coordinate))
                    }
                }

                ControlPanel(controller: controller)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .navigationTitle("GFlyer iOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label(
                        controller.canControlDeviceLocation ? "裝置模式" : "預覽模式",
                        systemImage: controller.canControlDeviceLocation ? "iphone.gen3" : "eye"
                    )
                    .font(.caption)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSetup = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showSetup) {
                SetupView(controller: controller)
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
}

private struct ControlPanel: View {
    @ObservedObject var controller: SimulationController

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.status.message)
                        .font(.subheadline.weight(.semibold))
                    Text(controller.status.coordinate?.display ?? controller.selectedCoordinate.display)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.status.isActive {
                    Circle()
                        .fill(controller.status.isPaused ? .orange : .green)
                        .frame(width: 10, height: 10)
                }
            }

            Picker("模式", selection: $controller.mode) {
                ForEach(SimulationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if controller.mode == .route {
                routeControls
            }

            HStack(spacing: 12) {
                Button {
                    controller.start()
                } label: {
                    Label("開始", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    controller.togglePause()
                } label: {
                    Image(systemName: controller.status.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!controller.status.isActive)
                .accessibilityLabel(controller.status.isPaused ? "繼續" : "暫停")

                Button(role: .destructive) {
                    controller.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!controller.status.isActive && !controller.canControlDeviceLocation)
                .accessibilityLabel("停止")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var routeControls: some View {
        VStack(spacing: 10) {
            HStack {
                Label("\(controller.routePoints.count) 個路線點", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                Spacer()
                Button {
                    controller.removeLastRoutePoint()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(controller.routePoints.isEmpty)
                .accessibilityLabel("移除最後路線點")
                Button(role: .destructive) {
                    controller.clearRoute()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(controller.routePoints.isEmpty)
                .accessibilityLabel("清除路線")
            }

            HStack {
                Text("速度")
                Slider(value: $controller.speedKilometresPerHour, in: 1...50, step: 1)
                Text("\(Int(controller.speedKilometresPerHour)) km/h")
                    .font(.caption.monospacedDigit())
                    .frame(width: 62, alignment: .trailing)
            }

            Toggle("循環路線", isOn: $controller.loopRoute)
            if controller.loopRoute {
                Picker("循環方式", selection: $controller.loopTransitionMode) {
                    ForEach(LoopTransitionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
