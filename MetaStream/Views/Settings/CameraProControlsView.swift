import SwiftUI
import UniformTypeIdentifiers

/// Settings › Camera › Pro controls: focus, exposure, white balance, image, look (LUT) and viewfinder overlays.
struct CameraProControlsView: View {
    let cap: CameraCapabilities?
    @EnvironmentObject var streamer: Streamer
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
    @AppStorage("camGDC") var camGDC = true
    @AppStorage("camGridOn") var camGridOn = false
    @AppStorage("camLevelOn") var camLevelOn = false
    @AppStorage("centerStage") var centerStage = true

    // Look of the live source (streamer.lookKey); saved per source on every change.
    @State var look = Look()
    @State var luts: [String] = []
    @State var importingLUT = false
    @State var lutError: String?

    var body: some View {
        Form {
            if cap == nil {
                Section {
                    Text("No camera found for this position on this device (expected in Simulator). "
                         + "Settings below still save, but can't be checked against real hardware here.")
                        .foregroundStyle(.orange)
                }
            }
            focusSection
            exposureSection
            whiteBalanceSection
            imageSection
            lookSection
            centerStageSection
            overlaysSection
        }
        .navigationTitle("Pro controls")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { look = Look.load(streamer.lookKey); luts = Look.files() }
        .onChange(of: streamer.lookKey) { _, newKey in look = Look.load(newKey) }
        .onChange(of: look) { _, newLook in Look.save(newLook, streamer.lookKey) }
        .fileImporter(isPresented: $importingLUT, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]) { result in
            guard case .success(let url) = result else { return }
            switch Look.importLUT(url) {
            case .success(let name): lutError = nil; luts = Look.files(); look.lut = name
            case .failure(let e): lutError = e.localizedDescription
            }
        }
    }

    private var focusSection: some View {
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
            Text("Smooth autofocus trades focus speed for less visible hunting: worth leaving on for anything handheld or walking. "
                 + "0 is closest, 1 is furthest for manual lens position.")
        }
    }

    private var exposureSection: some View {
        Section {
            capToggle("Manual exposure", isOn: $camExposureManual, supported: cap?.exposureManual ?? false)
            if camExposureManual {
                labeledSlider("ISO", valueText: "\(Int(camManualISO))", value: $camManualISO, range: cap?.isoRange ?? 100...100)
                labeledSlider("Shutter", valueText: "1/\(max(1, Int(1000 / max(camManualShutterMs, 0.1))))s",
                              value: $camManualShutterMs, range: cap?.shutterRangeMs ?? 1...1)
            } else {
                labeledSlider("Exposure bias", valueText: String(format: "%.1f EV", camExposureBiasEV),
                              value: $camExposureBiasEV, range: cap?.exposureBiasRange ?? 0...0)
            }
            capToggle("Low-light boost", isOn: $camLowLightBoost, supported: cap?.lowLightBoost ?? false)
        } header: { Text("Exposure") } footer: {
            Text("Manual exposure fixes ISO and shutter speed instead of letting the camera track the scene: set it walking into "
                 + "a place you know is dark or bright, not mid-stream. Off, the exposure bias slider still nudges auto exposure.")
        }
    }

    private var whiteBalanceSection: some View {
        Section {
            capToggle("Manual white balance", isOn: $camWhiteBalanceManual, supported: cap?.whiteBalanceManual ?? false)
            if camWhiteBalanceManual {
                labeledSlider("Temperature", valueText: "\(Int(camWBTemperature))K", value: $camWBTemperature, range: 2500...10000)
                labeledSlider("Tint", valueText: String(format: "%.0f", camWBTint), value: $camWBTint, range: -150...150)
            }
        } header: { Text("White balance") } footer: {
            Text("Locks color instead of letting it drift as lighting changes across a walk: mainly useful going "
                 + "indoor↔outdoor repeatedly and wanting one consistent look.")
        }
    }

    private var imageSection: some View {
        Section {
            Picker("HDR", selection: $camHDR) {
                Text("Auto").tag("auto")
                Text("On").tag("on").disabled(!(cap?.hdr ?? false))
                Text("Off").tag("off").disabled(!(cap?.hdr ?? false))
            }
            capToggle("Geometric distortion correction", isOn: $camGDC, supported: cap?.geometricDistortionCorrection ?? false)
            labeledSlider("Torch", valueText: camTorchLevel <= 0 ? "Off" : String(format: "%.0f%%", camTorchLevel * 100),
                          value: $camTorchLevel, range: 0...1)
                .disabled(!(cap?.torch ?? false))
        } header: { Text("Image") } footer: {
            Text("Geometric distortion correction straightens the ultra-wide lens's fisheye look; matters most on that lens. "
                 + "Torch is a fill light for the whole session, not a camera flash: it drains battery fast at high levels.")
        }
    }

    private var centerStageSection: some View {
        Section {
            Toggle("Center Stage (front camera)", isOn: $centerStage)
                .onChange(of: centerStage) { _, _ in streamer.applyCenterStage() }
        } footer: {
            Text("Keeps you framed as you move. Front camera on iPad; ignored where unsupported.")
        }
    }

    private var overlaysSection: some View {
        Section {
            Toggle("Rule-of-thirds grid", isOn: $camGridOn)
            Toggle("Level", isOn: $camLevelOn)
        } header: { Text("Viewfinder overlays") } footer: {
            Text("Grid and level only draw over the preview here — they never reach the recorded or streamed video.")
        }
    }
}
