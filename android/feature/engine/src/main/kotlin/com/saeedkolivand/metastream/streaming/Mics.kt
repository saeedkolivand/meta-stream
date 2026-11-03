package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pedro.encoder.input.sources.audio.AudioSource
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.audio.MixAudioSource
import com.pedro.library.generic.GenericStream
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs

/** Microphone choice, like iOS micUID: "" = the system default. Persisted by a type+name key, since AudioDeviceInfo ids change. */
object Mics {
    var selected by mutableStateOf("")
        private set

    fun init(context: Context) {
        selected = Prefs.string("micId")
        // iOS AudioRouteLog: which mic the app really hears, at launch, go-live and every plug/unplug, so pulled logs show it.
        context.getSystemService(AudioManager::class.java).registerAudioDeviceCallback(
            object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) {
                    if (added.any { it.isSource && it.type in usable }) log(context, "plugged in")
                }

                override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) {
                    if (removed.any { it.isSource && it.type in usable }) log(context, "unplugged")
                }
            },
            null
        )
    }

    /** "mic go live: DJI Mic (USB), 48000 Hz" : the chosen device if plugged in, else the system default. */
    fun log(context: Context, why: String) {
        val am = context.getSystemService(AudioManager::class.java)
        val chosen = available(context).firstOrNull { selected.isNotEmpty() && key(it) == selected }
        val name = chosen?.let(::label) ?: "system default, inputs: ${available(context).joinToString { label(it) }.ifEmpty { "none" }}"
        applog("audio", "mic $why: $name, ${am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE) ?: "?"} Hz")
    }

    fun key(d: AudioDeviceInfo) = "${d.type}:${d.productName}"

    fun label(d: AudioDeviceInfo) = "${d.productName} (${typeName(d.type)})"

    private fun typeName(t: Int) = when (t) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "built-in"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired headset"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
        else -> "type $t"
    }

    // Only real capture devices; the input list also holds telephony, FM tuner, remote-submix and bus entries.
    private val usable = setOf(
        AudioDeviceInfo.TYPE_BUILTIN_MIC,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET
    )

    fun available(context: Context): List<AudioDeviceInfo> =
        context.getSystemService(AudioManager::class.java).getDevices(AudioManager.GET_DEVICES_INPUTS).filter { it.type in usable }

    fun select(key: String) {
        selected = key
        Prefs.put("micId", key)
    }

    /** Null selection (or an unplugged device) leaves the source on the system default. Also the mix: volume and sounds. */
    fun apply(context: Context, src: AudioSource) {
        val device = if (selected.isEmpty()) null else available(context).firstOrNull { key(it) == selected }
        when (src) {
            is MicrophoneSource -> {
                src.setPreferredDevice(device)
                src.microphoneVolume = AudioMix.micGain
                src.setAudioEffect(AudioMix.effect)
            }
            is MixAudioSource -> { // screen share: the mic mixed with the apps' own audio
                src.setPreferredDevice(device)
                src.microphoneVolume = AudioMix.micGain
                src.setAudioEffect(AudioMix.effect)
            }
        }
    }

    /** Mute or unmute whichever source the stream holds. */
    fun mute(src: AudioSource, on: Boolean) {
        when (src) {
            is MicrophoneSource -> if (on) src.mute() else src.unMute()
            is MixAudioSource -> if (on) src.mute() else src.unMute()
        }
    }

    /**
     * Screen share with a projection carries the apps' audio mixed with the mic (AudioPlaybackCapture; apps that opt out stay
     * silent) unless Settings › Audio turns it off. Swaps only when that changes; mute and the mix carry over.
     */
    fun sync(context: Context, s: GenericStream, screen: Boolean, muted: Boolean) {
        val mix = if (screen && Prefs.bool("screenAppAudio", true)) ScreenShare.appAudio() else null
        if ((mix != null) == (s.audioSource is MixAudioSource)) return
        val next = mix ?: MicrophoneSource()
        try {
            s.changeAudioSource(next)
        } catch (e: IllegalArgumentException) {
            applog("audio", "can't swap audio source: ${e.message}")
            return
        }
        apply(context, next)
        mute(next, muted)
        applog("audio", if (mix != null) "screen share: app audio + mic" else "mic only")
    }
}
