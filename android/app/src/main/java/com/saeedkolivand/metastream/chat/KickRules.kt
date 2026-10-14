package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.platforms.Accounts
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

// Kick's Pusher events are undocumented and get renamed, so alerts are parsed by a rules table (same JSON as iOS and
// docs/kick-events.json): a remote copy wins, then the cached one, then this built-in.
internal val DEFAULT_KICK_RULES = """
{
  "version": 1,
  "channels": ["chatrooms.{chatroomId}.v2", "channel.{channelId}"],
  "events": {
    "App\\Events\\SubscriptionEvent": {"kind": "subscribe", "user": ["username"]},
    "App\\Events\\GiftedSubscriptionsEvent": {"kind": "subscribe", "user": ["gifter_username", "username"], "count": ["gifted_usernames", "quantity", "gifter_total"], "minCount": 1},
    "App\\Events\\StreamHostEvent": {"kind": "raid", "user": ["host_username"], "count": ["number_viewers"]},
    "App\\Events\\FollowersUpdated": {"kind": "follow", "user": ["username"], "require": "followed"},
    "App\\Events\\KicksGifted": {"kind": "tip", "user": ["sender.username", "username"], "amount": ["gift.amount", "amount"], "text": ["message"]}
  }
}
""".trimIndent()

private const val RULES_URL = "https://metastream.iamsaeed.dev/kick-events.json"
private val KINDS = mapOf(
    "follow" to Kind.Follow,
    "subscribe" to Kind.Subscribe,
    "raid" to Kind.Raid,
    "tip" to Kind.Tip,
    "cheer" to Kind.Cheer
)

private fun valid(raw: String): JSONObject? = runCatching { JSONObject(raw).takeIf { it.optInt("version") == 1 } }.getOrNull()

/** Remote rules (cached on success), else the cached copy, else the built-in default. Never throws. */
internal suspend fun loadKickRules(): JSONObject = withContext(Dispatchers.IO) {
    val cache = File(Accounts.app.cacheDir, "kick-events.json")
    val remote = runCatching {
        val c = URL(RULES_URL).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 5000
            c.readTimeout = 5000
            c.inputStream.bufferedReader().readText().takeIf { valid(it) != null }
        } finally {
            c.disconnect()
        }
    }.getOrNull()
    val (rules, source) = when {
        remote != null -> runCatching { cache.writeText(remote) }.let { valid(remote)!! to "remote" }
        else -> runCatching { valid(cache.readText()) }.getOrNull()?.let { it to "cached" }
            ?: (JSONObject(DEFAULT_KICK_RULES) to "built-in")
    }
    applog(
        "chat",
        "kick rules: $source, ${rules.optJSONObject(
            "events"
        )?.length() ?: 0} events, ${rules.optJSONArray("channels")?.length() ?: 0} channels"
    )
    rules
}

/** `channels` with {chatroomId}/{channelId} filled in; a channel with any other placeholder is skipped. */
internal fun kickChannels(rules: JSONObject, chatroomId: Int, channelId: Int): List<String> {
    val list = rules.optJSONArray("channels") ?: return emptyList()
    return (0 until list.length()).mapNotNull { i ->
        list.optString(i).replace("{chatroomId}", "$chatroomId").replace("{channelId}", "$channelId")
            .takeIf { '{' !in it && it.isNotEmpty() }
    }
}

private fun resolve(d: JSONObject, path: String): Any? {
    var cur: Any? = d
    for (key in path.split('.')) cur = (cur as? JSONObject)?.opt(key)
    return cur.takeIf { it != null && it != JSONObject.NULL && it != "" && !(it is JSONArray && it.length() == 0) }
}

private fun first(d: JSONObject, paths: JSONArray?): Any? =
    (0 until (paths?.length() ?: 0)).firstNotNullOfOrNull { resolve(d, paths!!.optString(it)) }

private fun text(d: JSONObject, paths: JSONArray?) = when (val v = first(d, paths)) {
    is String -> v
    is Number -> v.toString()
    else -> ""
}

private fun number(d: JSONObject, paths: JSONArray?) = when (val v = first(d, paths)) {
    is JSONArray -> v.length()
    is Number -> v.toInt()
    is String -> v.toIntOrNull() ?: 0
    else -> 0
}

/** One Kick event's `data` JSON string -> alert via its rule in [rules]; null when unmatched, malformed or dropped by the rule. */
internal fun parseKickRule(rules: JSONObject, eventName: String, dataJson: String): ChatEvent? = runCatching {
    val rule = rules.optJSONObject("events")?.optJSONObject(eventName) ?: return null
    val kind = KINDS[rule.optString("kind")] ?: return null
    val d = JSONObject(dataJson)
    rule.optString("require").takeIf { it.isNotEmpty() }?.let {
        if (resolve(d, it).let { v -> v != true && v != "true" && v != 1 }) return null
    }
    val user = text(d, rule.optJSONArray("user")).ifEmpty { return null }
    val n = number(d, rule.optJSONArray("count")).coerceAtLeast(rule.optInt("minCount", 0))
    val body = text(d, rule.optJSONArray("text"))
    ChatEvent(
        "kick",
        user,
        body,
        kind = kind,
        count = if (kind == Kind.Tip) 0 else n,
        amountCents = if (kind == Kind.Tip) number(d, rule.optJSONArray("amount")) else 0
    )
}.getOrNull()
