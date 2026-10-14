package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.util.LruCache
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CACHE_BYTES = 8 * 1024 * 1024

/**
 * Emote images for the native chat bitmap, which can't wait on an async view like Compose does. [get] answers from the
 * cache or starts a load and returns null; [version] bumps when one lands so the widget re-renders once.
 */
internal object EmoteBitmaps {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val cache = object : LruCache<String, Emote>(CACHE_BYTES) {
        override fun sizeOf(key: String, value: Emote) = value.bytes
    }
    private val pending = ConcurrentHashMap.newKeySet<String>()
    private val failed = ConcurrentHashMap.newKeySet<String>() // ponytail: a failed URL is never retried until restart
    private val animatedUrls = ConcurrentHashMap.newKeySet<String>()
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version

    /** True once [url] has loaded and turned out to have several frames. */
    fun isAnimated(url: String) = url in animatedUrls

    /** The frame of [url] showing [t] ms into its loop (a still ignores t); null while it loads. */
    fun get(url: String, px: Int, t: Long = 0): Bitmap? {
        val key = "$url@$px"
        cache.get(key)?.let { return it.at(t) }
        if (key !in failed && pending.add(key)) load(key, url, px)
        return null
    }

    private fun load(key: String, url: String, px: Int) {
        scope.launch {
            // Decoded off-thread to software bitmaps (we draw into a plain Canvas); wide emotes keep their aspect inside 3x the height.
            val emote = withContext(Dispatchers.IO) {
                runCatching { decodeEmote(URL(url).openStream().use { it.readNBytes(MAX_EMOTE_BYTES + 1) }, px) }.getOrNull()
            }
            pending.remove(key)
            if (emote == null) {
                failed.add(key)
            } else {
                if (emote.animated) animatedUrls.add(url)
                cache.put(key, emote)
                _version.update { it + 1 }
            }
        }
    }
}
