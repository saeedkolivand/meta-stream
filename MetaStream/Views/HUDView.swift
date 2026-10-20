import MWDATCore
import SwiftUI

/// Top status strip: connection, bitrate, battery, heat, source, mute, photo, manage, camera buttons.
/// Fixed pills never scroll the quick controls off screen -- see GoLiveControlsView's doc.
struct HUDView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var speaker: Speaker
    @EnvironmentObject var privacy: Privacy
    @EnvironmentObject var platforms: Platforms
    @AppStorage("blurOn") var blurOn = false
    @AppStorage("bitrateKbps") var bitrateKbps = 4000
    @AppStorage("glassesEnabled") private var glassesEnabled = false
    @Binding var showStatus: Bool
    @Binding var showManager: Bool
    @Binding var showChat: Bool
    @Binding var showCameraControls: Bool

    @State var showNetwork = false   // not private, same memberwise-init reason as overlays below

    @ObservedObject var overlays = OverlayStore.shared   // not private: it would make HUDView's memberwise init private

    /// Active scene; tap for the list. Glasses HEVC passthrough can't be drawn on, so it says so there.
    private var scenePill: some View {
        let usable = streamer.overlaysUsable
        return Menu {
            sceneButton("", "None")
            ForEach(overlays.scenes, id: \.name) { scene in sceneButton(scene.name, scene.name) }
        } label: {
            StripStyles.pill("rectangle.stack", usable ? (overlays.scene.isEmpty ? "No scene" : overlays.scene) : "overlays off for glasses",
                             usable && !overlays.scene.isEmpty ? .green : .gray)
        }
    }

    private func sceneButton(_ name: String, _ label: String) -> some View {
        Button {
            hapticTap()
            streamer.selectScene(name)
        } label: {
            if overlays.scene == name { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
    }

    private var phoneCamControllable: Bool { streamer.source == "phone" && streamer.manualSource != "external" }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if Streamer.glassesConfigured && glassesEnabled {
                    StripStyles.stripButton(label: {
                        StripStyles.pill("eyeglasses", streamer.glassesShort, glassesColor)
                    }, action: { showStatus = true })
                }

                if let since = streamer.recordingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = Int(ctx.date.timeIntervalSince(since))
                        StripStyles.pill("circle.fill", String(format: "REC %02d:%02d", s / 60, s % 60), .red)
                    }
                }
                if streamer.live {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        // Amber while down: the timer measures the session, never the connection, so it
                        // has to show degraded time rather than quietly counting dead air as healthy.
                        let down = streamer.connectedSince == nil
                        StripStyles.pill(down ? "exclamationmark.triangle.fill" : "record.circle.fill",
                             down ? "down " + elapsed(ctx.date) : elapsed(ctx.date),
                             down ? .orange : .red)
                    }
                    // Same sum as the {viewers} widget token: Kick + Twitch + YouTube.
                    StripStyles.pill("eye.fill", "\(platforms.kickViewers + platforms.twitchViewers + platforms.ytViewers)", .white)
                    LevelBar(meter: streamer.audioLevel)
                    StripStyles.stripButton(label: {
                        StripStyles.pill("waveform", "\(streamer.fps) fps · \(streamer.kbps) kbps", kbpsColor)
                    }, action: { hapticTap(); showNetwork = true })
                    if streamer.drops > 0 {
                        StripStyles.stripButton(label: {
                            StripStyles.pill("exclamationmark.arrow.triangle.2.circlepath", "\(streamer.drops) drops", .orange)
                        }, action: { hapticTap(); showNetwork = true })
                    }
                    if streamer.currentBitrateKbps > 0, streamer.currentBitrateKbps < bitrateKbps {
                        StripStyles.pill("arrow.down.right.circle", "\(streamer.currentBitrateKbps)k cap", .orange)
                    }
                } else {
                    StripStyles.stripButton(label: {
                        StripStyles.pill("antenna.radiowaves.left.and.right", streamer.rtmpState, .gray)
                    }, action: { hapticTap(); showNetwork = true })
                }
                if let pb = streamer.phoneBattery, pb < 30 {
                    StripStyles.pill("battery.25", "phone \(pb)%", pb < 15 ? .orange : .white)
                }
                if let gt = streamer.glassesThermal, let heat = glassesHeat(gt) {
                    StripStyles.pill("thermometer", "glasses \(heat)", heat == "warm" ? .white : .orange)
                }
                if blurOn {
                    StripStyles.pill(privacy.stalled ? "eye.trianglebadge.exclamationmark" : "eye.slash.fill",
                         privacy.stalled ? "blur failed" : "blur", privacy.stalled ? .orange : .white)
                }
                if streamer.thermal != .nominal {
                    StripStyles.pill("thermometer", thermalLabel, streamer.thermal == .fair ? .white : .orange)
                }
                StripStyles.pill(streamer.source == "screen" ? "display" : streamer.source == "phone" ? (streamer.manualSource == "external" ? "video.fill" : "iphone") : "eyeglasses",
                     streamer.manualSource == "auto" ? "auto · \(streamer.source)"
                         : streamer.manualSource == "external" ? (streamer.externalCameraName ?? "external") : streamer.manualSource,
                     streamer.source == "phone" ? .orange : .white)
                if !overlays.scenes.isEmpty { scenePill }
                StripStyles.stripButton(label: {
                    // Silences chat and alerts only. Stream warnings speak regardless — see Speaker.
                    StripStyles.pill(speaker.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", speaker.muted ? "tts off" : "tts", speaker.muted ? .orange : .white)
                }, action: { hapticTap(); speaker.muted.toggle() })
                StripStyles.stripButton(label: {
                    StripStyles.pill("camera.shutter.button", "photo", .white)
                }, action: { hapticTap(); streamer.capturePhoto() })
                .disabled(streamer.glassesShort != "streaming")
                .opacity(streamer.glassesShort == "streaming" ? 1 : 0.4)
                StripStyles.stripButton(label: {
                    StripStyles.pill("slider.horizontal.3", "manage", .cyan)
                }, action: { hapticTap(); showManager = true })
                if phoneCamControllable {
                    StripStyles.stripButton(label: {
                        StripStyles.pill("camera.aperture", "cam", showCameraControls ? .cyan : .white)
                    }, action: { hapticTap(); showCameraControls.toggle() })
                }
            }
        }
        .padding(.top, 4)
        .sheet(isPresented: $showNetwork) { NetworkPanelView().environmentObject(streamer) }
    }

    /// White normally; orange when sending well under target or the queue backed up in the last 5 s; red while down.
    private var kbpsColor: Color {
        if streamer.connectedSince == nil { return .red }
        let target = streamer.currentBitrateKbps
        let slow = target > 0 && streamer.kbps < target * 7 / 10
        return slow || streamer.net.recentlyCongested() ? .orange : .white
    }

    /// nil below moderate — a pill that never clears is noise on a screen you glance at mid-walk.
    private func glassesHeat(_ level: ThermalLevel) -> String? {
        switch level {
        case .moderate: return "warm"
        case .severe: return "hot"
        case .critical, .emergency, .shutdown: return "overheating"
        default: return nil
        }
    }

    private var thermalLabel: String {
        switch streamer.thermal {
        case .fair: return "warm"
        case .serious: return "hot"
        case .critical: return "overheating"
        default: return "ok"
        }
    }

    private var glassesColor: Color {
        switch streamer.glassesShort {
        case "streaming": return .green
        case "connecting": return .orange
        default: return .gray
        }
    }

    private func elapsed(_ now: Date) -> String {
        guard let since = streamer.liveSince else { return "00:00" }
        let s = Int(now.timeIntervalSince(since))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Thin flat level bar for the mix (-60...0 dBFS); orange when near silent, red near clipping. Own view so the 8 Hz updates stay local.
struct LevelBar: View {
    @ObservedObject var meter: AudioLevel

    var body: some View {
        let fill = CGFloat(min(1, max(0, (meter.db + 60) / 60)))
        let color: Color = meter.db > -6 ? .red : meter.db < AudioMath.deadAirDB ? .orange : .green
        Capsule().fill(.white.opacity(0.2)).frame(width: 40, height: 4)
            .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 40 * fill, height: 4) }
            .padding(.horizontal, 12).padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityLabel("Audio level")
    }
}
