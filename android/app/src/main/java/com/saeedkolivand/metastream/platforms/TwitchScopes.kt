package com.saeedkolivand.metastream.platforms

/** Twitch scope tables, keyed by the feature name the UI shows (iOS TwitchService.chatScopes/actionScopes). */
internal object TwitchScopes {
    // Read scopes the chat feed's EventSub subscriptions need.
    val chat = mapOf(
        "chat" to setOf("user:read:chat"),
        "follows" to setOf("moderator:read:followers"),
        "subscriptions" to setOf("channel:read:subscriptions"),
        "cheers" to setOf("bits:read")
    )

    // Write scopes for hands-free broadcaster actions. Markers use channel:manage:broadcast (already requested for
    // title edits), so they need no entry here.
    val action = mapOf(
        "clips" to setOf("clips:edit"),
        "ads" to setOf("channel:read:ads", "channel:manage:ads"),
        "commercial" to setOf("channel:edit:commercial"),
        "chat lockdown" to setOf("moderator:manage:chat_settings"),
        "announcements" to setOf("moderator:manage:announcements"),
        "raids" to setOf("channel:manage:raids"),
        "moderation" to setOf("moderator:manage:chat_messages", "moderator:manage:banned_users")
    )

    /** Requested at device-code login; the order matches iOS. */
    const val REQUESTED = "channel:manage:broadcast channel:read:stream_key user:write:chat user:read:chat moderator:read:followers " +
        "channel:read:subscriptions bits:read clips:edit channel:read:ads channel:manage:ads channel:edit:commercial " +
        "moderator:manage:chat_settings moderator:manage:announcements channel:manage:raids moderator:manage:chat_messages " +
        "moderator:manage:banned_users"

    /** Content classification label ids, used until the live catalog loads. */
    val labelFallback = mapOf(
        "DebatedSocialIssuesAndPolitics" to "Debated social issues & politics",
        "DrugsIntoxication" to "Drugs, intoxication",
        "SexualThemes" to "Sexual themes",
        "ViolentGraphic" to "Violent & graphic",
        "Gambling" to "Gambling",
        "ProfanityVulgarity" to "Profanity & vulgarity"
    )

    /** Feature names whose scopes are not all in [granted]; empty once the user reconnects. */
    fun missingFeatures(granted: Set<String>): List<String> = (chat + action).filterValues { !granted.containsAll(it) }.keys.sorted()
}
