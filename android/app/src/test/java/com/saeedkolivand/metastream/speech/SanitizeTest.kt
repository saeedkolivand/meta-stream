package com.saeedkolivand.metastream.speech

import org.junit.Assert.assertEquals
import org.junit.Test

class SanitizeTest {
    @Test fun stripsUrls() = assertEquals("see and", sanitizeSpeech("see https://x.io/a?b=1 and www.example.com"))

    @Test fun stripsKickEmotes() = assertEquals("hi there", sanitizeSpeech("hi [emote:123:KEKW] there"))

    @Test fun stripsColonEmotes() = assertEquals("nice", sanitizeSpeech("nice :Kappa:"))

    @Test fun keepsMentionName() = assertEquals("hello bob_1", sanitizeSpeech("hello @bob_1"))

    @Test fun collapsesWhitespace() = assertEquals("a b c", sanitizeSpeech("  a \n b\t\tc  "))

    @Test fun capsAt200() = assertEquals(200, sanitizeSpeech("x".repeat(500)).length)

    @Test fun emptyWhenOnlyNoise() = assertEquals("", sanitizeSpeech(" https://x.io :Kappa: "))
}
