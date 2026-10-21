import SwiftUI

/// Top-level settings: a category list, each pushing its own Form (standard iOS pattern). Every
/// @AppStorage key below is unchanged from the old single-Form layout -- moving a setting to a new
/// screen never touches its key, so nobody's saved value gets silently discarded by this reorg.
/// ponytail: no search. A search index needs hand-maintaining as settings are added and rots silently
/// the moment someone forgets to update it -- seven categories is small enough to scan by eye.
/// Screens live in Views/Settings/; shared rows live in SettingsControls.swift.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wrappedPending = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { StreamsView() } label: {
                        HStack {
                            Text("Streams")
                            Spacer()
                            if wrappedPending { Circle().fill(Color.accentColor).frame(width: 8, height: 8) }
                        }
                    }
                    NavigationLink("Ingest & protocol") { IngestSettingsView() }
                    if Streamer.glassesConfigured { NavigationLink("Meta glasses") { GlassesVideoSettingsView() } }
                    NavigationLink("Camera") { CameraSettingsView() }
                    NavigationLink("Scenes & widgets") { OverlaySettingsView() }
                    NavigationLink("Theme & story") { ThemeSettingsView() }
                    NavigationLink("Goal") { GoalSettingsView() }
                    NavigationLink("Telegram") { TelegramSettingsView() }
                    NavigationLink("Spotify") { SpotifySettingsView() }
                    NavigationLink("Audio") { AudioSettingsView() }
                    NavigationLink("Read aloud") { ReadAloudSettingsView() }
                    NavigationLink("Chat commands") { CommandsSettingsView() }
                    NavigationLink("Chat bots") { BotsSettingsView() }
                    NavigationLink("App bot") { AppBotSettingsView() }
                    NavigationLink("Privacy") { PrivacySettingsView() }
                    NavigationLink("Remote control") { RemoteSettingsView() }
                }
                Section {
                    NavigationLink("Diagnostics & about") { DiagnosticsSettingsView() }
                }
            }
            .onAppear { wrappedPending = WrappedStore.pendingMonth(records: SessionLog.all()) != nil }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
