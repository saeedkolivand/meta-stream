package com.saeedkolivand.metastream.overlay

import android.location.Location
import com.saeedkolivand.metastream.core.network.http
import com.saeedkolivand.metastream.overlay.widgets.goal.moved
import com.saeedkolivand.metastream.overlay.widgets.text.InlineIcons
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

/** Inline icon (see [InlineIcons]) for a WMO weather code (Open-Meteo `weather_code`); same names as iOS. */
fun weatherSymbol(code: Int): String = when (code) {
    0 -> "sun.max.fill"
    1, 2 -> "cloud.sun.fill"
    3 -> "cloud.fill"
    45, 48 -> "cloud.fog.fill"
    in 51..67 -> "cloud.rain.fill"
    in 71..77 -> "snowflake"
    80, 81, 82 -> "cloud.sun.rain.fill"
    85, 86 -> "cloud.snow.fill"
    in 95..99 -> "cloud.bolt.rain.fill"
    else -> "thermometer.medium"
}

/** Plain words for a WMO weather code, for chat replies. */
fun weatherWords(code: Int): String = when (code) {
    0 -> "clear"
    1, 2 -> "partly cloudy"
    3 -> "overcast"
    45, 48 -> "foggy"
    in 51..67 -> "rainy"
    in 71..77 -> "snowy"
    80, 81, 82 -> "showers"
    85, 86 -> "snow showers"
    in 95..99 -> "thunderstorms"
    else -> "unsettled"
}

/**
 * Current weather for the {weather} token from Open-Meteo (no key), refreshed from [WidgetLocation] fixes: every 15 min or
 * after moving 5 km. Coordinates are rounded to ~1 km before leaving the phone. Failures keep the last text.
 */
object WidgetWeather {
    @Volatile
    private var value = "--"

    @Volatile
    private var plain = "--"

    @Volatile
    private var wanted = false

    /** Reading it is what turns fetching on, so location never goes to Open-Meteo unless a widget shows {weather}. */
    val text: String
        get() {
            wanted = true
            return value
        }

    /** "17°, partly cloudy": [text] without the icon, for chat replies. */
    val plainText: String
        get() {
            wanted = true
            return plain
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
                    value = result.first
                    plain = result.second
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

    private fun fetch(lat: Double, lon: Double): Pair<String, String> {
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
            val code = cur.getInt("weather_code")
            val t = "${cur.getDouble("temperature_2m").roundToInt()}°"
            return "{i:${weatherSymbol(code)}} $t" to "$t, ${weatherWords(code)}"
        }
    }
}
