import SwiftUI

/// Live camera control strip: "set before you walk" controls live in SettingsView's Camera screen
/// (ISO, shutter, HDR, distortion correction: deliberate, set-once). These are the ones worth changing
/// mid-stream, applied straight to the live device -- see Streamer.applyCameraSettings.
struct CameraControlStripView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("camLens") var camLens = "wide"
    @AppStorage("camZoom") var camZoom = 1.0
    @AppStorage("camExposureManual") var camExposureManual = false
    @AppStorage("camExposureBiasEV") var camExposureBiasEV = 0.0
    @AppStorage("camTorchLevel") var camTorchLevel = 0.0
    @AppStorage("camWhiteBalanceManual") var camWhiteBalanceManual = false
    @AppStorage("camMirrored") var camMirrored = false
    @AppStorage("phoneStabilization") var phoneStabilization = "off"
    @AppStorage(LiveCameraControl.storageKey) var liveControlOrderRaw = LiveCameraControl.defaultOrderRaw

    /// Data-driven strip contents: see LiveCameraControl's doc. Falls back to the full default set if the
    /// stored value is empty or unparseable, so there's never a dead strip with nothing shown.
    private var liveControlOrder: [LiveCameraControl] { LiveCameraControl.order(from: liveControlOrderRaw) }

    var body: some View {
        // Landscape is too short for every row: scroll only when it doesn't fit.
        ViewThatFits(in: .vertical) {
            controlRows
            ScrollView(showsIndicators: false) { controlRows }
        }
        .padding(12)
        .frame(width: 156)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var controlRows: some View {
        VStack(spacing: 14) {
            ForEach(liveControlOrder, id: \.self) { liveControlRow($0) }
        }
    }

    @ViewBuilder
    private func liveControlRow(_ control: LiveCameraControl) -> some View {
        let cap = streamer.cameraCapabilities
        switch control {
        case .lens:
            // Ascending by real zoom factor and labeled with THIS device's actual multipliers -- see
            // CameraSettings.lensOptions. Empty when this position has only one lens.
            let options = CameraSettings.lensOptions(position: streamer.cameraPosition)
            if !options.isEmpty {
                HStack(spacing: 6) {
                    ForEach(options, id: \.lens.rawValue) { option in
                        Button {
                            hapticTap()
                            camLens = option.lens.rawValue
                            camZoom = option.zoomFactor
                            applog("stream", "camera lens=\(option.lens.rawValue) zoom=\(String(format: "%.2f", option.zoomFactor))x")
                            streamer.applyCameraSettings()
                        } label: {
                            Text(option.label)
                                .font(.caption2.weight(.bold))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(camLens == option.lens.rawValue ? .black : .white)
                                .background(camLens == option.lens.rawValue ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .zoom:
            if let range = cap?.zoomRange, range.upperBound > range.lowerBound {
                liveSlider("magnifyingglass", String(format: "%.1fx", camZoom), $camZoom, range)
            }
        case .exposure:
            if let range = cap?.exposureBiasRange {
                VStack(alignment: .leading, spacing: 2) {
                    liveSlider("sun.max", String(format: "%.1f EV", camExposureBiasEV), $camExposureBiasEV, range, disabled: camExposureManual)
                    // Bias only affects auto exposure -- custom ISO/shutter ignores it. Disabled rather
                    // than force-flipping the user's Settings choice.
                    if camExposureManual {
                        Text("manual exposure on").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
            }
        case .torch:
            if cap?.torch == true {
                liveSlider("flashlight.on.fill", camTorchLevel <= 0 ? "off" : String(format: "%.0f%%", camTorchLevel * 100), $camTorchLevel, 0...1)
            }
        case .whiteBalanceLock:
            if cap?.whiteBalanceManual == true {
                Button {
                    hapticTap()
                    camWhiteBalanceManual.toggle()
                    streamer.setWhiteBalanceLocked(camWhiteBalanceManual)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: camWhiteBalanceManual ? "lock.fill" : "lock.open")
                        Text(camWhiteBalanceManual ? "WB locked" : "Lock WB").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(camWhiteBalanceManual ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(.white.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        case .stabilization:
            // Deliberate discrete Menu, not a slider you graze -- each mode crops differently (visible
            // framing jump) and the stronger modes add latency, so switching has to be a deliberate tap.
            Menu {
                Picker("Stabilisation", selection: Binding(
                    get: { phoneStabilization },
                    set: { newValue in hapticTap(); phoneStabilization = newValue; streamer.setStabilization(newValue) })) {
                    Text("Off").tag("off")
                    Text("Standard").tag("standard")
                    Text("Cinematic").tag("cinematic")
                    Text("Action").tag("action")
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "gyroscope")
                    Text(DisplayNames.stabilizationShort(phoneStabilization)).font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(phoneStabilization == "off" ? AnyShapeStyle(.white.opacity(0.15)) : AnyShapeStyle(Color.blue.gradient), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        case .mirror:
            Button {
                hapticTap()
                camMirrored.toggle()
                streamer.setMirrored(camMirrored)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.left.and.right")
                    Text(camMirrored ? "Mirrored" : "Mirror").font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(camMirrored ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(.white.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    /// Fires on every value change, not just release -- SwiftUI's Slider already updates a plain
    /// Binding<Double> continuously while dragging, so this is what makes the picture change under your
    /// finger like the Camera app.
    private func liveSlider(_ icon: String, _ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, disabled: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption2.monospacedDigit())
                Spacer()
            }
            .foregroundStyle(.white)
            Slider(value: value, in: range)
                .tint(.white)
                .onChange(of: value.wrappedValue) { _, _ in streamer.applyCameraSettings() }
        }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }
}
