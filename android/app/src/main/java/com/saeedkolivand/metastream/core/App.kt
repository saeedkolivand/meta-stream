package com.saeedkolivand.metastream.core

import android.app.Application
import com.saeedkolivand.metastream.car.Notify
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Creates the process-wide singletons and wires them together; this is the only place that knows all of them. */
class App : Application() {
    // The one app-level scope; lives as long as the process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        Speaker.init(this)
        ChatFeed.init(scope, onMessage = Speaker::speakChat)
        Engine.init(this, scope, speak = Speaker::speakSystem, alert = { Notify.alert(this, it) })
    }
}
