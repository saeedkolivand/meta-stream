package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.platforms.Spotify

/** Settings › Spotify (iOS SpotifySettingsView): the account the Now playing widget, {song} / {artist} and !song read from. */
@Composable
internal fun SpotifyPage() {
    // Shows the current song here, even with no widget on screen.
    DisposableEffect(Unit) {
        Spotify.retain()
        onDispose { Spotify.release() }
    }
    Section(
        "Spotify",
        "Shows what your Spotify account is playing on any device. Add the Now playing widget to a scene, or use {song} and " +
            "{artist} in a text widget. The account that owns the Spotify developer app needs Premium."
    ) {
        if (Spotify.connected) {
            Text("Connected", fontSize = 17.sp)
            Spotify.track?.let { Text("Playing: ${it.artist} - ${it.title}", color = Secondary, fontSize = 17.sp) }
            ActionRow("Disconnect", destructive = true) { Spotify.disconnect() }
        } else {
            ActionRow("Connect Spotify") { Spotify.connect() }
        }
        if (Spotify.status.isNotEmpty()) Text(Spotify.status, color = Secondary, fontSize = 13.sp)
    }
}
