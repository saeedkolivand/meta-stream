package com.saeedkolivand.metastream.streaming

import com.pedro.encoder.input.audio.CustomAudioEffect
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

private const val SOUND_SECONDS = 20 // iOS caps: soundboard 20 s, clips 60 s, alert sound 15 s
private const val CLIP_SECONDS = 60
private const val ALERT_SECONDS = 15
private const val REPORT_MS = 125L // the HUD meter's rate, like iOS LevelOutput

/** One sound in the mix: 44.1 kHz stereo samples and a read position (only the audio thread moves it). */
private class Play(val pcm: ShortArray, val loop: Boolean) {
    var pos = 0
}

/**
 * Sounds into the stream (iOS SoundMix): the alert sound, media-layer clip audio and the soundboard are added into the mic's
 * PCM in RootEncoder's audio-effect hook, so the mic is the clock and nothing plays on the phone speaker. The same hook
 * measures what goes out, for the HUD meter and dead air. Sounds only play while live and unmuted. Muting stays
 * RootEncoder's: it hands the encoder a zero buffer and skips this hook, so buffers keep flowing and A/V sync holds.
 * ponytail: one sound per kind at a time (a new one replaces it); a sound that was playing when you mute resumes on unmute.
 */
object AudioMix {
    private val alert = AtomicReference<Play?>(null)
    private val clip = AtomicReference<Play?>(null)
    private val board = AtomicReference<Play?>(null)
    private val clipGeneration = AtomicInteger()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val chime by lazy { AudioMath.chime() }
    private val decoded = HashMap<String, ShortArray>() // ponytail: soundboard decodes kept for the session (8 x 20 s max)

    @Volatile private var alertPcm: ShortArray? = null

    @Volatile private var alertGain = 1f

    @Volatile private var clipGain = 1f

    @Volatile private var soundGain = 1f

    @Volatile private var level = AudioMath.SILENCE_DB

    @Volatile private var levelAt = 0L

    private var peak = AudioMath.SILENCE_DB
    private var lastReport = 0L

    /** Mic volume (0..1) for Mics.apply; the other volumes apply inside the mix. */
    @Volatile var micGain = 1f
        private set

    /** Installed on the mic by Mics.apply. Runs on RootEncoder's audio thread: no allocation, no locks. */
    val effect = object : CustomAudioEffect() {
        override fun process(pcm: ByteArray): ByteArray {
            val n = pcm.size
            if (Engine.live) {
                mix(pcm, n, alert, alertGain)
                mix(pcm, n, clip, clipGain)
                mix(pcm, n, board, soundGain)
            }
            peak = max(peak, AudioMath.dBFS(pcm, n))
            val now = System.currentTimeMillis()
            if (now - lastReport >= REPORT_MS) {
                lastReport = now
                level = peak
                levelAt = now
                peak = AudioMath.SILENCE_DB
            }
            return pcm
        }
    }

    private fun mix(pcm: ByteArray, n: Int, slot: AtomicReference<Play?>, gain: Float) {
        val p = slot.get() ?: return
        p.pos += AudioMath.mixInto(pcm, n, p.pcm, p.pos, gain)
        if (p.pos < p.pcm.size) return
        if (p.loop && p.pcm.isNotEmpty()) p.pos = 0 else slot.compareAndSet(p, null)
    }

    fun init() {
        applyVolumes()
        reloadAlert()
    }

    /** Re-reads the Settings volumes (0..100); the mic one reaches the mic through Engine.refreshMic. */
    fun applyVolumes() {
        micGain = AudioMath.gain(Prefs.int("volMic", 100))
        alertGain = AudioMath.gain(Prefs.int("volAlert", 100))
        clipGain = AudioMath.gain(Prefs.int("volClip", 100))
        soundGain = AudioMath.gain(Prefs.int("volSound", 100))
    }

    /** Decodes the custom alert sound (Soundboard.alertSound) off the main thread; "" keeps the chime. */
    fun reloadAlert() {
        val name = Soundboard.alertSound
        alertPcm = null
        if (name.isEmpty()) return
        scope.launch { alertPcm = decodeAudio(Soundboard.file(name), ALERT_SECONDS) }
    }

    /** The mix's level in dBFS for the HUD; silence when it hasn't reported for [staleMs] (no buffers, or muted). */
    fun level(staleMs: Long = 1000): Float =
        if (Engine.muted || System.currentTimeMillis() - levelAt > staleMs) AudioMath.SILENCE_DB else level

    private fun playing() = Engine.live && !Engine.muted

    /** With an alert banner, into the mix; ignored unless live (iOS AlertWidget). */
    fun playAlert() {
        if (playing()) alert.set(Play(alertPcm ?: chime, loop = false))
    }

    fun playSound(s: Sound) {
        if (!playing()) return
        scope.launch {
            val pcm = synchronized(decoded) { decoded[s.file] } ?: decodeAudio(Soundboard.file(s.file), SOUND_SECONDS)?.also {
                synchronized(decoded) { decoded[s.file] = it }
            }
            if (pcm == null) applog("audio", "sound ${s.name} has no audio") else board.set(Play(pcm, loop = false))
        }
    }

    /**
     * A media layer's audio; a later clip replaces the earlier one. ponytail: loose sync like iOS. It starts when the layer
     * is built and loops by itself while the video loops on its own, so they can drift; it only advances while live.
     */
    fun playClip(file: File, loop: Boolean) {
        val gen = clipGeneration.incrementAndGet()
        clip.set(null)
        scope.launch {
            val pcm = decodeAudio(file, CLIP_SECONDS) ?: return@launch // a video without an audio track plays nothing
            if (clipGeneration.get() == gen) clip.set(Play(pcm, loop))
        }
    }

    fun stopClips() {
        clipGeneration.incrementAndGet()
        clip.set(null)
    }
}
