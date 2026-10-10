import SwiftUI

/// Top-level settings: a category list, each pushing its own Form (standard iOS pattern). Every
/// @AppStorage key below is unchanged from the old single-Form layout -- moving a setting to a new
/// screen never touches its key, so nobody's saved value gets silently discarded by this reorg.
/// ponytail: no search. A search index needs hand-maintaining as settings are added and rots silently
/// the moment someone forgets to update it -- seven categories is small enough to scan by eye.
/// Screens live in Views/Settings/; shared rows live in SettingsControls.swift.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Ingest & protocol") { IngestSettingsView() }
                    NavigationLink("Video (glasses)") { GlassesVideoSettingsView() }
                    NavigationLink("Camera") { CameraSettingsView() }
                    NavigationLink("Audio") { AudioSettingsView() }
                    NavigationLink("Read aloud") { ReadAloudSettingsView() }
                    NavigationLink("Privacy") { PrivacySettingsView() }
                }
                Section {
                    NavigationLink("Diagnostics & about") { DiagnosticsSettingsView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
