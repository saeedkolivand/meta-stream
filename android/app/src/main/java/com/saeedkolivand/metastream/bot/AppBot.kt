package com.saeedkolivand.metastream.bot

import android.os.BatteryManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.goal.DonatePage
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.overlay.SceneRoles
import com.saeedkolivand.metastream.overlay.WidgetLocation
import com.saeedkolivand.metastream.overlay.WidgetWeather
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Spotify
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.speech.SpeechSettings
import com.saeedkolivand.metastream.speech.isBlocked
import com.saeedkolivand.metastream.speech.offensive
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Health
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * The app's own chat account on Kick and Twitch (iOS AppBot): scene notices, viewer commands, timers and thank-yous.
 * Never posts as the streamer. One paced queue per platform, and everything only while live (or in test mode).
 * ponytail: !donate and !song join the command list with the goal store and Spotify; settings are plain Prefs keys.
 */
object AppBot {
    var status by mutableStateOf("")

    val defaults = mapOf(
        "botTplBrbOn" to "Connection's weak, back in a moment", "botTplBrbOff" to "We're back!",
        "botTplStartingOn" to "Starting soon!", "botTplStartingOff" to "We're live, welcome in!",
        "botTplEndingOn" to "Thanks for watching!",
        "botTplFollow" to "{user}, thanks for the follow!", "botTplSub" to "{user}, thanks for subscribing!",
        "botTplGift" to "{user}, thanks for the {count} gifted subs!", "botTplRaid" to "{user}, thanks for the raid with {count} viewers!",
        "botTplDonate" to "{title}: {total} / {target} ({percent}%) · {url}"
    )
    val commands = listOf("!location", "!speed", "!distance", "!weather", "!battery", "!uptime", "!goal", "!donate", "!song", "!commands") +
        BotRules.donateAliases

    private val queues = HashMap<String, Channel<Pair<String, String>>>() // origin -> (text, replyTo), drained 1 per 1.5 s

    // Our last texts (chat echoes them back, they are not viewers) and the bot accounts' "origin|name" learned from those
    // echoes. Concurrent: read-aloud asks isOwn from the chat socket's thread.
    private val sent = java.util.concurrent.ConcurrentLinkedDeque<String>()
    private val ownNames: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()
    private val answered = HashMap<String, Long>()
    private val msgs = HashMap<String, Int>()
    private val marks = HashMap<String, Pair<Long, Int>>()
    private val lastTimer = HashMap<String, Long>()
    private var holdingGps = false
    private var holdingSpotify = false
    private var brbAt: Long? = null
    private var brbOpen = false

    fun flag(key: String, fallback: Boolean = true) = Prefs.bool(key, fallback)

    fun tpl(key: String) = Prefs.string(key, defaults[key].orEmpty())

    /** Live, or test mode: answers, notices and thank-yous work offline too. Timers stay live-only. */
    private val active get() = Engine.live || flag("botTestMode", false)

    fun platformOn(origin: String) = when (origin) {
        "kick" -> flag("botKick", false) && Kick.connected
        "twitch" -> flag("botTwitch", false) && Twitch.userId.isNotEmpty() && TwitchBot.connected
        else -> false
    }

    /** Main thread: the 1 s tick and the chat hook. */
    fun init() {
        Accounts.scope.launch {
            while (true) {
                tick()
                delay(1000)
            }
        }
    }

    /** Queued, delayed, never dropped: Twitch allows 20 messages per 30 s to a non-mod. [replyTo] threads it under the asker. */
    private fun say(origin: String, text: String, replyTo: String = "") {
        if (!active || !platformOn(origin) || text.isEmpty()) return
        queues.getOrPut(origin) {
            Channel<Pair<String, String>>(Channel.UNLIMITED).also { ch ->
                Accounts.scope.launch {
                    for ((t, r) in ch) {
                        post(origin, t, r)
                        delay(1500)
                    }
                }
            }
        }.trySend(text.take(500) to replyTo) // Kick's limit
    }

    private suspend fun post(origin: String, text: String, replyTo: String) {
        sent.addLast(text)
        while (sent.size > 20) sent.pollFirst()
        try {
            if (origin == "kick") {
                // type "bot" posts as the app's bot account of the token owner's channel; never fall back to "user".
                val body = JSONObject().put("content", text).put("type", "bot")
                if (replyTo.isNotEmpty()) body.put("reply_to_message_id", replyTo)
                Kick.api.call("POST", "/public/v1/chat", body = body)
            } else {
                val body = JSONObject().put("broadcaster_id", Twitch.userId).put("message", text).put("sender_id", TwitchBot.id)
                if (replyTo.isNotEmpty()) body.put("reply_parent_message_id", replyTo)
                TwitchBot.api.call("POST", "/chat/messages", body = body)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            applog("chat", "app bot $origin send failed: ${e.message}")
            status = "${if (origin == "kick") "Kick" else "Twitch"}: ${e.message}"
            if (replyTo.isNotEmpty()) post(origin, text, "") // the question is gone: answer without the reply
        }
    }

    /** From SceneRoles: BRB / Starting on and off, Ending on. An empty template posts nothing; a flapping BRB posts once per 2 min. */
    fun role(role: String, on: Boolean) {
        if (!flag("botNotices")) return
        if (role == SceneRoles.BRB) {
            val now = System.currentTimeMillis()
            if (on) {
                if (!BotRules.brbNoticeDue(brbAt, now)) return
                brbAt = now
                brbOpen = true
            } else {
                if (!brbOpen) return
                brbOpen = false
            }
        }
        val text = tpl("botTpl" + role.replaceFirstChar(Char::uppercase) + if (on) "On" else "Off")
        listOf("kick", "twitch").forEach { say(it, text) }
    }

    /** From GoalStore.onReached. */
    fun goalReached(title: String) {
        if (flag("botNotices")) listOf("kick", "twitch").forEach { say(it, "Goal reached: $title!") }
    }

    /** Every chat event: viewer commands, the timers' message count and thank-yous. */
    fun handle(e: ChatEvent) {
        if (e.offensive || !active || (e.platform != "kick" && e.platform != "twitch")) return
        when (e.kind) {
            Kind.Message -> message(e)
            Kind.Follow -> thank(e, "botTplFollow")
            Kind.Subscribe -> thank(e, if (e.count > 0) "botTplGift" else "botTplSub")
            Kind.Raid -> thank(e, "botTplRaid")
            else -> Unit
        }
    }

    private fun thank(e: ChatEvent, key: String) {
        if (!flag("botThanks") || isBlocked(e.user, SpeechSettings.blocked)) return
        say(e.platform, BotRules.fill(tpl(key), BotRules.safeName(e.user), e.count))
    }

    /** One of the app bot's own lines; Kick doesn't name the bot account, so it's learned from the first echo. */
    fun isOwn(e: ChatEvent): Boolean {
        val key = e.platform + "|" + e.user.lowercase()
        if (key in ownNames) return true
        if (e.platform == "twitch" && TwitchBot.name.isNotEmpty() && e.user.equals(TwitchBot.name, true)) return true
        if (e.text !in sent) return false
        val me = if (e.platform == "kick") Kick.user else Twitch.user
        if (!e.user.equals(me, true)) ownNames += key
        return true
    }

    private fun message(e: ChatEvent) {
        if (isOwn(e)) return
        if (!BotList.isBot(e.user)) msgs[e.platform] = (msgs[e.platform] ?: 0) + 1
        val cmd = e.text.trim().split(Regex("\\s+")).first().lowercase()
        if (cmd !in commands) return
        if (!platformOn(e.platform) || !flag(BotRules.switchKey(cmd))) return applog("bot", "$cmd on ${e.platform} ignored: off there")
        val now = System.currentTimeMillis()
        val privileged = e.badges.any { it == "broadcaster" || it == "moderator" }
        // Offline (test mode) only the streamer and mods get answers: !location to anyone off-stream would say where you are.
        if (!Engine.live && !privileged) return
        val key = e.platform + "|" + cmd
        if (!BotRules.cooldownOK(answered[key], now, privileged)) return
        answered[key] = now
        val name = (if (e.platform == "kick") Kick.user else Twitch.user).ifEmpty { "The streamer" }
        answer(cmd, name)?.let { say(e.platform, it, e.msgId) } ?: applog("bot", "$cmd: value not known yet, staying silent")
    }

    private fun battery() = Health.battery ?: Accounts.app.getSystemService(BatteryManager::class.java)
        .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).takeIf { it in 0..100 }

    /** null (stay silent) when the value isn't known yet; an answer that says why beats silence, which looks broken. */
    private fun answer(cmd: String, name: String): String? = when (cmd) {
        "!location" -> if (flag("botHideLocation", false)) {
            "Location is private right now"
        } else {
            WidgetLocation.cityText.takeIf { it != "--" }?.let { "$name is in $it" } ?: "$name's location isn't known yet"
        }
        "!speed" -> WidgetLocation.speedText.takeIf { it != "--" }?.let { "$name is going $it" }
            ?: "Speed isn't available right now (no GPS)"
        "!distance" -> "$name has travelled ${WidgetLocation.distanceText(Engine.liveSince)} today"
        "!weather" -> WidgetWeather.plainText.takeIf { it != "--" }?.let { "It's $it where $name is" }
            ?: "The weather there isn't known yet"
        "!battery" -> battery()?.let { "$name's phone is at $it%" }
        "!goal" -> GoalStore.config.let { c ->
            "${GoalStore.money(GoalStore.total)} of ${GoalStore.money(c.target)} for ${c.title} (${(GoalStore.progress * 100).toInt()}%)"
        }
        "!donate", "!tip", "!support", "!donation" -> GoalStore.config.let { c ->
            if (c.target.signum() <= 0) {
                "Support the stream: ${DonatePage.chatURL}"
            } else {
                tpl("botTplDonate").replace("{title}", c.title).replace("{total}", GoalStore.money(GoalStore.total))
                    .replace("{target}", GoalStore.money(c.target)).replace("{percent}", "${(GoalStore.progress * 100).toInt()}")
                    .replace("{url}", DonatePage.chatURL)
            }
        }
        "!song" -> when (val song = Spotify.track) {
            null -> if (Spotify.connected) "Nothing's playing right now" else "Spotify isn't connected"
            else -> (if (song.artist.isEmpty()) song.title else "${song.artist} - ${song.title}") +
                if (song.url.isEmpty()) "" else " ${song.url}"
        }
        "!uptime" -> Engine.liveSince?.let {
            val m = maxOf(0L, System.currentTimeMillis() - it) / 60_000
            "$name has been live for ${if (m >= 60) "${m / 60} h " else ""}${m % 60} min"
        } ?: "$name isn't live right now"
        else -> commands.filter {
            it != "!commands" && it !in BotRules.donateAliases && flag(BotRules.switchKey(it))
        }.takeIf { it.isNotEmpty() }?.let {
            "Commands: " +
                it.joinToString(" ")
        }
    }

    /** Keeps the GPS on while location commands are possible, and runs the timers. */
    private fun tick() {
        val wantGps = active &&
            (platformOn("kick") || platformOn("twitch")) &&
            listOf("botCmdLocation", "botCmdSpeed", "botCmdDistance", "botCmdWeather").any { flag(it) }
        if (wantGps != holdingGps) {
            holdingGps = wantGps
            if (wantGps) WidgetLocation.retain() else WidgetLocation.release()
        }
        // Polls Spotify while !song could be asked, so the answer is the song playing now.
        val wantSpotify = active && (platformOn("kick") || platformOn("twitch")) && flag("botCmdSong") && Spotify.connected
        if (wantSpotify != holdingSpotify) {
            holdingSpotify = wantSpotify
            if (wantSpotify) Spotify.retain() else Spotify.release()
        }
        if (wantGps && flag("botCmdWeather")) WidgetWeather.text // reading it is what turns the fetch on
        if (!Engine.live) {
            msgs.clear()
            marks.clear()
            lastTimer.clear()
            brbAt = null
            brbOpen = false
            return
        }
        if (!flag("botTimersOn", false) || SceneRoles.active == SceneRoles.BRB) return
        val now = System.currentTimeMillis()
        for (t in BotTimer.stored().filter { it.text.isNotEmpty() }) {
            for (o in listOf("kick", "twitch").filter(::platformOn)) {
                val k = "${t.text}|$o"
                val m = msgs[o] ?: 0
                val mark = marks[k] ?: run {
                    marks[k] = now to m
                    null
                } ?: continue
                if (BotRules.timerDue(mark.first, t.minutes, m - mark.second, lastTimer[o], now)) {
                    marks[k] = now to m
                    lastTimer[o] = now
                    say(o, t.text)
                }
            }
        }
    }
}
