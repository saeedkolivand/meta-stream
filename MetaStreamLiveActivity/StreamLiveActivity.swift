// Lock Screen / Dynamic Island UI for the stream. Built for a glance while driving: big timer, one pill,
// two big buttons. The .small family is the Apple Watch Smart Stack / CarPlay Dashboard layout (no buttons:
// CarPlay ignores them).
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private typealias StreamState = StreamActivityAttributes.ContentState

struct StreamLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreamActivityAttributes.self) { context in
            FamilyView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.8))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { PhasePill(state: state) }
                DynamicIslandExpandedRegion(.trailing) { ElapsedText(state: state).font(.title3.bold()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        StatsLine(state: state)
                        if state.phase != "ended" { Controls(state: state) }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle().fill(phaseColor(state.phase)).frame(width: 8, height: 8)
                    ElapsedText(state: state).font(.caption2).frame(maxWidth: 48)
                }
            } compactTrailing: {
                Text("\(state.kbps)k").font(.caption2.monospacedDigit())
            } minimal: {
                Circle().fill(phaseColor(state.phase)).frame(width: 10, height: 10)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Picks the Lock Screen layout or the small one the system asks for on Apple Watch and in CarPlay.
private struct FamilyView: View {
    let state: StreamState
    @Environment(\.activityFamily) private var family
    var body: some View {
        if family == .small {
            HStack {
                PhasePill(state: state)
                Spacer()
                ElapsedText(state: state).font(.headline)
            }
        } else {
            LockScreenView(state: state)
        }
    }
}

private func phaseColor(_ phase: String) -> Color {
    switch phase {
    case "live": .red
    case "reconnecting": .orange
    default: .gray
    }
}

private struct LockScreenView: View {
    let state: StreamState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PhasePill(state: state)
                Spacer()
                ElapsedText(state: state).font(.title.bold())
            }
            StatsLine(state: state)
            if state.phase != "ended" { Controls(state: state) }
        }
    }
}

private struct PhasePill: View {
    let state: StreamState
    var body: some View {
        Text(state.phase.uppercased())
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(phaseColor(state.phase), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// Count-up from liveSince: the system ticks it, the app sends no per-second updates. Once ended, the
/// interval closes at endedAt so the lingering card shows the final duration instead of still ticking.
private struct ElapsedText: View {
    let state: StreamState
    var body: some View {
        Group {
            if let end = state.endedAt {
                Text(timerInterval: state.liveSince...max(end, state.liveSince), countsDown: false)
            } else {
                Text(state.liveSince, style: .timer)
            }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }
}

private struct StatsLine: View {
    let state: StreamState
    var body: some View {
        Text("\(state.source.capitalized) · \(state.kbps) kbps · \(state.drops) drops")
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
    }
}

private struct Controls: View {
    let state: StreamState
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(intent: ToggleMuteIntent()) {
                    Label(state.muted ? "Unmute" : "Mute", systemImage: state.muted ? "mic.slash.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                Button(intent: StopStreamIntent()) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(.red)
            }
            if !state.commands.isEmpty {
                HStack(spacing: 8) {
                    ForEach(state.commands, id: \.id) { c in
                        Button(intent: SendCommandIntent(commandID: c.id)) { Text(c.text).lineLimit(1).frame(maxWidth: .infinity) }
                    }
                }
                .font(.subheadline)
            }
        }
        .font(.headline)
    }
}
