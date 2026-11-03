package com.saeedkolivand.metastream.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.storage.BoolPref
import com.saeedkolivand.metastream.core.storage.Prefs

/** Chat settings shared by the feed, read-aloud and the stream widgets (keys unchanged from read-aloud's, as on iOS). */
object ChatSettings {
    // Per-platform chat toggles: an off platform is not connected at all (no list rows, no speech).
    val kickChat = BoolPref("voiceKick", true)
    val twitchChat = BoolPref("voiceTwitch", true)
    val youtubeChat = BoolPref("voiceYouTube", true)

    /** Extra words that keep a message from being read or shown on stream, comma separated (iOS ttsBlocked). */
    var blocked by mutableStateOf(Prefs.string("ttsBlocked"))
        private set

    fun pickBlocked(s: String) {
        blocked = s
        Prefs.put("ttsBlocked", s)
    }
}
