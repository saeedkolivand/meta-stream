package com.saeedkolivand.metastream.core.storage

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** A persisted on/off setting that Compose can observe. */
class BoolPref(private val key: String, default: Boolean) {
    var value by mutableStateOf(Prefs.bool(key, default))
        private set

    fun set(v: Boolean) {
        value = v
        Prefs.put(key, v)
    }
}
