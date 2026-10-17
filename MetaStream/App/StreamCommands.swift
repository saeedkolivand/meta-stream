import SwiftUI

/// Magic Keyboard shortcuts (shown when holding ⌘). No go-live/stop shortcut on purpose: too easy to hit by accident.
struct StreamCommands: Commands {
    @ObservedObject var streamer: Streamer
    @ObservedObject var speaker: Speaker
    @ObservedObject private var store = OverlayStore.shared

    var body: some Commands {
        CommandMenu("Stream") {
            ForEach(0..<9, id: \.self) { i in
                let name = store.scenes.indices.contains(i) ? store.scenes[i].name : nil
                Button(name.map { "Scene \(i + 1): \($0)" } ?? "Scene \(i + 1)") { if let name { streamer.selectScene(name) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .disabled(name == nil)
            }
            Button("No overlay") { streamer.selectScene("") }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button(streamer.muted ? "Unmute microphone" : "Mute microphone") { streamer.setMuted(!streamer.muted) }
                .keyboardShortcut("m", modifiers: .command)
            Button(streamer.recordingSince != nil ? "Stop recording" : "Start recording") { streamer.toggleRecording() }
                .keyboardShortcut("r", modifiers: .command)
            Button(speaker.muted ? "Unmute read-aloud" : "Mute read-aloud") { speaker.muted.toggle() }
                .keyboardShortcut("t", modifiers: .command)
        }
    }
}
