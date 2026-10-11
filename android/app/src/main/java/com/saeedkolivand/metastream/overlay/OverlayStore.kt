package com.saeedkolivand.metastream.overlay

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.documentfile.provider.DocumentFile
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import java.io.File

/** The imported pack (JSON in filesDir), the files copied next to it, and which scene is active. Main-thread state. */
object OverlayStore {
    private lateinit var app: Application
    private val dir get() = File(app.filesDir, "overlays")
    private val packFile get() = File(dir, "pack.json")

    var pack by mutableStateOf<Pack?>(null)
        private set

    /** Active scene name; empty means none. */
    var scene by mutableStateOf("")
        private set

    /** Import/locate result for the settings sheet. */
    var message by mutableStateOf("")
        private set

    fun init(application: Application) {
        app = application
        scene = Prefs.string("overlayScene")
        pack = runCatching { Pack.fromJson(packFile.readText()) }.getOrNull()
    }

    fun select(name: String) {
        scene = name
        Prefs.put("overlayScene", name)
        Overlays.refresh()
    }

    fun active(): Scene? = pack?.scenes?.firstOrNull { it.name == scene }

    /** Local path of a file the scene refers to by its Windows path, or null while it hasn't been located. */
    fun local(path: String): File? = File(dir, baseName(path)).takeIf { it.isFile }

    fun missing(): List<String> = pack?.files()?.filter { local(it) == null }.orEmpty()

    fun import(uri: Uri) {
        val text = runCatching { app.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() } }.getOrNull()
        // Only counts reach the log: the file carries account tokens.
        val parsed = runCatching { parseObs(text.orEmpty()) }.getOrNull()
        if (parsed == null || parsed.scenes.isEmpty()) {
            message = "That file isn't an OBS scene collection"
            return
        }
        dir.mkdirs()
        packFile.writeText(parsed.toJson())
        pack = parsed
        if (parsed.scenes.none { it.name == scene }) select("")
        val n = parsed.scenes.sumOf { it.layers.size }
        applog("overlay", "imported ${parsed.scenes.size} scenes, $n layers")
        message =
            listOf("Imported ${parsed.scenes.size} scenes, $n layers.", parsed.skippedText(), missingText()).filter {
                it.isNotEmpty()
            }.joinToString(" ")
        Overlays.refresh()
    }

    private fun missingText() = missing().size.let { if (it == 0) "" else "$it files not found: tap Locate files." }

    /** Copies every missing file whose name appears anywhere under [tree] into app storage. */
    fun locate(tree: Uri) {
        val wanted = missing().associateBy { baseName(it).lowercase() }
        if (wanted.isEmpty()) return
        dir.mkdirs()
        val root = DocumentFile.fromTreeUri(app, tree) ?: return
        val stack = ArrayDeque(listOf(root))
        var found = 0
        while (stack.isNotEmpty() && found < wanted.size) {
            for (f in stack.removeLast().listFiles()) {
                if (f.isDirectory) {
                    stack.addLast(f)
                } else {
                    // Saved under the scene's spelling of the name: local() looks it up case-sensitively.
                    val target = wanted[f.name?.lowercase()]?.let { File(dir, baseName(it)) } ?: continue
                    if (target.exists()) continue
                    runCatching {
                        app.contentResolver.openInputStream(f.uri)?.use { i -> target.outputStream().use { i.copyTo(it) } }
                    }.onSuccess { found++ }
                }
            }
        }
        message = "Copied $found of ${wanted.size} files. ${missingText()}".trim()
        Overlays.refresh()
    }

    private fun baseName(path: String) = path.substringAfterLast('/').substringAfterLast('\\')
}
