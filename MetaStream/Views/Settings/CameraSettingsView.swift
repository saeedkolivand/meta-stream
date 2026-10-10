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
    @AppStorage("camFocusMode") var camFocusMode = "continuous"
    @AppStorage("camLensPosition") var camLensPosition = 0.5
    @AppStorage("camSmoothAutoFocus") var camSmoothAutoFocus = true
    @AppStorage("camFaceDrivenAutoFocus") var camFaceDrivenAutoFocus = true
    @AppStorage("camExposureManual") var camExposureManual = false
    @AppStorage("camExposureBiasEV") var camExposureBiasEV = 0.0
    @AppStorage("camManualISO") var camManualISO = 200.0
    @AppStorage("camManualShutterMs") var camManualShutterMs = 33.3
    @AppStorage("camLowLightBoost") var camLowLightBoost = true
    @AppStorage("camWhiteBalanceManual") var camWhiteBalanceManual = false
    @AppStorage("camWBTemperature") var camWBTemperature = 5500.0
    @AppStorage("camWBTint") var camWBTint = 0.0
    @AppStorage("camHDR") var camHDR = "auto"
    @AppStorage("camTorchLevel") var camTorchLevel = 0.0
    @AppStorage("camMirrored") var camMirrored = false
    @AppStorage("camGDC") var camGDC = true
    @AppStorage("camGridOn") var camGridOn = false
    @AppStorage("camLevelOn") var camLevelOn = false

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
                    Text("No camera found for this position on this device (expected in Simulator). Settings below still save, but can't be checked against real hardware here.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink("Customise live control strip") { LiveControlsCustomizeView() }
            } footer: {
                Text("Choose which controls appear over the preview while streaming, and in what order.")
            }

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
                Text("Sets the starting zoom for that lens's framing next time the phone camera attaches -- also the fallback camera used automatically while the glasses are disconnected. A lens this iPhone doesn't have (e.g. telephoto on a non-Pro model) is skipped.")
            }

            Section("Zoom") {
                labeledSlider("Zoom", valueText: String(format: "%.2fx", camZoom), value: $camZoom, range: cap?.zoomRange ?? 1...1)
            }
            .disabled(cap == nil)

            Section {
                Picker("Mode", selection: $camFocusMode) {
                    Text("Continuous").tag("continuous").disabled(!(cap?.focusContinuous ?? false))
                    Text("Auto (single-shot)").tag("auto").disabled(!(cap?.focusAuto ?? false))
                    Text("Manual").tag("manual").disabled(!(cap?.focusManual ?? false))
                }
                if camFocusMode == "manual" {
                    labeledSlider("Lens position", valueText: String(format: "%.2f", camLensPosition), value: $camLensPosition, range: 0...1)
                }
                capToggle("Smooth autofocus", isOn: $camSmoothAutoFocus, supported: cap?.smoothAutoFocus ?? false)
                Toggle("Face-driven autofocus", isOn: $camFaceDrivenAutoFocus)
            } header: { Text("Focus") } footer: {
                Text("Smooth autofocus trades focus speed for less visible hunting — designed for video, worth leaving on for anything handheld or walking. 0 is closest, 1 is furthest for manual lens position.")
            }

            Section {
                capToggle("Manual exposure", isOn: $camExposureManual, supported: cap?.exposureManual ?? false)
                if camExposureManual {
                    labeledSlider("ISO", valueText: "\(Int(camManualISO))", value: $camManualISO, range: cap?.isoRange ?? 100...100)
                    labeledSlider("Shutter", valueText: "1/\(max(1, Int(1000 / max(camManualShutterMs, 0.1))))s", value: $camManualShutterMs, range: cap?.shutterRangeMs ?? 1...1)
                } else {
                    labeledSlider("Exposure bias", valueText: String(format: "%.1f EV", camExposureBiasEV), value: $camExposureBiasEV, range: cap?.exposureBiasRange ?? 0...0)
                }
                capToggle("Low-light boost", isOn: $camLowLightBoost, supported: cap?.lowLightBoost ?? false)
            } header: { Text("Exposure") } footer: {
                Text("Manual exposure fixes ISO and shutter speed instead of letting the camera track the scene — set this walking into a place you know is dark or bright, not mid-stream. Off, the exposure bias slider still nudges auto exposure brighter or darker.")
            }

            Section {
                capToggle("Manual white balance", isOn: $camWhiteBalanceManual, supported: cap?.whiteBalanceManual ?? false)
                if camWhiteBalanceManual {
                    labeledSlider("Temperature", valueText: "\(Int(camWBTemperature))K", value: $camWBTemperature, range: 2500...10000)
                    labeledSlider("Tint", valueText: String(format: "%.0f", camWBTint), value: $camWBTint, range: -150...150)
                }
            } header: { Text("White balance") } footer: {
                Text("Locks color instead of letting it drift as lighting changes across a walk — mainly useful going indoor↔outdoor repeatedly and wanting one consistent look.")
            }

            Section {
                Picker("HDR", selection: $camHDR) {
                    Text("Auto").tag("auto")
                    Text("On").tag("on").disabled(!(cap?.hdr ?? false))
                    Text("Off").tag("off").disabled(!(cap?.hdr ?? false))
                }
                Toggle("Mirror", isOn: $camMirrored)
                capToggle("Geometric distortion correction", isOn: $camGDC, supported: cap?.geometricDistortionCorrection ?? false)
                labeledSlider("Torch", valueText: camTorchLevel <= 0 ? "Off" : String(format: "%.0f%%", camTorchLevel * 100), value: $camTorchLevel, range: 0...1)
                    .disabled(!(cap?.torch ?? false))
            } header: { Text("Image") } footer: {
                Text("Geometric distortion correction straightens the ultra-wide lens's fisheye look; matters most on that lens. Torch is a fill light for the whole session, not a camera flash — it drains battery fast at high levels.")
            }

            // Group: purely to stay under @ViewBuilder's 10-direct-child cap on Form's content closure --
            // this Form was already at 9 sections before these two, so a straight 11th/12th addition risks
            // a build error I can't compile-check here. Group doesn't change layout, just child counting.
            Group {
                Section {
                    // Glasses + front camera works on any phone (one capture device); phone-camera pairs need multicam hardware.
                    let supported = AVCaptureMultiCamSession.isMultiCamSupported || Streamer.glassesConfigured
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
                    Text((AVCaptureMultiCamSession.isMultiCamSupported ? "" : Streamer.glassesConfigured ? "This phone can't run two of its own cameras at once, so only glasses + the front camera works here. " : "This phone can't run two cameras at once. ")
                         + "Streams one camera full-frame with the other as a small window. Tap the window to swap which is big; the eye button on the main screen hides it. With the phone camera it uses the opposite camera; with glasses it uses the front camera. The window is hidden while blur is on. Dual camera streams at up to 1080p30 and always re-encodes (H.264). Changes made while live apply to the next stream.")
                }

                Section {
                    Toggle("Rule-of-thirds grid", isOn: $camGridOn)
                    Toggle("Level", isOn: $camLevelOn)
                } header: { Text("Viewfinder overlays") } footer: {
                    Text("Grid and level only draw over the preview here — they never reach the recorded or streamed video.")
                }

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
                        Text("No capture format info for this position (expected in Simulator). Resolution/frame rate below keep whatever was last saved.")
                            .foregroundStyle(.orange)
                    }
                    // Stabilisation used to disappear along with Resolution/Frame rate whenever
                    // CameraFormatCapabilities.probe came back empty -- the one live control (see
                    // ContentView's liveControlRow .stabilization case, an unconditional Menu) that wasn't
                    // reachable from Settings in that case. Same phoneStabilization key either way; offers
                    // this resolution's supported modes when format info is known, the full set otherwise,
                    // so it's never simply missing.
                    Picker("Stabilisation", selection: $phoneStabilization) {
                        let modes = formatCaps?.resolutions.first(where: { $0.height == phoneHeight })?.stabilizationModes
                            ?? formatCaps?.resolutions.first?.stabilizationModes
                            ?? ["off", "standard", "cinematic", "action"]
                        ForEach(modes, id: \.self) { Text(DisplayNames.stabilizationLabel($0)).tag($0) }
                    }
                } header: { Text("Resolution & stabilisation") } footer: {
                    Text("Resolution and frame rate come straight off this camera's supported capture formats, so they change per device and per resolution — nothing here is offered unless this camera can actually do it. Stabilisation crops the picture and the stronger modes add capture latency, so Standard is the safe pick for a live stream and Action is for rough movement you would otherwise not be able to watch. Fixed for the whole stream — set it before going live.")
                }
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: phoneHeight) { _, newHeight in
            // Changing resolution can invalidate the stored fps/stabilisation (they're interdependent --
            // a format that does 4K60 may not do 4K120) -- snap both to something this resolution actually
            // supports rather than silently keeping a now-unavailable value.
            guard let res = formatCaps?.resolutions.first(where: { $0.height == newHeight }) else { return }
            snapToResolution(res)
        }
        .onChange(of: fallbackCamera) { _, _ in refresh() }
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
