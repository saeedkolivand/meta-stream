package com.saeedkolivand.metastream.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.remote.ObsServer

/** Settings › Remote control (iOS RemoteSettingsView): the obs-websocket server for Stream Deck, Touch Portal, Streamer.bot. */
@Composable
internal fun RemotePage() {
    val scope = rememberCoroutineScope()
    var on by remember { mutableStateOf(Prefs.bool("obsServerOn", false)) }
    var password by remember { mutableStateOf(Prefs.string("obsPassword", "")) }
    Section(
        null,
        "Lets Stream Deck, Touch Portal and Streamer.bot control the app as if it were OBS: scenes, go live, record, mic, sounds. " +
            "Local network only (same Wi-Fi, or this phone's hotspot). In the controller, add an OBS connection with the address, " +
            "port and password below."
    ) {
        SwitchRow("obs-websocket server", on) {
            on = it
            Prefs.put("obsServerOn", it)
            ObsServer.sync(scope)
            password = Prefs.string("obsPassword", "")
        }
    }
    if (!on) return
    Section("Password") {
        TextRow("Password", password, {
            password = it
            Prefs.put("obsPassword", it)
            ObsServer.revokeSessions()
        })
        ActionRow("Regenerate") {
            password = ObsServer.randomPassword()
            Prefs.put("obsPassword", password)
            ObsServer.revokeSessions()
        }
        if (password.length < 8) Text("Use at least 8 characters: shorter passwords are refused.", color = Orange)
    }
    Section("Address (port ${ObsServer.PORT})") {
        val ips = remember { ObsServer.addresses() }
        ips.forEach { (label, ip) -> ValueRow(label, ip) }
        if (ips.isEmpty()) Text("Not on a network", color = Secondary)
    }
}
