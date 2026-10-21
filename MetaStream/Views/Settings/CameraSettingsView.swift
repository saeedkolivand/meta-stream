import AVFoundation
import SwiftUI

struct CameraSettingsView: View {
    @AppStorage("fallbackCamera") var fallbackCamera = "back"
    @AppStorage("phoneHeight") var phoneHeight = 720
    @AppStorage("phoneLandscape") var phoneLandscape = false
    @AppStorage("phoneFps") var phoneFps = 30
    @AppStorage("phoneStabilization") var phoneStabilization = "off"

    @AppStorage("camLens") var camLens = "wide"
    @AppStorage("camZoom") var camZoom = 1.0
    @AppStorage("camExposureManual") var camExposureManual = false
    @AppStorage("camMirrored") var camMirrored = false

    @EnvironmentObject var streamer: Streamer
    @AppStorage("dualCam") var dualCam = false
    @AppStorage("dualCamCorner") var dualCamCorner = "topRight"
    @AppStorage("dualCamSize") var dualCamSize = "m"
    @AppStorage("dualCamShape") var dualCamShape = "rounded"

    // Re-probed whenever the fallback position changes -- front/back genuinely differ in what they
    // support, so a stale probe would grey out (or wrongly enable) the wrong controls. Lens no longer
    // changes what's probed (see refresh()'s doc).
    @State private var cap: CameraCapabilities?
    @State private var formatCaps: CameraFormatCapabilities?

    private var position: AVCaptureDevice.Position { fallbackCamera == "front" ? .front : .back }

    var body: some View {
        Form {
            if cap == nil {
                Section {
                    Text("No camera found for this position on this device (expected in Simulator). "
                         + "Settings below still save, but can't be checked against real hardware here.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink("Customise live control strip") { LiveControlsCustomizeView() }
            } footer: {
                Text("Choose which controls appear over the preview while streaming, and in what order.")
            }

            lensSection

            Section("Zoom") {
                labeledSlider("Zoom", valueText: String(format: "%.2fx", camZoom), value: $camZoom, range: cap?.zoomRange ?? 1...1)
            }
            .disabled(cap == nil)

            formatSection
            stabilisationSection
            Section { Toggle("Mirror", isOn: $camMirrored) }
            dualCamSection
            proSection
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: phoneHeight) { _, newHeight in
            // Changing resolution can invalidate the stored fps/stabilisation (they're interdependent --
            // a format that does 4K60 may not do 4K120) -- snap both to something this resolution actually
            // supports rather than silently keeping a now-unavailable value.
            guard let res = formatCaps?.resolutions.first(where: { $0.height == newHeight }) else { return }
            snapToResolution(res)
        }
        .onChange(of: fallbackCamera) { _, _ in refresh() }
    }

    private var lensSection: some View {
        Section {
            Picker("Camera", selection: $fallbackCamera) { Text("Back").tag("back"); Text("Front").tag("front") }
                .pickerStyle(.segmented)
            // Wide/ultra-wide/telephoto share one physical camera now (see CameraSettings.
            // captureDevice's doc), so picking a lens here just sets the starting zoom to that lens's
            // switch-over factor -- same thing the live lens buttons do (ContentView's liveControlRow).
            // camLens itself is no longer a device selector, only which button is highlighted.
            Picker("Lens", selection: Binding(
                get: { camLens },
                set: { newLens in
                    camLens = newLens
                    if let opt = CameraSettings.lensOptions(position: position).first(where: { $0.lens.rawValue == newLens }) {
                        camZoom = opt.zoomFactor
                    }
                })) {
                ForEach(CameraLens.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
        } header: { Text("Lens") } footer: {
            Text("Sets the starting zoom for that lens (also the fallback camera while the glasses are disconnected); "
                 + "a lens this iPhone lacks is skipped.")
        }
    }

    private var formatSection: some View {
        Section {
            if let formatCaps, !formatCaps.resolutions.isEmpty {
                let res = formatCaps.resolutions.first { $0.height == phoneHeight } ?? formatCaps.resolutions[0]
                Picker("Resolution", selection: $phoneHeight) {
                    ForEach(formatCaps.resolutions, id: \.height) { Text("\($0.height)p").tag($0.height) }
                }
                Picker("Aspect", selection: $phoneLandscape) { Text("Portrait 9:16").tag(false); Text("Landscape 16:9").tag(true) }
                Picker("Frame rate", selection: $phoneFps) {
                    ForEach(res.frameRates, id: \.self) { Text("\($0)").tag($0) }
                }
            } else {
                Text("No capture format info for this position (expected in Simulator). "
                     + "Resolution/frame rate below keep whatever was last saved.")
                    .foregroundStyle(.orange)
            }
        } header: { Text("Resolution") } footer: {
            Text("Only formats this camera supports are offered. Fixed for the whole stream: set before going live. "
                 + "With the dual camera or a USB webcam the frame rate is capped at 60 on iPad and 30 on iPhone, "
                 + "and a webcam only gets 60 when its current mode offers it.")
        }
    }

    private var stabilisationSection: some View {
        Section {
            // Offers this resolution's supported modes when format info is known, the full set otherwise, so it's never missing.
            Picker("Stabilisation", selection: $phoneStabilization) {
                let modes = formatCaps?.resolutions.first(where: { $0.height == phoneHeight })?.stabilizationModes
                    ?? formatCaps?.resolutions.first?.stabilizationModes
                    ?? ["off", "standard", "cinematic", "action"]
                ForEach(modes, id: \.self) { Text(DisplayNames.stabilizationLabel($0)).tag($0) }
            }
        } footer: {
            Text("Crops the picture and the stronger modes add latency. Standard is the safe pick for a live stream; "
                 + "Action is for rough movement you would otherwise not be able to watch.")
        }
    }

    private var dualCamSection: some View {
        Section {
            // Glasses + front camera works on any phone (one capture device); phone-camera pairs need multicam hardware.
            let supported = AVCaptureMultiCamSession.isMultiCamSupported || Streamer.glassesEnabled
            Toggle("Dual camera", isOn: $dualCam)
                .disabled(!supported)
                .onChange(of: dualCam) { _, on in streamer.setDualCam(on) }
            if dualCam {
                Picker("Corner", selection: $dualCamCorner) {
                    Text("Top left").tag("topLeft"); Text("Top right").tag("topRight")
                    Text("Bottom left").tag("bottomLeft"); Text("Bottom right").tag("bottomRight")
                }
                .onChange(of: dualCamCorner) { _, _ in streamer.applyDualCamLayout() }
                Picker("Size", selection: $dualCamSize) {
                    Text("Small").tag("s"); Text("Medium").tag("m"); Text("Large").tag("l")
                }
                .onChange(of: dualCamSize) { _, _ in streamer.applyDualCamLayout() }
                Picker("Shape", selection: $dualCamShape) {
                    Text("Rounded").tag("rounded"); Text("Circle").tag("circle")
                }
                .onChange(of: dualCamShape) { _, _ in streamer.applyDualCamLayout() }
            }
        } header: { Text("Face cam (dual camera)") } footer: {
            Text(dualCamFooter)
        }
    }

    /// Two lines while off; the details show once the face cam is on.
    private var dualCamFooter: String {
        let unsupported = AVCaptureMultiCamSession.isMultiCamSupported ? "" : Streamer.glassesEnabled
            ? "This phone can't run two of its own cameras at once, so only glasses + the front camera works here. "
            : "This phone can't run two cameras at once. "
        let basics = "Streams one camera full-frame with the other as a small window. Tap the window to swap which is big."
        guard dualCam else { return unsupported + basics }
        return unsupported + basics + " The eye button on the main screen hides it. With the phone camera it uses the opposite camera; "
            + "with glasses it uses the front camera. The window is hidden while blur is on. "
            + "Dual camera streams at up to 1080p30 and always re-encodes (H.264). Changes made while live apply to the next stream."
    }

    private var proSection: some View {
        Section {
            NavigationLink {
                CameraProControlsView(cap: cap)
            } label: {
                LabeledContent("Pro controls", value: camExposureManual ? "Manual exposure" : "Auto")
            }
        } footer: {
            Text("Focus, exposure, white balance, HDR, torch, look (LUT) and viewfinder overlays.")
        }
    }

    private func snapToResolution(_ res: CameraFormatCapabilities.Resolution) {
        if !res.frameRates.contains(phoneFps) { phoneFps = res.nearestFps(to: phoneFps) }
        if !res.stabilizationModes.contains(phoneStabilization) { phoneStabilization = res.nearestStabilization(to: phoneStabilization) }
    }

    /// Re-probed whenever position changes, like `cap` above -- lens no longer selects a different device
    /// (see CameraSettings.captureDevice's doc), so it doesn't affect what's probed here any more. Also
    /// snaps the stored resolution (and, via snapToResolution, fps/stabilisation) to the nearest one this
    /// camera actually supports -- keeps a previously-saved 1080p/30 choice intact on hardware that still
    /// supports it, but never leaves the picker pointed at a resolution this camera can't shoot.
    private func refresh() {
        cap = CameraCapabilities.probe(position: position)
        formatCaps = CameraFormatCapabilities.probe(position: position)
        guard let res = formatCaps?.nearestResolution(to: phoneHeight) else { return }
        if res.height != phoneHeight { phoneHeight = res.height }
        snapToResolution(res)
    }
}
