package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog

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
    fun apply(context: Context, mic: MicrophoneSource) {
        val device = if (selected.isEmpty()) null else available(context).firstOrNull { key(it) == selected }
        mic.setPreferredDevice(device)
        mic.microphoneVolume = AudioMix.micGain
        mic.setAudioEffect(AudioMix.effect)
    }
}
