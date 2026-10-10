package com.saeedkolivand.metastream.speech

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.core.Prefs
import java.util.concurrent.atomic.AtomicInteger

/** Text-to-speech for chat read-aloud and system alerts. State is Compose snapshot state with a private setter. */
object Speaker {
    var readAloud by mutableStateOf(false)
        private set

    @Volatile private var tts: TextToSpeech? = null

    @Volatile private var ready = false
    private val pending = AtomicInteger() // utterances queued or playing

    fun init(context: Context) {
        readAloud = Prefs.bool("readAloud")
        tts = TextToSpeech(context) { status ->
            if (status != TextToSpeech.SUCCESS) return@TextToSpeech
            // ponytail: NAVIGATION_GUIDANCE (not MEDIA) so alerts duck the music and play over car audio like turn-by-turn
            // prompts; USAGE_ASSISTANT would also work but some head units treat it as a call-like interruption.
            tts?.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            tts?.setOnUtteranceProgressListener(
                object : UtteranceProgressListener() {
                    override fun onStart(id: String?) {}

                    override fun onDone(id: String?) {
                        pending.decrementAndGet()
                    }

                    @Deprecated("required override")
                    override fun onError(id: String?) {
                        pending.decrementAndGet()
                    }

                    override fun onStop(id: String?, interrupted: Boolean) {
                        pending.decrementAndGet()
                    }
                }
            )
            ready = true
        }
    }

    fun updateReadAloud(on: Boolean) {
        readAloud = on
        Prefs.put("readAloud", on)
    }

    private fun speak(text: String, flush: Boolean) {
        if (!ready) return
        pending.incrementAndGet()
        val mode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        if (tts?.speak(text, mode, Bundle(), "m${System.nanoTime()}") != TextToSpeech.SUCCESS) pending.decrementAndGet()
    }

    // ponytail: iOS has a 5-deep chat lane and a 20/min cap; here one cap of 5 queued utterances drops new chat when
    // behind (Android TTS can't drop the oldest queued item). Upgrade path: own queue like Speaker.swift.
    fun speakChat(e: ChatEvent) {
        if (!readAloud) return
        val text = sanitizeSpeech(e.text)
        if (text.isNotEmpty() && pending.get() < 5) speak("${e.user} says $text", false)
    }

    /** System alerts interrupt and ignore the read-aloud toggle, like iOS speakSystem. */
    fun speakSystem(text: String) = speak(text, true)
}
