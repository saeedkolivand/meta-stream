package com.saeedkolivand.metastream.overlay

import android.location.Location
import com.saeedkolivand.metastream.platforms.http
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.Request
import org.json.JSONObject

private const val REFRESH_MS = 15 * 60_000L
private const val RETRY_MS = 2 * 60_000L
private const val MOVED_METERS = 5000f

/** Emoji for a WMO weather code (Open-Meteo `weather_code`). */
internal fun weatherEmoji(code: Int): String = when (code) {
    0 -> "☀️"
    1, 2 -> "🌤️"
    3 -> "☁️"
    45, 48 -> "🌫️"
    in 51..67 -> "🌧️"
    in 71..77 -> "❄️"
    80, 81, 82 -> "🌦️"
    85, 86 -> "🌨️"
    in 95..99 -> "⛈️"
    else -> "🌡️"
}

/**
 * Current weather for the {weather} token from Open-Meteo (no key), refreshed from [WidgetLocation] fixes: every 15 min or
 * after moving 5 km. Coordinates are rounded to ~1 km before leaving the phone. Failures keep the last text.
 */
internal object WidgetWeather {
    @Volatile
    private var value = "--"

    @Volatile
    private var wanted = false

    /** Reading it is what turns fetching on, so location never goes to Open-Meteo unless a widget shows {weather}. */
    val text: String
        get() {
            wanted = true
            return value
        }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var busy = false
    private var okAt = 0L
    private var failedAt = 0L
    private var fetched: Location? = null

    /** Called for every fix; decides whether a fetch is due. All state is guarded by the object lock. */
    fun update(lat: Double, lon: Double) {
        val now = System.currentTimeMillis()
        synchronized(this) {
            if (!wanted || busy || (failedAt != 0L && now - failedAt < RETRY_MS)) return
            val at = fetched
            val moved = at != null && distance(at.latitude, at.longitude, lat, lon) > MOVED_METERS
            if (at != null && !moved && now - okAt < REFRESH_MS) return
            busy = true
        }
        scope.launch {
            val result = runCatching { fetch(lat, lon) }.getOrNull()
            synchronized(this@WidgetWeather) {
                if (result != null) {
                    value = result
                    okAt = System.currentTimeMillis()
                    failedAt = 0L
                    fetched = Location("").apply {
                        latitude = lat
                        longitude = lon
                    }
                } else {
                    failedAt = System.currentTimeMillis()
                }
                busy = false
            }
        }
    }

    private fun distance(aLat: Double, aLon: Double, bLat: Double, bLon: Double) =
        FloatArray(1).also { Location.distanceBetween(aLat, aLon, bLat, bLon, it) }[0]

    private fun fetch(lat: Double, lon: Double): String {
        val unit = if (Locale.getDefault().country in IMPERIAL) "fahrenheit" else "celsius"
        val url = String.format(
            Locale.US,
            "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f&current=temperature_2m,weather_code&temperature_unit=%s",
            lat,
            lon,
            unit
        )
        http.newCall(Request.Builder().url(url).build()).execute().use { r ->
            val cur = JSONObject(r.body?.string().orEmpty()).getJSONObject("current")
            return "${weatherEmoji(cur.getInt("weather_code"))} ${cur.getDouble("temperature_2m").roundToInt()}°"
        }
    }
}
