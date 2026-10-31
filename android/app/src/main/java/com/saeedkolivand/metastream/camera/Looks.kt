package com.saeedkolivand.metastream.camera

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.pedro.library.view.GlInterface
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import java.io.File

private const val MAX_CUBE_BYTES = 16 * 1024 * 1024 // a 64-point cube is ~8 MB of text

/**
 * The live source's [Look] in the GL chain (iOS setLookEffect). Like the privacy blur, the filter outlives Overlays'
 * rebuilds and is only added or removed when the look turns non-neutral or neutral; slider moves just update it.
 */
object Looks {
    private lateinit var folder: File
    private var filter: LookFilter? = null
    private var owner: GlInterface? = null
    private val cubes = HashMap<String, Cube?>() // parsed once per file name

    fun init(context: Context) {
        folder = File(context.filesDir, "luts").apply { mkdirs() }
    }

    /** Which source's look is live: the phone camera's facing, or the USB camera. */
    fun key(): String = when {
        Engine.source == Source.Usb -> "external"
        Engine.source == Source.Glasses -> "glasses"
        Engine.source == Source.Screen -> "screen"
        Cam.facingBack() -> "back"
        else -> "front"
    }

    val inChain get() = filter != null

    /** Main thread. Makes [g]'s chain match the live source's look; the filter goes first, ahead of the overlays. */
    fun install(g: GlInterface) {
        if (owner !== g) forget()
        val look = if (Engine.source == Source.Glasses) Look() else Look.load(key())
        val f = filter
        if (!look.neutral) {
            val lut = look.lut?.let { cubes.getOrPut(it) { load(it) } }
            val live = f ?: LookFilter().also { filter = it }
            if (f == null) {
                owner = g
                g.addFilter(0, live)
            }
            live.set(look, lut)
        } else if (f != null) {
            g.removeFilter(f)
            forget()
        }
    }

    /** The GL pipeline was replaced, so the old filter is already gone. */
    fun forget() {
        filter = null
        owner = null
    }

    private fun load(name: String): Cube? = try {
        parseCube(File(folder, name).readText())
    } catch (e: Exception) {
        applog("stream", "LUT $name unusable: ${e.message}")
        null
    }

    fun files(): List<String> = folder.list()?.filter { it.lowercase().endsWith(".cube") }?.sorted().orEmpty()

    fun delete(name: String) {
        File(folder, name).delete()
        cubes.remove(name)
    }

    /** Validates a picked .cube and copies it in; the stored name, or the error to show. */
    fun import(context: Context, uri: Uri): Result<String> = runCatching {
        val display = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "look.cube"
        val bytes = context.contentResolver.openInputStream(uri)!!.use { it.readNBytes(MAX_CUBE_BYTES + 1) }
        if (bytes.size > MAX_CUBE_BYTES) throw CubeError("That file is too big for a LUT")
        parseCube(String(bytes))
        val name = display.replace(Regex("[^\\w.\\- ]"), "_").let { if (it.lowercase().endsWith(".cube")) it else "$it.cube" }
        File(folder, name).writeBytes(bytes)
        cubes.remove(name)
        name
    }.onFailure { applog("stream", "LUT import failed: ${it.message}") }
}
