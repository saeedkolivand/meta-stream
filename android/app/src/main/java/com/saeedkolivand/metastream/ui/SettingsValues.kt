package com.saeedkolivand.metastream.ui

import com.saeedkolivand.metastream.bot.BotCommand
import com.saeedkolivand.metastream.bot.TwitchBot
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.AppSettings
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.goal.DonationHub
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.Site
import com.saeedkolivand.metastream.overlay.ColorTheme
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Restream
import com.saeedkolivand.metastream.platforms.Spotify
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import com.saeedkolivand.metastream.privacy.Privacy
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Mics
import com.saeedkolivand.metastream.streaming.Source

/** The ingest platforms (iOS IngestSettingsView): Prefs "platform" -> name and preset URL (null = paste your own). */
internal val Platforms = listOf(
    Triple("kick", "Kick", "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"),
    Triple("twitch", "Twitch", "rtmps://live.twitch.tv:443/app/"),
    Triple("youtube", "YouTube", "rtmps://a.rtmps.youtube.com:443/live2"),
    Triple("restream", "Restream", "rtmp://live.restream.io/live"),
    Triple("instagram", "Instagram", null),
    Triple("tiktok", "TikTok", null),
    Triple("custom", "Custom", null)
)

internal fun platformId() = Prefs.string("platform", "custom")

/**
 * The grey summaries on the settings rows (iOS SettingsValues). Each reads the same state as the screen it summarises;
 * empty means "nothing worth saying".
 */
internal object SettingsValues {
    private fun onOff(key: String) = if (Prefs.bool(key, false)) "On" else "Off"

    private val accounts get() = listOf(Kick, Twitch, YouTube, Restream)

    fun accounts() = accounts.count { it.connected }.let { if (it == 0) "" else "$it connected" }

    /** "Kick · RTMPS": the platform and the protocol its URL uses. */
    fun ingest(): String {
        val name = Platforms.firstOrNull { it.first == platformId() }?.second.orEmpty()
        val url = Engine.url.lowercase()
        val proto = listOf("srtla://" to "SRTLA", "srt://" to "SRT", "rtmps://" to "RTMPS", "rtmp://" to "RTMP").firstOrNull {
            url.startsWith(it.first)
        }?.second
        return listOfNotNull(name.ifEmpty { null }, proto).joinToString(" · ")
    }

    fun quality() = AppSettings.ingest.let { "${it.height}p · ${it.fps} fps" }

    fun camera() = if (Engine.source ==
        Source.Usb
    ) {
        "USB camera"
    } else if (com.saeedkolivand.metastream.camera.Cam.facingBack()) {
        "Back"
    } else {
        "Front"
    }

    fun glasses() = onOff("glassesEnabled")

    /** The picked microphone's name; "Default" when none is picked, empty when it isn't plugged in. */
    fun audio(): String {
        if (Mics.selected.isEmpty()) return "Default"
        return Mics.available(Engine.appContext).firstOrNull { Mics.key(it) == Mics.selected }?.productName?.toString().orEmpty()
    }

    fun privacy() = if (Privacy.on) "On" else "Off"

    fun scenes() = OverlayStore.scenes.size.let { if (it == 0) "" else "$it scene" + if (it == 1) "" else "s" }

    fun theme() = ColorTheme.current.title

    fun chat() = when {
        ChatFeed.kickSlug.isNotBlank() -> "Kick · ${ChatFeed.kickSlug}"
        ChatFeed.twitchChannel.isNotBlank() -> "Twitch · ${ChatFeed.twitchChannel}"
        else -> ""
    }

    fun commands() = BotCommand.stored().size.let { if (it == 0) "" else "$it" }

    fun appBot() = listOf("botKick" to "Kick", "botTwitch" to "Twitch").filter { Prefs.bool(it.first, false) }.map { it.second }
        .ifEmpty { listOf("Off") }.joinToString(", ")

    /** "€120 / €500", in the goal's own currency. */
    fun goal() = GoalStore.config.currency.let { Money(GoalStore.total, it).display + " / " + Money(GoalStore.config.target, it).display }

    fun sources() = Site.entries.count { DonationHub.key(it).isNotEmpty() }.let { if (it == 0) "" else "$it set up" }

    fun telegram() = onOff("telegramOn")

    fun spotify() = if (Spotify.connected) "Connected" else ""

    fun remote() = onOff("obsServerOn")

    /** The readiness card's chips: destination, quality, microphone, camera. */
    fun chips() = listOf(ingest(), quality(), audio().let { if (it == "Default") "Default mic" else it.ifEmpty { "Microphone" } }, camera())
        .filter { it.isNotEmpty() }

    /** Real problems in the current settings and the page id that fixes each (iOS SettingsReadiness). */
    fun issues(): List<Pair<String, String>> {
        val out = ArrayList<Pair<String, String>>()
        val account = mapOf("kick" to Kick, "twitch" to Twitch, "youtube" to YouTube, "restream" to Restream)[platformId()]
        if (account != null && !account.connected) out += "accounts" to "${account.label} is not connected"
        if (account == null && Engine.key.isBlank()) out += "ingest" to "No stream key for the destination"
        Site.entries.forEach { site ->
            val status = DonationHub.status[site].orEmpty()
            if (DonationHub.key(site).isNotEmpty() && (status.startsWith("Key rejected") || status.startsWith("Can't reach"))) {
                out += "sources" to "${site.title}: ${status.substringBefore(" ·")}"
            }
        }
        if (Prefs.bool("telegramOn", false) &&
            Prefs.string("telegramChannel").isBlank()
        ) {
            out += "telegram" to "Telegram live post has no channel"
        }
        if (Prefs.bool("botTwitch", false)) {
            if (!Twitch.connected) {
                out += "accounts" to "App bot is on for Twitch but your Twitch account isn't connected"
            } else if (TwitchBot.name.isEmpty()) {
                out += "accounts" to "App bot is on for Twitch but has no bot account"
            }
        }
        if (Prefs.bool("obsServerOn", false) && Prefs.string("obsPassword").length < 8) {
            out += "remote" to "Remote control password is shorter than 8 characters"
        }
        return out
    }
}
