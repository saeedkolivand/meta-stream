package com.saeedkolivand.metastream.platforms

import com.saeedkolivand.metastream.core.redactFromLogs
import com.saeedkolivand.metastream.core.scrub
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OAuthTest {
    // RFC 7636 appendix B test vector.
    @Test fun s256MatchesRfcVector() {
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", Pkce.s256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
    }

    @Test fun randomIsUnreservedAndFresh() {
        val v = Pkce.random(64)
        assertEquals(64, v.length)
        assertTrue(v.all { it.isLetterOrDigit() || it in "-._~" })
        assertNotEquals(v, Pkce.random(64))
    }

    @Test fun redirectWithMatchingStateCompletesOnce() {
        val flow = OAuth.expect("state-ok")
        assertTrue(OAuth.deliver("state-ok", "the-code"))
        assertEquals("the-code", kotlinx.coroutines.runBlocking { flow.await() })
        assertFalse(OAuth.deliver("state-ok", "replayed")) // a state is single-use
    }

    @Test fun redirectWithUnknownOrMissingStateIsRejected() {
        val flow = OAuth.expect("state-a")
        assertFalse(OAuth.deliver("state-b", "stolen-code"))
        assertFalse(OAuth.deliver(null, "stolen-code"))
        assertFalse(flow.isCompleted) // the real flow keeps waiting
        assertTrue(OAuth.deliver("state-a", null)) // denial still ends it, with no code
        assertEquals(null, kotlinx.coroutines.runBlocking { flow.await() })
    }

    @Test fun tokensAreScrubbedFromLogs() {
        redactFromLogs("ya29.super-secret-token")
        assertEquals("Bearer ***", scrub("Bearer ya29.super-secret-token"))
        redactFromLogs("abc") // too short to be a secret
        assertEquals("abc", scrub("abc"))
    }

    @Test fun missingTwitchScopesMatchIos() {
        val granted = setOf("channel:manage:broadcast", "user:read:chat", "clips:edit", "channel:read:ads", "channel:manage:ads")
        assertEquals(
            listOf("announcements", "chat lockdown", "cheers", "commercial", "follows", "moderation", "raids", "subscriptions"),
            TwitchScopes.missingFeatures(granted)
        )
        assertEquals(TwitchScopes.chat.size + TwitchScopes.action.size, TwitchScopes.missingFeatures(emptySet()).size)
    }

    @Test fun pickBroadcastPrefersTheMostAliveOne() {
        fun b(id: String, status: String) = JSONObject().put("id", id).put("status", JSONObject().put("lifeCycleStatus", status))
        assertEquals("b", pickBroadcast(listOf(b("a", "complete"), b("b", "live"), b("c", "ready")))?.getString("id"))
        assertEquals("c", pickBroadcast(listOf(b("a", "complete"), b("c", "ready")))?.getString("id"))
        assertEquals("a", pickBroadcast(listOf(b("a", "complete")))?.getString("id")) // nothing alive: newest
    }
}
