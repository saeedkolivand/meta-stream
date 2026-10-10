import MWDATCore
import SwiftUI

/// Top status strip: connection, bitrate, battery, heat, source, mute, photo, manage, camera buttons.
/// Fixed pills never scroll the quick controls off screen -- see GoLiveControlsView's doc.
struct HUDView: View {
    @EnvironmentObject var streamer: Streamer
    @EnvironmentObject var speaker: Speaker
    @EnvironmentObject var privacy: Privacy
    @AppStorage("blurOn") var blurOn = false
    @AppStorage("bitrateKbps") var bitrateKbps = 4000
    @Binding var showStatus: Bool
    @Binding var showManager: Bool
    @Binding var showChat: Bool
    @Binding var showCameraControls: Bool

    private var phoneCamControllable: Bool { streamer.source == "phone" && streamer.manualSource != "external" }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if Streamer.glassesConfigured {
                    StripStyles.stripButton(label: {
                        StripStyles.pill("eyeglasses", streamer.glassesShort, glassesColor)
                    }, action: { showStatus = true })
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
                    StripStyles.pill("waveform", "\(streamer.fps) fps · \(streamer.kbps) kbps", .white)
                    if streamer.currentBitrateKbps > 0, streamer.currentBitrateKbps < bitrateKbps {
                        StripStyles.pill("arrow.down.right.circle", "\(streamer.currentBitrateKbps)k cap", .orange)
                    }
                } else {
                    StripStyles.pill("antenna.radiowaves.left.and.right", streamer.rtmpState, .gray)
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
                StripStyles.pill(streamer.source == "phone" ? (streamer.manualSource == "external" ? "video.fill" : "iphone") : "eyeglasses",
                     streamer.manualSource == "auto" ? "auto · \(streamer.source)"
                         : streamer.manualSource == "external" ? (streamer.externalCameraName ?? "external") : streamer.manualSource,
                     streamer.source == "phone" ? .orange : .white)
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
