package com.saeedkolivand.metastream.core

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

/** Creates the channel if needed (idempotent) and returns the manager. */
fun ensureChannel(c: Context, id: String, name: String, importance: Int): NotificationManager {
    val m = c.getSystemService(NotificationManager::class.java)
    m.createNotificationChannel(NotificationChannel(id, name, importance))
    return m
}
