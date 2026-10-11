package com.saeedkolivand.metastream.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Persisted user settings as Compose snapshot state; writes go through the update functions. */
object AppSettings {
    var ingest by mutableStateOf(IngestConfig())
        private set
    var glassesResolution by mutableStateOf("high")
        private set
    var glassesFps by mutableIntStateOf(30)
        private set
    var keepAwake by mutableStateOf(true)
        private set

    fun init() {
        val d = IngestConfig()
        ingest = IngestConfig(
            Prefs.int("height", d.height),
            Prefs.int("fps", d.fps),
            Prefs.int("bitrateKbps", d.bitrateKbps),
            Prefs.bool("h265"),
            Lock.entries.firstOrNull { it.name == Prefs.string("lock") } ?: d.lock,
            Prefs.int("srtLatencyMs", d.srtLatencyMs)
        )
        glassesResolution = Prefs.string("gResolution", "high")
        glassesFps = Prefs.int("gFps", 30)
        keepAwake = Prefs.bool("keepAwake", true)
    }

    fun updateIngest(c: IngestConfig) {
        ingest = c
        Prefs.put("height", c.height)
        Prefs.put("fps", c.fps)
        Prefs.put("bitrateKbps", c.bitrateKbps)
        Prefs.put("h265", c.h265)
        Prefs.put("lock", c.lock.name)
        Prefs.put("srtLatencyMs", c.srtLatencyMs)
    }

    fun restoreIngestDefaults() = updateIngest(IngestConfig())

    fun updateGlasses(resolution: String = glassesResolution, fps: Int = glassesFps) {
        glassesResolution = resolution
        glassesFps = fps
        Prefs.put("gResolution", resolution)
        Prefs.put("gFps", fps)
    }

    fun updateKeepAwake(on: Boolean) {
        keepAwake = on
        Prefs.put("keepAwake", on)
    }
}
