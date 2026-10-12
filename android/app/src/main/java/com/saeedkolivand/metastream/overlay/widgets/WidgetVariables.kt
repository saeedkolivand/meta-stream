package com.saeedkolivand.metastream.overlay

import android.os.BatteryManager
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Health
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** {tokens} for on-stream text, resolved from live app state by the live text widget once per second. */
internal object WidgetVariables {
    /** For the editor's insert menu, in menu order. */
    val tokens: List<Pair<String, String>> = listOf(
        "{time}" to "Time",
        "{date}" to "Date",
        "{uptime}" to "Live time",
        "{viewers}" to "Viewers",
        "{bitrate}" to "Bitrate",
        "{battery}" to "Battery",
        "{speed}" to "Speed",
        "{city}" to "City",
        "{follower}" to "Latest follower",
        "{sub}" to "Latest sub"
    )

    fun needsLocation(template: String) = "{speed}" in template || "{city}" in template

    /** Only tokens present in the template are evaluated. */
    fun resolve(template: String): String {
        if ('{' !in template) return template
        var out = template
        for ((token, _) in tokens) if (token in out) out = out.replace(token, value(token))
        return out
    }

    private fun value(token: String): String = when (token) {
        "{time}" -> DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
        "{date}" -> DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date())
        "{uptime}" -> uptime(Engine.liveSince)
        "{viewers}" -> (Kick.viewers + Twitch.viewers + YouTube.viewers).toString()
        "{bitrate}" -> "${Health.bitrateKbps} kbps"
        "{battery}" -> battery()
        "{speed}" -> WidgetLocation.speedText
        "{city}" -> WidgetLocation.cityText
        "{follower}" -> ChatFeed.lastFollower
        "{sub}" -> ChatFeed.lastSubscriber
        else -> token
    }

    // Health.battery only ticks while live; the editor preview wants a number too, so fall back to the system value.
    private fun battery(): String {
        val pct = Health.battery
            ?: appContext.getSystemService(BatteryManager::class.java).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct in 0..100) "$pct%" else "--"
    }

    private fun uptime(since: Long?): String {
        val s = if (since == null) 0 else ((System.currentTimeMillis() - since) / 1000).coerceAtLeast(0)
        return if (s >= 3600) {
            String.format(Locale.US, "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
        } else {
            String.format(Locale.US, "%02d:%02d", s / 60, s % 60)
        }
    }
}
