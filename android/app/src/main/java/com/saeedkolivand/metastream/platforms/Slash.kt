package com.saeedkolivand.metastream.platforms

import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.Kind
import java.util.UUID
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

/**
 * Slash commands typed in the chat input (iOS SlashCommand + SlashRunner): carried out through the platform's own API,
 * never posted as a message; [run] returns the one-line note shown under the compose bar.
 * ponytail: no hidden kick.com page (adr/0005) on Android yet, so Kick gets only what its public API offers; /clear there
 * deletes the recent messages one by one.
 */
object Slash {
    fun parse(text: String): Pair<String, List<String>>? {
        if (!text.startsWith("/")) return null
        val parts = text.drop(1).split(Regex("\\s+")).filter { it.isNotEmpty() }
        return parts.firstOrNull()?.let { it.lowercase() to parts.drop(1) }
    }

    /** "600" -> 600, "10m" -> 600, "1h", "1d", "30s"; null when it isn't a duration (the word is part of a reason). */
    fun seconds(s: String): Int? {
        val mult = mapOf('s' to 1, 'm' to 60, 'h' to 3600, 'd' to 86400)[s.lowercase().lastOrNull()]
        val v = (if (mult != null) s.dropLast(1) else s).toIntOrNull()?.takeIf { it in 1..1_000_000 } ?: return null
        return v * (mult ?: 1)
    }

    fun pretty(s: Int) = when {
        s % 86400 == 0 -> "${s / 86400} d"
        s % 3600 == 0 -> "${s / 3600} h"
        s % 60 == 0 -> "${s / 60} min"
        else -> "$s s"
    }

    private val both = listOf("ban", "unban", "timeout", "untimeout", "delete", "clear", "title", "category", "ad", "help")
    private val twitchOnly = listOf("slow", "emoteonly", "followers", "subscribers", "raid", "announce", "marker", "clip")
    private val kickWeb = listOf("host", "poll", "prediction", "polldelete", "followonly", "mod", "unmod", "vip", "unvip", "og", "unog")

    private fun feature(name: String) = when (name) {
        "ban", "unban", "timeout", "untimeout", "delete", "clear" -> "moderation"
        "slow", "emoteonly", "followers", "subscribers" -> "chat lockdown"
        "announce" -> "announcements"
        "raid" -> "raids"
        "ad" -> "commercial"
        "clip" -> "clips"
        else -> null
    }

    suspend fun run(origin: String, name: String, a: List<String>): String {
        val kick = origin == "kick"
        val label = if (kick) "Kick" else "Twitch"
        if (origin == "youtube") return "Slash commands aren't supported on YouTube"
        if (name == "help") {
            return "$label: " + (both + if (kick) KickWeb.commands.filter { it !in both } else twitchOnly).joinToString(" ") { "/$it" }
        }
        if (name !in both + twitchOnly + kickWeb + KickWeb.commands) return "Unknown command /$name"
        // adr/0005: through the signed-in kick.com page. Signed out, /clear keeps its public-API fallback below.
        if (kick && name in KickWeb.commands && (name != "clear" || KickWeb.ready())) return KickWeb.run(name, a)
        if (kick && name in kickWeb) return "Kick has no /$name yet"
        if (kick && name in twitchOnly) return "Kick has no API for /$name yet"
        if (!kick && name in kickWeb) return "Twitch has no /$name"
        if (if (kick) Kick.userId == 0 else Twitch.userId.isEmpty()) return "$label isn't connected"
        val f = feature(name)
        if (!kick && f != null && !Twitch.hasScopes(TwitchScopes.action[f].orEmpty())) return "Reconnect Twitch to allow $f"
        return try {
            Runner(kick).run(name, a)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val text = e.message.orEmpty()
            when {
                "HTTP 401" !in text && "HTTP 403" !in text -> text
                kick -> "Kick refused: reconnect Kick in Manage to grant moderation"
                else -> "Twitch refused: reconnect Twitch in Manage"
            }
        }
    }
}

private class Runner(val kick: Boolean) {
    private val origin = if (kick) "kick" else "twitch"
    private val mod get() = mapOf("broadcaster_id" to Twitch.userId, "moderator_id" to Twitch.userId)

    private fun login(raw: String) = raw.removePrefix("@").lowercase()

    // ponytail: only the feed buffer (last 200 lines) is searched, no separate id store, like iOS.
    private fun lastMessage(login: String): ChatEvent? = ChatFeed.chat.value.lastOrNull {
        it.platform == origin && it.kind == Kind.Message && it.user.lowercase() == login && it.msgId.isNotEmpty()
    }

    /** Platform user id: from recent chat, else looked up by login (a Kick username is its channel slug, exact only). */
    private suspend fun userId(login: String): String? {
        ChatFeed.chat.value.lastOrNull {
            it.platform == origin && it.user.lowercase() == login && it.userId.isNotEmpty()
        }?.let { return it.userId }
        return if (kick) {
            Kick.api.call("GET", "/public/v1/channels", mapOf("slug" to login)).objects("data").firstOrNull()
                ?.optInt("broadcaster_user_id")?.takeIf { it > 0 }?.toString()
        } else {
            Twitch.api.call("GET", "/users", mapOf("login" to login)).objects("data").firstOrNull()?.optString("id")?.ifEmpty { null }
        }
    }

    suspend fun run(name: String, a: List<String>): String = when (name) {
        "ban", "timeout", "unban", "untimeout" -> banning(name, a)
        "delete" -> {
            val who = a.firstOrNull()?.let(::login)
            val m = who?.let(::lastMessage)
            when {
                who == null -> "Usage: /delete user"
                m == null -> "No recent message from $who"
                else -> {
                    delete(m.msgId)
                    "Deleted the last message from ${m.user}"
                }
            }
        }
        "clear" -> clear()
        "slow", "emoteonly", "followers", "subscribers" -> chatMode(name, a)
        "title" -> a.joinToString(" ").let { t ->
            if (t.isEmpty()) return "Usage: /title text"
            if (kick) Kick.apply(t, null, Kick.tags) else Twitch.apply(t, null, Twitch.tags, emptyMap(), Twitch.delay, Twitch.language)
            if ((if (kick) Kick.title else Twitch.title) == t) "Title set" else Accounts.status
        }
        "category" -> a.joinToString(" ").let { q ->
            if (q.isEmpty()) return "Usage: /category name"
            val c = (if (kick) Kick.search(q) else Twitch.search(q)).firstOrNull() ?: return "No category matching $q"
            if (kick) {
                Kick.apply(
                    Kick.title,
                    c,
                    Kick.tags
                )
            } else {
                Twitch.apply(Twitch.title, c, Twitch.tags, emptyMap(), Twitch.delay, Twitch.language)
            }
            if ((if (kick) Kick.category else Twitch.category)?.id == c.id) "Category set to ${c.name}" else Accounts.status
        }
        "ad" -> {
            val s = a.firstOrNull()?.toIntOrNull() ?: if (kick) 30 else 90
            if (kick) {
                val body = JSONObject().put("break_duration_seconds", s.coerceIn(7, 90)).put("id", UUID.randomUUID().toString())
                Kick.api.call("POST", "/public/v1/ads/ad-break", body = body)
                "Ad break started"
            } else {
                Twitch.startCommercial(((s + 15) / 30 * 30).coerceIn(30, 180)) // Twitch takes 30...180 in steps of 30
                Accounts.status
            }
        }
        "raid" -> a.firstOrNull()?.let {
            Twitch.raid(it)
            Accounts.status
        } ?: "Usage: /raid channel"
        "announce" -> if (a.isEmpty()) {
            "Usage: /announce text"
        } else {
            Twitch.announce(a.joinToString(" "))
            Accounts.status
        }
        "marker" -> {
            Twitch.createMarker()
            "Marker added"
        }
        else -> "Clip: ${Twitch.createClip()}" // "clip"
    }

    private suspend fun banning(name: String, a: List<String>): String {
        val who = a.firstOrNull()?.let(::login) ?: return "Usage: /$name user"
        val uid = userId(who) ?: return "Can't find $who"
        if (name.startsWith("un")) {
            if (kick) {
                Kick.api.call(
                    "DELETE",
                    "/public/v1/moderation/bans",
                    body = JSONObject().put("broadcaster_user_id", Kick.userId).put("user_id", uid.toInt())
                )
            } else {
                Twitch.api.call("DELETE", "/moderation/bans", mod + ("user_id" to uid))
            }
            return "Unbanned $who"
        }
        var rest = a.drop(1)
        var secs: Int? = null
        if (name == "timeout") {
            secs = rest.firstOrNull()?.let(Slash::seconds)
            if (secs != null) rest = rest.drop(1)
            // Kick wants whole minutes 1...10080, Twitch seconds up to 2 weeks.
            secs = if (kick) (((secs ?: 600) + 59) / 60).coerceIn(1, 10080) * 60 else minOf(secs ?: 600, 1_209_600)
        }
        val reason = rest.joinToString(" ").take(100)
        if (kick) {
            val body = JSONObject().put("broadcaster_user_id", Kick.userId).put("user_id", uid.toInt())
            secs?.let { body.put("duration", it / 60) }
            if (reason.isNotEmpty()) body.put("reason", reason)
            Kick.api.call("POST", "/public/v1/moderation/bans", body = body)
        } else {
            val data = JSONObject().put("user_id", uid).put("reason", reason)
            secs?.let { data.put("duration", it) }
            Twitch.api.call("POST", "/moderation/bans", mod, JSONObject().put("data", data))
        }
        return secs?.let { "Timed out $who for ${Slash.pretty(it)}" } ?: "Banned $who"
    }

    private suspend fun delete(id: String) {
        if (kick) {
            Kick.api.call("DELETE", "/public/v1/chat/$id")
        } else {
            Twitch.api.call(
                "DELETE",
                "/moderation/chat",
                mod + ("message_id" to id)
            )
        }
    }

    private suspend fun clear(): String {
        if (!kick) {
            Twitch.api.call("DELETE", "/moderation/chat", mod)
            ChatFeed.clear("twitch")
            return "Chat cleared"
        }
        // Kick's public API has no clear-all: delete the Kick messages still in the feed.
        val ids = ChatFeed.chat.value.filter { it.platform == "kick" && it.kind == Kind.Message && it.msgId.isNotEmpty() }.map { it.msgId }
        if (ids.isEmpty()) return "Nothing the app can delete yet"
        var n = 0
        for (id in ids) {
            try {
                delete(id)
                n++
            } catch (e: PlatformException) {
                val m = e.message.orEmpty()
                if ("HTTP 429" in m) return "Rate limited: deleted $n of ${ids.size} messages"
                if ("HTTP 401" in m || "HTTP 403" in m) throw e
                // anything else: already gone
            }
        }
        if (n > 0) ChatFeed.clear("kick")
        return "Deleted $n recent messages"
    }

    private suspend fun chatMode(name: String, a: List<String>): String {
        val off = a.firstOrNull()?.lowercase() == "off"
        val n = a.firstOrNull()?.toIntOrNull()
        val (body, note) = when (name) {
            "slow" -> (n ?: 30).coerceIn(3, 120).let { s ->
                (if (off) JSONObject().put("slow_mode", false) else JSONObject().put("slow_mode", true).put("slow_mode_wait_time", s)) to
                    (if (off) "Slow mode off" else "Slow mode $s s")
            }
            "emoteonly" -> JSONObject().put("emote_mode", !off) to if (off) "Emote-only off" else "Emote-only on"
            "followers" -> (n ?: 0).coerceIn(0, 129_600).let { m ->
                (
                    if (off) {
                        JSONObject().put(
                            "follower_mode",
                            false
                        )
                    } else {
                        JSONObject().put("follower_mode", true).put("follower_mode_duration", m)
                    }
                    ) to
                    (if (off) "Followers-only off" else "Followers-only $m min")
            }
            else -> JSONObject().put("subscriber_mode", !off) to if (off) "Subscribers-only off" else "Subscribers-only on"
        }
        Twitch.api.call("PATCH", "/chat/settings", mod, body)
        return note
    }
}
