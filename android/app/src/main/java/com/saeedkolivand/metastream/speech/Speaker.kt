package com.saeedkolivand.metastream.speech

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
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

    /** Installed voices once the engine is up, sorted for the picker; empty until then. */
    var voices by mutableStateOf<List<Voice>>(emptyList())
        private set

    /** Set by ChatFeed when more than one chat origin is live, so lines say "on Kick, ...". */
    @Volatile var showOrigin = false

    @Volatile private var tts: TextToSpeech? = null

    @Volatile private var ready = false
    private val pending = AtomicInteger() // utterances queued or playing
    private var appContext: Context? = null

    @Volatile private var early: Pair<String, Boolean>? = null // the latest line asked for before the engine was ready

    /** Reads the toggle and defers the engine: building TextToSpeech at app start spends memory and wakes the TTS service. */
    fun init(context: Context) {
        appContext = context.applicationContext
        readAloud = Prefs.bool("readAloud")
        if (readAloud) prepare()
    }

    /** Creates the engine on first actual use (read-aloud on, a preview, the voice picker, or a system alert). */
    fun prepare() {
        if (tts != null) return
        val ctx = appContext ?: return
        tts = TextToSpeech(ctx) { status ->
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
            early?.let { (t, f) -> speak(t, f) }
            early = null
            voices =
                runCatching {
                    tts?.voices.orEmpty().sortedWith(compareBy({ it.locale.displayName }, { it.name }))
                }.getOrDefault(emptyList())
            applyVoice()
        }
    }

    /** Applies the saved voice and speed; the engine default stays when the saved voice is no longer installed. */
    fun applyVoice() {
        prepare()
        tts?.setSpeechRate(SpeechSettings.rate / SpeechSettings.DEFAULT_RATE)
        voices.firstOrNull { it.name == SpeechSettings.voice }?.let { tts?.voice = it }
    }

    /** Plays [text] in the selected voice so the picker can be auditioned. */
    fun preview(text: String) = speak(text, true)

    fun updateReadAloud(on: Boolean) {
        readAloud = on
        Prefs.put("readAloud", on)
        if (on) prepare() else tts?.stop() // off means quiet now, not after the queued messages finish
    }

    private fun speak(text: String, flush: Boolean) {
        prepare() // a system alert or first chat line may be the first thing that needs the engine
        if (!ready) {
            early = text to flush // the engine binds asynchronously; say this once it's up instead of dropping a stream alert
            return
        }
        pending.incrementAndGet()
        val mode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        if (tts?.speak(text, mode, Bundle(), "m${System.nanoTime()}") != TextToSpeech.SUCCESS) pending.decrementAndGet()
    }

    // ponytail: iOS has a 5-deep chat lane and a 20/min cap; here one cap of 5 queued utterances drops new chat when
    // behind (Android TTS can't drop the oldest queued item). Upgrade path: own queue like Speaker.swift.
    /** Chat messages and alerts (tips/follows/subs/raids), gated by the read-aloud toggle and the per-kind settings. */
    fun speakChat(e: ChatEvent) {
        if (!readAloud || e.platform == "test") return // the Logs screen's flood test is never spoken
        val text = spokenText(e, SpeechSettings.options()) ?: return
        val origin = if (showOrigin) "on ${e.platform.replaceFirstChar(Char::uppercase)}, " else ""
        if (pending.get() < 5) speak(origin + text, false)
    }

    /** System alerts interrupt and ignore the read-aloud toggle, like iOS speakSystem. */
    fun speakSystem(text: String) = speak(text, true)
}
