package com.saeedkolivand.metastream.speech

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.Prefs

/** A persisted on/off setting that Compose can observe. */
class BoolPref(private val key: String, default: Boolean) {
    var value by mutableStateOf(Prefs.bool(key, default))
        private set

    fun set(v: Boolean) {
        value = v
        Prefs.put(key, v)
    }
}

/** Read-aloud settings, same keys and defaults as iOS ReadAloudSettingsView/Speaker (@AppStorage). */
object SpeechSettings {
    val messages = BoolPref("ttsMessagesOn", true)
    val tips = BoolPref("ttsTipsOn", true)
    val follows = BoolPref("ttsFollowsOn", true)
    val subs = BoolPref("ttsSubsOn", true)
    val raids = BoolPref("ttsRaidsOn", true)

    // Per-platform chat toggles: an off platform is not connected at all (no list rows, no speech).
    val kickChat = BoolPref("voiceKick", true)
    val twitchChat = BoolPref("voiceTwitch", true)
    val youtubeChat = BoolPref("voiceYouTube", true)

    /** TextToSpeech voice name; empty = engine default. */
    var voice by mutableStateOf(Prefs.string("ttsVoiceID"))
        private set

    /** iOS-style 0.35..0.65 around a 0.5 default (Android's own scale is this / 0.5). */
    var rate by mutableStateOf(Prefs.string("ttsRate").toFloatOrNull() ?: DEFAULT_RATE)
        private set

    /** Tips below this are not read; whole dollars like iOS. */
    var minTipCents by mutableStateOf(Prefs.string("ttsMinTipCents").toIntOrNull() ?: 0)
        private set

    fun pickVoice(name: String) {
        voice = name
        Prefs.put("ttsVoiceID", name)
    }

    fun pickRate(r: Float) {
        rate = r
        Prefs.put("ttsRate", r.toString())
    }

    fun pickMinTip(c: Int) {
        minTipCents = c
        Prefs.put("ttsMinTipCents", c.toString())
    }

    fun options() = SpeechOptions(messages.value, tips.value, follows.value, subs.value, raids.value, minTipCents)

    const val DEFAULT_RATE = 0.5f
}
