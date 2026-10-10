package com.saeedkolivand.metastream.streaming

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.core.ensureChannel
import com.saeedkolivand.metastream.ui.MainActivity

private const val CHANNEL = "live"
private const val NOTIFICATION_ID = 1

/**
 * Keeps the process (and camera/mic access) alive; the stream itself is owned by [Engine].
 *
 * Android 14+ refuses to start a camera|microphone foreground service from the background, and a service started while the
 * app is visible keeps its while-in-use camera/mic access. So the service also runs idle ("ready") while the phone app is
 * visible or a car session exists, and a later goLive from the car only reuses the already-running service.
 */
class StreamingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            NOTIFICATION_ID,
            notification(this),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        )
        running = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
    }

    companion object {
        @Volatile
        var running = false
            private set

        // "app" (activity visible), "car" (car session), "live". Shared by the activity, the car session and Engine, so every
        // access holds this set's monitor.
        private val holders = mutableSetOf<String>()

        private fun notification(c: Context): Notification {
            ensureChannel(c, CHANNEL, "Live", NotificationManager.IMPORTANCE_LOW)
            return NotificationCompat.Builder(c, CHANNEL)
                .setContentTitle(c.getString(if (Engine.live) R.string.live_title else R.string.ready_title))
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                // Tap to reopen the app and Stop: back-press no longer ends the stream.
                .setContentIntent(PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
                .build()
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
                if (holders.isEmpty() && !Engine.live) c.stopService(Intent(c, StreamingService::class.java)) else refresh(c)
            }
        }

        /** Re-posts the notification (live vs ready) on the running service. */
        fun refresh(c: Context) {
            if (running) c.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(c))
        }
    }
}
