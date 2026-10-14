import SwiftUI

/// Fixed bottom controls: GO LIVE, source picker, chat/settings shortcuts plus the always-on-screen
/// mic/camera/blur buttons. These are the controls you need in the second something goes wrong, so they
/// must never live in the scrolling status strip where a long run of pills can push them off the edge.
struct GoLiveControlsView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("rtmpURL") var ingestURL = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    @AppStorage("streamKey") var streamKey = ""
    @AppStorage("micUID") var micUID = ""
    @AppStorage("fallbackCamera") var fallbackCamera = "back"
    @AppStorage("bitrateKbps") var bitrateKbps = 4000
    @AppStorage("srtLatencyMs") var srtLatencyMs = 2000
    @AppStorage("phoneHeight") var phoneHeight = 720
    @AppStorage("phoneLandscape") var phoneLandscape = false
    @AppStorage("phoneFps") var phoneFps = 30
    @AppStorage("phoneStabilization") var phoneStabilization = "off"
    @AppStorage("blurOn") var blurOn = false
    @AppStorage("resolution") var resolution = "high"
    @AppStorage("fps") var fpsSetting = 30

    var codec: String
    @Binding var showChat: Bool
    @Binding var showSettings: Bool

    @Environment(\.horizontalSizeClass) private var hSize
    private var compact: Bool { hSize == .compact }
    private var goSize: CGFloat { compact ? 72 : 84 }
    private var smallSize: CGFloat { compact ? 44 : 52 }

    var body: some View {
        controls.padding(.bottom, 12)
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: compact ? 8 : (streamer.dualCamActive ? 8 : 18)) {
            // Compact width puts these in a left-edge rail (ContentView) to keep the row within 343 pt.
            if !compact { QuickControls(size: smallSize) }
            if Streamer.glassesConfigured {
                StripStyles.roundButton(streamer.glassesOn ? "eyeglasses" : "eyeglasses.slash",
                                        filled: streamer.glassesOn, size: smallSize) {
                    hapticTap()
                    streamer.glassesOn ? streamer.stopGlasses() : streamer.startGlasses(resolution: resolution, fps: UInt(fpsSetting))
                }
            }
            // A picker, not a cycler: hunting for the right source by tapping through four states is
            // the wrong interaction when the shot is already wrong on stream.
            Menu {
                Picker("Video source", selection: Binding(get: { streamer.manualSource },
                                                          set: { hapticTap(); streamer.setSource($0) })) {
                    Label("Auto", systemImage: "wand.and.stars").tag("auto")
                    if Streamer.glassesConfigured {
                        Label("Glasses", systemImage: "eyeglasses").tag("glasses")
                    }
                    Label("Back camera", systemImage: "camera.fill").tag("back")
                    Label("Front camera", systemImage: "camera.rotate.fill").tag("front")
                    if streamer.externalCameraName != nil {
                        Label("External camera", systemImage: "video.fill").tag("external")
                    }
                }
            } label: {
                Image(systemName: sourceIcon)
                    .font(.system(size: smallSize * 0.38, weight: .semibold))
                    .foregroundStyle(streamer.manualSource == "auto" ? .white : .black)
                    .frame(width: smallSize, height: smallSize)
                    .background(streamer.manualSource == "auto" ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.white), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                hapticTap(strong: true)
                if streamer.live {
                    streamer.stopLive()
                } else {
                    streamer.goLive(url: ingestURL, key: streamKey, micUID: micUID,
                                    fallbackPosition: fallbackCamera == "front" ? .front : .back,
                                    bitrateKbps: bitrateKbps, codec: codec, srtLatencyMs: srtLatencyMs,
                                    quality: .init(height: phoneHeight, landscape: phoneLandscape, fps: phoneFps,
                                                   stabilization: phoneStabilization))
                }
            } label: {
                ZStack {
                    Circle().fill(streamer.live ? Color.red : Color.green)
                        .frame(width: goSize, height: goSize)
                        .shadow(color: (streamer.live ? Color.red : Color.green).opacity(0.5), radius: 12)
                    Text(streamer.live ? "END" : "GO\nLIVE")
                        .font(.system(size: compact ? 13 : 15, weight: .heavy)).multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(duration: 0.3), value: streamer.live)

            // Hide/show the face-cam window mid-stream (the second camera keeps running; only the overlay goes).
            if streamer.dualCamActive {
                StripStyles.roundButton(streamer.dualCamHidden ? "eye.slash" : "eye", filled: streamer.dualCamHidden, size: smallSize) {
                    hapticTap()
                    streamer.setDualCamHidden(!streamer.dualCamHidden)
                }
            }
            StripStyles.roundButton("bubble.left.and.bubble.right.fill", filled: showChat, size: smallSize) {
                hapticTap(); showChat.toggle()
            }
            StripStyles.roundButton("gearshape.fill", filled: false, size: smallSize) { hapticTap(); showSettings = true }
        }
    }

    /// Shows what is actually on air, not what was asked for — on auto those differ whenever the
    /// glasses drop and the phone takes over.
    private var sourceIcon: String {
        switch streamer.manualSource {
        case "glasses": return "eyeglasses"
        case "back": return "camera.fill"
        case "front": return "camera.rotate.fill"
        case "external": return "video.fill"
        default: return streamer.source == "phone" ? "iphone" : "eyeglasses"
        }
    }
}

/// Mic / camera / blur round buttons; flattens into whichever stack hosts it (bottom row or left rail).
struct QuickControls: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("blurOn") var blurOn = false
    var size: CGFloat

    var body: some View {
        Group {
            button(streamer.muted ? "mic.slash.fill" : "mic.fill",
                   streamer.muted ? "Muted" : "Mic",
                   style: streamer.muted ? .stopped : .live) {
                streamer.setMuted(!streamer.muted)
            }
            button(streamer.cameraOff ? "video.slash.fill" : "video.fill",
                   streamer.cameraOff ? "Hidden" : "Camera",
                   style: streamer.cameraOff ? .stopped : .live) {
                streamer.setCameraOff(!streamer.cameraOff)
            }
            button(blurOn ? "eye.slash.fill" : "eye.fill",
                   blurOn ? (streamer.live && !streamer.transcoding ? "Next stream" : "Blur on") : "Blur off",
                   style: !blurOn ? .off : (streamer.live && !streamer.transcoding ? .pending : .protecting)) {
                blurOn.toggle()
            }
        }
    }

    /// One colour per meaning, never two shades of the same thing: green is going out, red is not going
    /// out, blue is actively protecting, amber is asked for but not in effect, grey is off.
    private enum QuickStyle {
        case live, stopped, protecting, pending, off
        var tint: Color? {
            switch self {
            case .live: return .green
            case .stopped: return .red
            case .protecting: return .blue
            case .pending: return .orange
            case .off: return nil
            }
        }
    }

    private func button(_ icon: String, _ label: String, style: QuickStyle,
                        action: @escaping () -> Void) -> some View {
        StripStyles.roundButton(icon, filled: false, tint: style.tint, size: size) {
            hapticTap(strong: true)
            action()
        }
        .accessibilityLabel(label)
    }
}
