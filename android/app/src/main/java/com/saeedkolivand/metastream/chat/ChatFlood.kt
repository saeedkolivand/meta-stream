package com.saeedkolivand.metastream.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val PER_SECOND = 10
private const val DURATION_S = 60

private val NAMES = listOf("amir", "Sara", "kian_live", "Mina", "Pouya", "luna", "Dariush", "zed", "نیلوفر", "Bahar")
private val COLORS = listOf("#FF4500", "#1E90FF", "#2E8B57", "#DAA520", "#9ACD32", "#D2691E", "#FF69B4", "#8A2BE2")
private val BADGES = listOf(emptyList(), listOf("subscriber"), listOf("moderator"), listOf("vip", "subscriber"), listOf("broadcaster"))
private val TEXTS = listOf(
    "hello everyone, great stream today",
    "that was insane, did you see that?",
    "سلام به همه، استریم عالیه",
    "امروز چه خبر؟ خیلی خوب بود",
    "catJAM catJAM catJAM",
    "this is so funny PepeLaugh",
    "EZ clap",
    "no way [emote:37226:KEKW] [emote:37226:KEKW]",
    "first time here, loving the vibe"
)

/** Fake chat for load-testing the overlay and the main screen: 10 msg/s for 60 s through the normal feed, origin "test". */
object ChatFlood {
    var running by mutableStateOf(false)
        private set
    private var job: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun toggle() {
        if (running) {
            job?.cancel()
            running = false
            return
        }
        running = true
        job = scope.launch {
            try {
                repeat(PER_SECOND * DURATION_S) { i ->
                    if (!isActive) return@repeat
                    ChatFeed.onChat(
                        ChatEvent(
                            "test",
                            NAMES[i % NAMES.size],
                            TEXTS[i % TEXTS.size],
                            color = COLORS[i % COLORS.size],
                            badges = BADGES[i % BADGES.size]
                        )
                    )
                    delay(1000L / PER_SECOND)
                }
            } finally {
                running = false
            }
        }
    }
}
