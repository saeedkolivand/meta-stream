package com.saeedkolivand.metastream.car

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import com.saeedkolivand.metastream.chat.ChatEvent
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.ensureChannel

private const val CHAT = "chat"
private const val ALERT = "alerts"
private val platforms = listOf("kick" to "Kick", "twitch" to "Twitch")

/** Car-facing notifications: chat as MessagingStyle (Android Auto requires it next to templated messaging) and stream-health alerts. */
object Notify {
    /** True while a car session exists; phone-only use gets no chat/alert notifications. */
    @Volatile var car = false
    private val seen = mutableMapOf<String, Long>() // newest chat time already posted per platform

    fun reset() = seen.clear()

    private fun nm(c: Context): NotificationManagerCompat {
        // ponytail: LOW = no heads-up spam for chat (docs: IMPORTANCE_DEFAULT or lower); HIGH only for stream-health alerts.
        ensureChannel(c, CHAT, "Chat", NotificationManager.IMPORTANCE_LOW)
        ensureChannel(c, ALERT, "Stream alerts", NotificationManager.IMPORTANCE_HIGH)
        return NotificationManagerCompat.from(c)
    }

    fun chat(c: Context, all: List<ChatEvent>) {
        val n = nm(c)
        if (!n.areNotificationsEnabled()) return
        for ((i, p) in platforms.withIndex()) {
            val msgs = all.filter { it.platform == p.first }.takeLast(5)
            val newest = msgs.lastOrNull()?.time ?: continue
            if (newest <= seen.getOrPut(p.first) { System.currentTimeMillis() }) continue
            seen[p.first] = newest
            val style = NotificationCompat.MessagingStyle(
                Person.Builder().setName("Me").setKey("self").build()
            ).setConversationTitle(p.second)
            for (m in msgs) style.addMessage(m.text, m.time, Person.Builder().setName(m.user).setKey(m.user).build())
            val reply = NotificationCompat.Action.Builder(android.R.drawable.ic_menu_send, "Reply", pi(c, p.first, "reply", i, true))
                .addRemoteInput(RemoteInput.Builder("reply").setLabel("Reply").build())
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY).setShowsUserInterface(false).build()
            val read = NotificationCompat.Action.Builder(android.R.drawable.ic_menu_view, "Mark as read", pi(c, p.first, "read", i, false))
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ).setShowsUserInterface(false).build()
            val builder = NotificationCompat.Builder(c, CHAT).setSmallIcon(android.R.drawable.stat_notify_chat)
            post(
                n,
                100 + i,
                builder.setStyle(
                    style
                ).addAction(reply).addAction(read).setOnlyAlertOnce(true).setCategory(NotificationCompat.CATEGORY_MESSAGE).build()
            )
        }
    }

    fun alert(c: Context, text: String) {
        if (!car) return
        val n = nm(c)
        if (!n.areNotificationsEnabled()) return
        val builder = NotificationCompat.Builder(c, ALERT).setSmallIcon(android.R.drawable.ic_dialog_alert)
        post(
            n,
            200,
            builder.setContentTitle(
                "MetaStream"
            ).setContentText(text).setCategory(NotificationCompat.CATEGORY_STATUS).setAutoCancel(true).build()
        )
    }

    // Callers check areNotificationsEnabled(); the user can still revoke POST_NOTIFICATIONS between that check and the post.
    private fun post(n: NotificationManagerCompat, id: Int, notification: Notification) {
        try {
            n.notify(id, notification)
        } catch (e: SecurityException) {
            applog("notify", "notification permission revoked: ${e.message}")
        }
    }

    fun cancelChat(c: Context, platform: String) =
        NotificationManagerCompat.from(c).cancel(100 + platforms.indexOfFirst { it.first == platform })

    private fun pi(c: Context, platform: String, action: String, i: Int, mutable: Boolean) = PendingIntent.getBroadcast(
        c,
        i * 2 + (if (mutable) 1 else 0),
        Intent(c, ChatReceiver::class.java).setAction(action).putExtra("p", platform),
        PendingIntent.FLAG_UPDATE_CURRENT or (if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)
    )
}

class ChatReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val p = i.getStringExtra("p") ?: return
        // ponytail: sending isn't implemented (no OAuth); the reply is dropped. Upgrade path: platform send() from Engine.
        if (i.action ==
            "reply"
        ) {
            applog(
                "chat",
                "reply to $p dropped: sending needs sign-in (${RemoteInput.getResultsFromIntent(
                    i
                )?.getCharSequence("reply")?.length ?: 0} chars)"
            )
        }
        Notify.cancelChat(c, p)
    }
}
