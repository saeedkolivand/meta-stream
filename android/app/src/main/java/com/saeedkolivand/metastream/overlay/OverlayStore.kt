package com.saeedkolivand.metastream.overlay

import android.app.Application
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.documentfile.provider.DocumentFile
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import java.io.File
import java.util.UUID
import org.json.JSONArray

private const val MAX_IMAGE_BYTES = 25 * 1024 * 1024

/** The scenes (JSON in filesDir), the files copied next to it, and which scene is active. Main-thread state. */
object OverlayStore {
    private lateinit var app: Application
    private val dir get() = File(app.filesDir, "overlays")
    private val packFile get() = File(dir, "pack.json")

    var pack by mutableStateOf<Pack?>(null)
        private set

    val scenes: List<Scene> get() = pack?.scenes.orEmpty()

    /** Active scene name; empty means none. */
    var scene by mutableStateOf("")
        private set

    /** Import/locate result for the settings sheet. */
    var message by mutableStateOf("")
        private set

    /** "fade" or "cut"; applied by [Scenes.select]. */
    var transition by mutableStateOf("fade")
        private set
    var rotateOn by mutableStateOf(false)
        private set
    var rotateScenes by mutableStateOf<List<String>>(emptyList())
        private set
    var rotateSeconds by mutableStateOf(60)
        private set

    fun init(application: Application) {
        app = application
        scene = Prefs.string("overlayScene")
        pack = runCatching { Pack.fromJson(packFile.readText()) }.getOrNull()
        transition = Prefs.string("sceneTransition", "fade")
        rotateOn = Prefs.bool("sceneRotateOn")
        rotateSeconds = Prefs.int("sceneRotateSeconds", 60)
        rotateScenes = runCatching {
            JSONArray(Prefs.string("sceneRotateScenes", "[]")).let { a -> (0 until a.length()).map(a::getString) }
        }.getOrDefault(emptyList())
    }

    @JvmName("saveTransition") // the property's private setter already owns setTransition on the JVM
    fun setTransition(v: String) {
        transition = v
        Prefs.put("sceneTransition", v)
    }

    @JvmName("saveRotateOn") // the property's private setter already owns setRotateOn on the JVM
    fun setRotateOn(v: Boolean) {
        rotateOn = v
        Prefs.put("sceneRotateOn", v)
    }

    @JvmName("saveRotateScenes") // the property's private setter already owns setRotateScenes on the JVM
    fun setRotateScenes(v: List<String>) {
        rotateScenes = v
        Prefs.put("sceneRotateScenes", JSONArray(v).toString())
    }

    @JvmName("saveRotateSeconds") // the property's private setter already owns setRotateSeconds on the JVM
    fun setRotateSeconds(v: Int) {
        rotateSeconds = v
        Prefs.put("sceneRotateSeconds", v)
    }

    /** Raw switch with no transition or camera change; the UI goes through [Scenes.select]. */
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
        // Merge: in-app scenes (and earlier imports) the file doesn't mention are kept.
        val kept = scenes.filter { old -> parsed.scenes.none { it.name == old.name } }
        commit(parsed.copy(scenes = kept + parsed.scenes))
        if (scenes.none { it.name == scene }) select("")
        val n = parsed.scenes.sumOf { it.layers.size }
        applog("overlay", "imported ${parsed.scenes.size} scenes, $n layers")
        message =
            listOf("Imported ${parsed.scenes.size} scenes, $n layers.", parsed.skippedText(), missingText()).filter {
                it.isNotEmpty()
            }.joinToString(" ")
        Overlays.refresh()
    }

    private fun commit(p: Pack) {
        dir.mkdirs()
        packFile.writeText(p.toJson())
        pack = p
    }

    private fun mapScene(name: String, f: (Scene) -> Scene) {
        val p = pack ?: return
        commit(p.copy(scenes = p.scenes.map { if (it.name == name) f(it) else it }))
    }

    private fun taken(name: String) = scenes.any { it.name == name }

    /** Creates an empty scene ("Scene 1".. first free), plus a 1080p pack when there is none yet; returns its name. */
    fun addScene(): String {
        val p = pack ?: Pack(1920, 1080, emptyList(), emptyMap())
        val name = generateSequence(1) { it + 1 }.map { "Scene $it" }.first { n -> p.scenes.none { it.name == n } }
        commit(p.copy(scenes = p.scenes + Scene(name, emptyList())))
        return name
    }

    /** Copies as "<name> copy", "<name> copy 2"...; null when [name] doesn't exist. */
    fun duplicateScene(name: String): String? {
        val p = pack ?: return null
        val src = p.scenes.firstOrNull { it.name == name } ?: return null
        val copy = generateSequence(1) { it + 1 }.map { if (it == 1) "$name copy" else "$name copy $it" }.first { !taken(it) }
        commit(p.copy(scenes = p.scenes + src.copy(name = copy)))
        return copy
    }

    /** False when [new] is blank or already taken. */
    fun renameScene(old: String, new: String): Boolean {
        val n = new.trim()
        if (n.isEmpty() || !taken(old) || (n != old && taken(n))) return false
        mapScene(old) { it.copy(name = n) }
        if (scene == old) {
            scene = n
            Prefs.put("overlayScene", n)
        }
        setRotateScenes(rotateScenes.map { if (it == old) n else it })
        return true
    }

    fun deleteScene(name: String) {
        val p = pack ?: return
        commit(p.copy(scenes = p.scenes.filter { it.name != name }))
        setRotateScenes(rotateScenes - name)
        if (scene == name) select("")
    }

    /** Persists the layers; the stream is rebuilt only when this is the scene on air. */
    fun setLayers(scene: String, layers: List<Layer>) {
        mapScene(scene) { it.copy(layers = layers) }
        if (scene == this.scene) Overlays.refresh()
    }

    /** [camera] is "back"|"front"|"external"|"glasses"|"auto", or null to keep whatever is current. */
    fun setCamera(scene: String, camera: String?) = mapScene(scene) { it.copy(camera = camera) }

    /** Copies a picked image into app storage as img-uuid.ext (extension sniffed from the bytes); returns the name for data["file"]. */
    fun saveImage(uri: Uri): String? {
        val bytes = runCatching {
            app.contentResolver.openInputStream(uri)?.use { it.readNBytes(MAX_IMAGE_BYTES + 1) }
        }.getOrNull()
        if (bytes == null || bytes.size > MAX_IMAGE_BYTES) return null
        val ext = imageExt(bytes) ?: return null
        dir.mkdirs()
        val name = "img-${UUID.randomUUID()}.$ext"
        return name.takeIf { runCatching { File(dir, name).writeBytes(bytes) }.isSuccess }
    }

    private fun imageExt(b: ByteArray): String? {
        fun at(i: Int, s: String) = b.size >= i + s.length && s.indices.all { b[i + it].toInt() == s[it].code }
        return when {
            at(1, "PNG") -> "png"
            b.size > 2 && b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte() -> "jpg"
            at(0, "GIF8") -> "gif"
            at(0, "RIFF") && at(8, "WEBP") -> "webp"
            else -> null
        }
    }

    /** The widget's own size before layout scaling; null while its file is missing or its text is empty. */
    fun naturalSize(l: Layer): Pair<Float, Float>? {
        val d = l.data
        return when (l.type) {
            LayerType.Chat -> ChatStyle.from(d).natural
            LayerType.Alerts -> AlertStyle.from(d).natural
            LayerType.Events -> EventListStyle.from(d).natural
            LayerType.Qr -> QrStyle.from(d).natural
            LayerType.Browser -> (d["width"]?.toFloatOrNull() ?: 800f) to (d["height"]?.toFloatOrNull() ?: 600f)
            LayerType.Color -> (d["width"]?.toFloatOrNull() ?: 1920f) to (d["height"]?.toFloatOrNull() ?: 1080f)
            LayerType.Image -> local(d["file"].orEmpty())?.let(::imageSize)?.let { (w, h) ->
                (w - l.crop[0] - l.crop[2]).toFloat() to (h - l.crop[1] - l.crop[3]).toFloat()
            }
            LayerType.Media -> local(d["file"].orEmpty())?.let(::mediaSize)
            LayerType.Slideshow ->
                l.files.firstNotNullOfOrNull { local(it)?.let(::imageSize) }?.let { it.first.toFloat() to it.second.toFloat() }
            LayerType.Text -> textSize(l)
        }
    }

    private fun textSize(l: Layer): Pair<Float, Float>? {
        val t = TextStyle.from(l.data)
        val bmp = if (l.layout != null) inAppTextBitmap(t, 1f) else textBitmap(t.text, t.face, t.bold, t.size, t.color)
        return bmp?.let { it.width.toFloat() to it.height.toFloat() }
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

/** Video dimensions from the container metadata (no decoding), or null when unreadable. */
internal fun mediaSize(f: File): Pair<Float, Float>? {
    val mmr = MediaMetadataRetriever()
    return try {
        mmr.setDataSource(f.path)
        val w = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toFloatOrNull()
        val h = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toFloatOrNull()
        if (w == null || h == null) null else w to h
    } catch (e: RuntimeException) {
        null
    } finally {
        mmr.release()
    }
}
