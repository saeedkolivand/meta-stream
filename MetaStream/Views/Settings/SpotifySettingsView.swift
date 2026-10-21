import SwiftUI

/// Settings › Spotify: the account the Now playing widget and the {song} / {artist} tokens read from.
struct SpotifySettingsView: View {
    @ObservedObject private var spotify = SpotifyNowPlaying.shared

    var body: some View {
        Form {
            Section {
                if spotify.connected {
                    Text("Connected")
                    if let t = spotify.track { Text("Playing: \(t.title) · \(t.artist)").foregroundStyle(.secondary) }
                    Button("Disconnect", role: .destructive) { spotify.disconnect() }
                } else {
                    Button("Connect Spotify") { spotify.connect() }
                }
                if !spotify.status.isEmpty { Text(spotify.status).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Spotify") } footer: {
                Text("Shows what your Spotify account is playing on any device. Add the Now playing widget to a scene, or "
                     + "use {song} and {artist} in a text widget. The account that owns the Spotify developer app needs Premium.")
            }
        }
        .navigationTitle("Spotify")
        .onAppear { spotify.retain() }       // shows the current song here, even with no widget on screen
        .onDisappear { spotify.release() }
    }
}
