package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.saeedkolivand.metastream.core.Prefs

/** Microphone choice, like iOS micUID: "" = the system default. Persisted by a type+name key, since AudioDeviceInfo ids change. */
object Mics {
    var selected by mutableStateOf("")
        private set

    fun init() {
        selected = Prefs.string("micId")
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

    /** Null selection (or an unplugged device) leaves the source on the system default. */
    fun apply(context: Context, mic: MicrophoneSource) {
        val device = if (selected.isEmpty()) null else available(context).firstOrNull { key(it) == selected }
        mic.setPreferredDevice(device)
    }
}
