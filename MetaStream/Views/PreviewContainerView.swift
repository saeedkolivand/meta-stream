import AVFoundation
import CoreMotion
import SwiftUI

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}

struct PreviewView: UIViewRepresentable {
    @EnvironmentObject var streamer: Streamer
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.displayLayer.videoGravity = .resizeAspect
        streamer.preview = view.displayLayer
        if streamer.pip == nil { streamer.pip = PiPController(layer: view.displayLayer) }
        return view
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

/// Viewfinder-only level: CMMotionManager roll -> a horizon line drawn over the preview.
/// Started/stopped with the Settings toggle so it costs nothing when off; never touches the capture
/// pipeline or encoded video (see gridOverlay/levelOverlay -- purely a SwiftUI overlay).
final class LevelMonitor: ObservableObject {
    @Published var rollDegrees: Double = 0
    private let mm = CMMotionManager()
    func start() {
        guard mm.isDeviceMotionAvailable, !mm.isDeviceMotionActive else { return }
        mm.deviceMotionUpdateInterval = 1.0 / 20
        mm.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            self?.rollDegrees = data.attitude.roll * 180 / .pi
        }
    }
    func stop() { mm.stopDeviceMotionUpdates() }
}

/// Live preview + viewfinder gestures and overlays. Tap-to-focus/expose and long-press AE/AF lock are
/// gestures directly on the preview (not strip controls), so they work whether or not the strip is open.
struct PreviewContainerView: View {
    @EnvironmentObject var streamer: Streamer
    @ObservedObject var levelMonitor: LevelMonitor
    @Binding var focusTap: CGPoint?
    @Binding var aeafLocked: Bool
    @Binding var pinchStartZoom: Double?

    @AppStorage("camZoom") var camZoom = 1.0
    @AppStorage("camMirrored") var camMirrored = false
    @AppStorage("camGridOn") var camGridOn = false
    @AppStorage("camLevelOn") var camLevelOn = false
    @AppStorage("phoneLandscape") var phoneLandscape = false
    @AppStorage("dualCamCorner") var dualCamCorner = "topRight"
    @AppStorage("dualCamSize") var dualCamSize = "m"
    @AppStorage("dualCamShape") var dualCamShape = "rounded"

    /// Phone-camera controls only drive a built-in camera; a UVC external camera exposes none of them.
    private var phoneCamControllable: Bool { streamer.source == "phone" && streamer.manualSource != "external" }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    PreviewView().ignoresSafeArea()
                        .contentShape(Rectangle())
                        .gesture(
                            LongPressGesture(minimumDuration: 0.5).exclusively(before: SpatialTapGesture())
                                .onEnded { value in
                                    guard phoneCamControllable else { return }
                                    switch value {
                                    case .first:
                                        hapticTap(strong: true)
                                        aeafLocked.toggle()
                                        streamer.setAEAFLocked(aeafLocked)
                                    case .second(let tapValue):
                                        let canvas = streamer.dualCamCanvas
                                        if streamer.dualCamActive, !streamer.dualCamHidden,
                                           let cp = Streamer.canvasPoint(forViewPoint: tapValue.location, viewSize: geo.size, canvas: canvas),
                                           Streamer.pipRect(canvas: canvas, corner: dualCamCorner, size: dualCamSize, shape: dualCamShape).contains(cp) {
                                            hapticTap()
                                            streamer.swapDualCam()
                                            return
                                        }
                                        if streamer.dualCamSwapped { return }
                                        hapticTap()
                                        focusTap = tapValue.location
                                        let norm = CGPoint(x: tapValue.location.x / max(geo.size.width, 1), y: tapValue.location.y / max(geo.size.height, 1))
                                        let orientation: AVCaptureVideoOrientation = phoneLandscape ? streamer.landscapeOrientation : .portrait
                                        streamer.tapToFocus(at: CameraSettings.devicePoint(forViewPoint: norm, orientation: orientation, mirrored: camMirrored))
                                        Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { focusTap = nil } }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    guard phoneCamControllable, !streamer.dualCamSwapped else { return }
                                    if pinchStartZoom == nil { pinchStartZoom = camZoom }
                                    let range = streamer.cameraCapabilities?.zoomRange ?? (camZoom...camZoom)
                                    camZoom = CameraSettings.clamped((pinchStartZoom ?? camZoom) * Double(value.magnification), min: range.lowerBound, max: range.upperBound)
                                    streamer.applyCameraSettings()
                                }
                                .onEnded { _ in pinchStartZoom = nil }
                        )

                    if camGridOn { gridOverlay(size: geo.size) }
                    if camLevelOn { levelOverlay(size: geo.size) }
                }
            }

            if let p = focusTap {
                RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .position(p)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if aeafLocked {
                VStack {
                    Text("AE/AF LOCK")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.top, 54)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if streamer.cameraOff {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill").font(.system(size: 44))
                    Text("Camera off").font(.headline)
                    Text("viewers see black").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
        }
    }

    /// Rule-of-thirds grid, viewfinder only -- never touches the encoded video.
    private func gridOverlay(size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: size.width / 3, y: 0)); p.addLine(to: CGPoint(x: size.width / 3, y: size.height))
            p.move(to: CGPoint(x: size.width * 2 / 3, y: 0)); p.addLine(to: CGPoint(x: size.width * 2 / 3, y: size.height))
            p.move(to: CGPoint(x: 0, y: size.height / 3)); p.addLine(to: CGPoint(x: size.width, y: size.height / 3))
            p.move(to: CGPoint(x: 0, y: size.height * 2 / 3)); p.addLine(to: CGPoint(x: size.width, y: size.height * 2 / 3))
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
        .allowsHitTesting(false)
    }

    /// Horizon level from LevelMonitor's roll, viewfinder only. Green within ~1.5° of level.
    private func levelOverlay(size: CGSize) -> some View {
        let roll = levelMonitor.rollDegrees
        let level = abs(roll) < 1.5
        return Rectangle()
            .fill(level ? Color.green : Color.white)
            .frame(width: size.width * 0.6, height: 1.5)
            .rotationEffect(.degrees(-roll))
            .position(x: size.width / 2, y: size.height / 2)
            .allowsHitTesting(false)
    }
}
