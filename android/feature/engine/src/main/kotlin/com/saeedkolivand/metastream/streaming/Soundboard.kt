package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** A soundboard entry (iOS Sound): a file copied into filesDir/sounds. */
data class Sound(val name: String, val file: String)

/** The soundboard (max 8, JSON in Prefs "sounds") and the alert sound ("" = the built-in chime), like iOS AudioSettingsView. */
object Soundboard {
    const val MAX = 8

    var sounds by mutableStateOf(listOf<Sound>())
        private set

    /** File name in the sounds folder, or "" for the built-in chime. */
    var alertSound by mutableStateOf("")
        private set

    private lateinit var folder: File

    fun init(context: Context) {
        folder = File(context.filesDir, "sounds").apply { mkdirs() }
        alertSound = Prefs.string("alertSound")
        sounds = runCatching {
            val a = JSONArray(Prefs.string("sounds", "[]"))
            (0 until a.length()).map { a.getJSONObject(it).let { o -> Sound(o.getString("name"), o.getString("file")) } }
        }.getOrDefault(emptyList())
    }

    fun file(name: String) = File(folder, name)

    fun add(context: Context, uri: Uri) {
        if (sounds.size >= MAX) return
        val (file, display) = import(context, uri) ?: return
        save(sounds + Sound(display.substringBeforeLast('.'), file))
    }

    fun rename(index: Int, name: String) = save(sounds.mapIndexed { i, s -> if (i == index) s.copy(name = name) else s })

    fun remove(index: Int) {
        sounds.getOrNull(index)?.let { file(it.file).delete() }
        save(sounds.filterIndexed { i, _ -> i != index })
    }

    /** A picked file as the alert sound, or null for the chime; the previous file is deleted. */
    fun setAlert(context: Context, uri: Uri?) {
        val next = uri?.let { import(context, it)?.first } ?: ""
        if (alertSound.isNotEmpty()) file(alertSound).delete()
        alertSound = next
        Prefs.put("alertSound", next)
        AudioMix.reloadAlert()
    }

    /** The alert sound's display name (the stored name minus its unique prefix). */
    fun alertLabel() = if (alertSound.isEmpty()) "Chime" else alertSound.substringAfter('-')

    private fun save(list: List<Sound>) {
        sounds = list
        Prefs.put("sounds", JSONArray(list.map { JSONObject().put("name", it.name).put("file", it.file) }).toString())
    }

    /** Copies a picked document in under a unique name; (stored name, display name), or null when the copy failed. */
    private fun import(context: Context, uri: Uri): Pair<String, String>? = try {
        val display = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "sound"
        val name = UUID.randomUUID().toString().take(8) + "-" + display.replace(Regex("[^\\w.\\- ]"), "_")
        context.contentResolver.openInputStream(uri)!!.use { input -> file(name).outputStream().use { input.copyTo(it) } }
        name to display
    } catch (e: Exception) {
        applog("audio", "sound import failed: ${e.message}")
        null
    }
}
