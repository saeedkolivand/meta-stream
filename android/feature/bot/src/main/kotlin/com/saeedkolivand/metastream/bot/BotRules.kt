package com.saeedkolivand.metastream.bot

import com.saeedkolivand.metastream.chat.Slash
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.Twitch
import org.json.JSONArray
import org.json.JSONObject

/** The shared bot list (Prefs "botNames", comma separated) and what a bot message means for the streamer (iOS BotList). */
object BotList {
    const val DEFAULT_NAMES = "nightbot,streamelements,streamlabs,moobot,fossabot,botrix,botrixoficial,kicklet,sery_bot,wizebot,soundalerts"
    const val DEFAULT_TRIGGERS = "won, winner"

    /** Names ending in "bot" always count, whatever the list says. */
    fun isBot(name: String, list: String = Prefs.string("botNames", DEFAULT_NAMES)): Boolean {
        val u = name.lowercase()
        return u.endsWith("bot") || list.lowercase().split(',').any { it.trim() == u }
    }

    private fun words(s: String) = s.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString(" ")

    /** A bot message holding a trigger word (case-insensitive, whole word): worth the streamer's attention while live. */
    fun isAnnouncement(
        user: String,
        text: String,
        botList: String = Prefs.string("botNames", DEFAULT_NAMES),
        triggers: String = Prefs.string("botTriggers", DEFAULT_TRIGGERS)
    ): Boolean {
        if (!isBot(user, botList)) return false
        val body = " ${words(text)} "
        return triggers.split(',').map(::words).any { it.isNotEmpty() && " $it " in body }
    }

    /** Whether read-aloud speaks this message: non-bots always; bots per "botReadMode" (off | triggers | all). */
    fun reads(user: String, text: String): Boolean = !isBot(user) ||
        when (Prefs.string("botReadMode", "triggers")) {
            "all" -> true
            "off" -> false
            else -> isAnnouncement(user, text)
        }
}

/** The app bot's pure decisions (iOS AppBot statics), times in ms. */
object BotRules {
    /** Same command on the same platform: once per 30 s, unless a mod or the broadcaster typed it. */
    fun cooldownOK(last: Long?, now: Long, privileged: Boolean) = privileged || last == null || now - last >= 30_000

    /** Interval passed (never under 5 min), 5 viewer messages since its last post, and 5 min since any timer posted there. */
    fun timerDue(since: Long, minutes: Int, msgs: Int, lastAny: Long?, now: Long) =
        now - since >= maxOf(minutes, 5) * 60_000L && msgs >= 5 && (lastAny == null || now - lastAny >= 300_000)

    /** A flapping link posts its weak notice at most once per 2 min. */
    fun brbNoticeDue(last: Long?, now: Long) = last == null || now - last >= 120_000

    val donateAliases = listOf("!tip", "!support", "!donation")

    fun switchKey(cmd: String) = "botCmd" + if (cmd in donateAliases) "Donate" else cmd.drop(1).replaceFirstChar(Char::uppercase)

    fun fill(template: String, user: String, count: Int) = template.replace("{user}", user).replace("{count}", count.toString())
}

/** A saved chat command ("!giveaway start") sent as the streamer (iOS BotCommand); Prefs "botCommands" as JSON. */
data class BotCommand(val text: String, val destination: String = "all") { // destination: kick | twitch | all
    companion object {
        private val seed = listOf(BotCommand("/clear"), BotCommand("!giveaway start"), BotCommand("!giveaway end"), BotCommand("!socials"))

        fun stored(): List<BotCommand> {
            val raw = Prefs.string("botCommands").ifEmpty { return seed }
            return runCatching {
                JSONArray(raw).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
                    .map { BotCommand(it.getString("text"), it.optString("destination", "all")) }
            }.getOrDefault(seed)
        }

        fun save(list: List<BotCommand>) = Prefs.put(
            "botCommands",
            JSONArray(
                list.map {
                    JSONObject().put("text", it.text).put("destination", it.destination)
                }
            ).toString()
        )
    }
}

/** A message the app bot repeats while live (iOS AppTimer); Prefs "botTimers" as JSON. */
data class BotTimer(val text: String, val minutes: Int = 15) {
    companion object {
        fun stored(): List<BotTimer> = runCatching {
            JSONArray(Prefs.string("botTimers", "[]")).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
                .map { BotTimer(it.getString("text"), it.optInt("minutes", 15)) }
        }.getOrDefault(emptyList())

        fun save(list: List<BotTimer>) =
            Prefs.put("botTimers", JSONArray(list.map { JSONObject().put("text", it.text).put("minutes", it.minutes) }).toString())
    }
}

/**
 * Posted as the streamer's own account: bots like BotRix only obey the broadcaster and mods. A "/command" is never posted:
 * it runs like a typed slash command on each platform it targets. Returns that outcome ("" otherwise).
 */
suspend fun BotCommand.send(): String {
    applog("chat", "command $text -> $destination")
    val targets = listOf("kick", "twitch").filter { destination == "all" || destination == it }
    Slash.parse(text)?.let { (name, args) ->
        return targets.filter {
            it != "twitch" || Twitch.connected
        }.map { Slash.run(it, name, args) }.filter { it.isNotEmpty() }.joinToString(" · ")
    }
    targets.forEach { Accounts.send(it, text) }
    return ""
}
