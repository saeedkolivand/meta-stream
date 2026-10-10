package com.saeedkolivand.metastream.streaming

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.SystemClock
import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.ensureChannel
import com.saeedkolivand.metastream.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

private const val CHANNEL = "live"
private const val NOTIFICATION_ID = 1
private const val ACTION_MUTE = "com.saeedkolivand.metastream.MUTE"
private const val ACTION_STOP = "com.saeedkolivand.metastream.STOP"
private const val TEXT_THROTTLE_MS = 5000L

/**
 * Keeps the process (and camera/mic access) alive; the stream itself is owned by [Engine].
 *
 * Android 14+ refuses to start a camera|microphone foreground service from the background, and a service started while the
 * app is visible keeps its while-in-use camera/mic access. So the service also runs idle ("ready") while the phone app is
 * visible or a car session exists, and a later goLive from the car only reuses the already-running service.
 */
class StreamingService : Service() {
    // Owned here, cancelled in onDestroy: re-posts the notification when the Engine state it shows changes.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        if (!getSystemService(NotificationManager::class.java).canPostPromotedNotifications()) {
            applog("service", "Live Updates are off for this app; the notification stays a normal ongoing one")
        }
        scope.launch {
            var last: LiveNotice? = null
            var at = 0L
            snapshotFlow { currentNotice() }.collect { n ->
                val l = last
                val now = SystemClock.elapsedRealtime()
                // Bitrate-only (text) changes are throttled to one post per 5 s; any other change posts at once.
                if (running && (n == null || l == null || n.copy(text = l.text) != l || now - at >= TEXT_THROTTLE_MS)) {
                    getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(this@StreamingService, n))
                    last = n
                    at = now
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_MUTE -> Engine.toggleMute()
            ACTION_STOP -> Engine.stop()
            else -> {
                startForeground(
                    NOTIFICATION_ID,
                    notification(this, currentNotice()),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
                running = true
                return START_NOT_STICKY
            }
        }
        if (!running) stopSelf() // a stale notification action started a service nobody holds
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        scope.cancel()
    }

    companion object {
        @Volatile
        var running = false
            private set

        // "app" (activity visible), "car" (car session), "live". Shared by the activity, the car session and Engine, so every
        // access holds this set's monitor.
        private val holders = mutableSetOf<String>()

        /** Null while idle ("ready"). Reads snapshot state, so inside snapshotFlow it re-runs when any of it changes. */
        private fun currentNotice() =
            if (Engine.live) liveNotice(Engine.source, Engine.status, Engine.connected, Engine.liveSince, Engine.muted) else null

        private fun action(c: Context, code: Int, action: String) =
            PendingIntent.getService(c, code, Intent(c, StreamingService::class.java).setAction(action), PendingIntent.FLAG_IMMUTABLE)

        private fun notification(c: Context, n: LiveNotice?): Notification {
            ensureChannel(c, CHANNEL, "Live", NotificationManager.IMPORTANCE_LOW)
            val b = Notification.Builder(c, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                // Tap to reopen the app and Stop: back-press no longer ends the stream.
                .setContentIntent(PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
            if (n == null) return b.setContentTitle(c.getString(R.string.ready_title)).build()
            b.setContentTitle(n.title).setContentText(n.text)
                .setOnlyAlertOnce(true)
                .setRequestPromotedOngoing(true) // Android 16 Live Update; needs POST_PROMOTED_NOTIFICATIONS
                .addAction(android.R.drawable.ic_btn_speak_now, n.muteLabel, action(c, 1, ACTION_MUTE))
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", action(c, 2, ACTION_STOP))
            n.chronometerSince?.let { b.setWhen(it).setUsesChronometer(true) }
            n.chip?.let { b.setShortCriticalText(it) }
            return b.build()
        }

        /** Registers [who] as needing the service; false when Android refuses to start it (background, or no camera/mic permission). */
        fun hold(c: Context, who: String): Boolean = synchronized(holders) {
            holders += who
            if (running) return true
            try {
                c.startForegroundService(Intent(c, StreamingService::class.java))
                true
            } catch (e: Exception) {
                holders -= who
                applog("service", "can't start: ${e.message}")
                false
            }
        }

        fun release(c: Context, who: String) {
            synchronized(holders) {
                holders -= who
                if (holders.isEmpty() && !Engine.live) c.stopService(Intent(c, StreamingService::class.java))
            }
        }
    }
}
