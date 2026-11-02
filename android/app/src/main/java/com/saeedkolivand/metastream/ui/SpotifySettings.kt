package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.graphics.Color
import com.saeedkolivand.metastream.platforms.Spotify

/** Settings › Spotify (iOS SpotifySettingsView): the account the Now playing widget, {song} / {artist} and !song read from. */
@Composable
internal fun SpotifyPage() {
    // Shows the current song here, even with no widget on screen.
    DisposableEffect(Unit) {
        Spotify.retain()
        onDispose { Spotify.release() }
    }
    Section("Spotify") {
        if (Spotify.connected) {
            Text("Connected")
            Spotify.track?.let { Note("Playing: ${it.title} · ${it.artist}") }
            TextButton({ Spotify.disconnect() }) { Text("Disconnect", color = Color(0xFFFF453A)) }
        } else {
            Button({ Spotify.connect() }) { Text("Connect Spotify") }
        }
        if (Spotify.status.isNotEmpty()) Note(Spotify.status)
        Footnote(
            "Shows what your Spotify account is playing on any device. Add the Now playing widget to a scene, or use {song} and " +
                "{artist} in a text widget. The account that owns the Spotify developer app needs Premium."
        )
    }
}
