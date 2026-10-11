package com.saeedkolivand.metastream.platforms

import com.saeedkolivand.metastream.core.applog
import java.time.Instant
import org.json.JSONObject

// Hands-free Twitch broadcaster actions (iOS TwitchService extension). Each is one decisive tap in the UI; the UI
// greys a button out until its scope was granted (TwitchScopes.action).

private fun Twitch.requireUser() {
    if (userId.isEmpty()) throw PlatformException("twitch: not connected")
}

/** `broadcaster_id` + `moderator_id` pair every moderator-scoped call needs; the broadcaster moderates their own channel. */
private fun Twitch.modQuery() = mapOf("broadcaster_id" to userId, "moderator_id" to userId)

/** POST helix/clips (clips:edit). The clip finishes processing on Twitch's side a few seconds after the id comes back. */
suspend fun Twitch.createClip(): String {
    requireUser()
    val r = api.call("POST", "/clips", mapOf("broadcaster_id" to userId))
    val id = r.objects("data").firstOrNull()?.optString("id").orEmpty().ifEmpty {
        throw PlatformException("twitch: clip create returned no id")
    }
    return "https://clips.twitch.tv/$id"
}

/** POST helix/streams/markers: the body key is `user_id`, not `broadcaster_id` (Twitch's own inconsistency). */
suspend fun Twitch.createMarker() {
    requireUser()
    api.call("POST", "/streams/markers", body = JSONObject().put("user_id", userId))
}

/** GET helix/channels/ads (channel:read:ads). `next_ad_at` is "" when nothing is scheduled; failures are logged, not surfaced. */
suspend fun Twitch.refreshAdSchedule() {
    try {
        val a = api.call("GET", "/channels/ads", mapOf("broadcaster_id" to userId)).objects("data").firstOrNull() ?: return
        adSnoozeCount = a.optInt("snooze_count")
        adNextAt = a.optString("next_ad_at").takeIf { it.isNotEmpty() }?.let { runCatching { Instant.parse(it) }.getOrNull() }
    } catch (e: PlatformException) {
        applog("api", "twitch ad schedule: ${e.message}")
    }
}

/** POST helix/channels/ads/schedule/snooze (channel:manage:ads). */
suspend fun Twitch.snoozeAd() = attempt("Ad snoozed") {
    api.call("POST", "/channels/ads/schedule/snooze", mapOf("broadcaster_id" to userId))
    refreshAdSchedule()
}

/** POST helix/channels/commercial (channel:edit:commercial). Twitch accepts 30/60/90/120/150/180 s; fixed 90 like iOS. */
suspend fun Twitch.startCommercial(seconds: Int = 90) = attempt("Commercial started") {
    requireUser()
    api.call("POST", "/channels/commercial", body = JSONObject().put("broadcaster_id", userId).put("length", seconds))
}

/** PATCH helix/chat/settings (moderator:manage:chat_settings). Fixed 10-min follower gate / 10 s slow mode, as on iOS. */
suspend fun Twitch.lockdownChat(on: Boolean) = attempt(if (on) "Chat locked down" else "Chat lockdown lifted") {
    requireUser()
    val body = if (on) {
        JSONObject().put(
            "follower_mode",
            true
        ).put("follower_mode_duration_minutes", 10).put("slow_mode", true).put("slow_mode_wait_seconds", 10)
    } else {
        JSONObject().put("follower_mode", false).put("slow_mode", false)
    }
    api.call("PATCH", "/chat/settings", modQuery(), body)
}

/** POST helix/chat/announcements (moderator:manage:announcements); default colour. */
suspend fun Twitch.announce(message: String) = attempt("Announcement sent") {
    requireUser()
    api.call("POST", "/chat/announcements", modQuery(), JSONObject().put("message", message.trim().ifEmpty { return@attempt }))
}

/** POST helix/raids (channel:manage:raids). Takes a login name, resolved to an id via GET /users first. */
suspend fun Twitch.raid(targetLogin: String) {
    val login = targetLogin.trim().lowercase()
    if (login.isEmpty()) return
    attempt {
        requireUser()
        val to = api.call("GET", "/users", mapOf("login" to login)).objects("data").firstOrNull()?.optString("id").orEmpty()
        if (to.isEmpty()) return@attempt Accounts.say("Twitch: no user named $login")
        api.call("POST", "/raids", mapOf("from_broadcaster_id" to userId, "to_broadcaster_id" to to))
        Accounts.say("Raiding $login")
    }
}
