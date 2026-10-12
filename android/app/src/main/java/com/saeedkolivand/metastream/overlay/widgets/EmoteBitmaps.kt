package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.util.LruCache
import coil3.ImageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private const val CACHE_BYTES = 8 * 1024 * 1024

/**
 * Emote images for the native chat bitmap, which can't wait on an async view like Compose does. [get] answers from the
 * cache or starts a load and returns null; [version] bumps when one lands so the widget re-renders once.
 */
internal object EmoteBitmaps {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val loader by lazy { ImageLoader(appContext) }
    private val cache = object : LruCache<String, Bitmap>(CACHE_BYTES) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    private val pending = ConcurrentHashMap.newKeySet<String>()
    private val failed = ConcurrentHashMap.newKeySet<String>() // ponytail: a failed URL is never retried until restart
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version

    fun get(url: String, px: Int): Bitmap? {
        val key = "$url@$px"
        cache.get(key)?.let { return it }
        if (key !in failed && pending.add(key)) load(key, url, px)
        return null
    }

    private fun load(key: String, url: String, px: Int) {
        scope.launch {
            // Wide emotes keep their aspect inside 3x the height; software bitmaps, since we draw into a plain Canvas.
            val bmp = runCatching {
                loader.execute(ImageRequest.Builder(appContext).data(url).size(px * 3, px).allowHardware(false).build()).image?.toBitmap()
            }.getOrNull()
            pending.remove(key)
            if (bmp == null) {
                failed.add(key)
            } else {
                cache.put(key, bmp)
                _version.update { it + 1 }
            }
        }
    }
}
