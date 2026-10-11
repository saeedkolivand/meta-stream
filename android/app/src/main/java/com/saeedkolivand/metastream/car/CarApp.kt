package com.saeedkolivand.metastream.car

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.messaging.model.CarMessage
import androidx.car.app.messaging.model.ConversationCallback
import androidx.car.app.messaging.model.ConversationItem
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.Header
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.compose.runtime.snapshotFlow
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.applog
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.streaming.StreamingService
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch

class CarApp : CarAppService() {
    // Only Android Auto (gearhead, by its signing certs bundled in the library) may bind: this service can turn the
    // camera and mic on, so any-host is never allowed, not even in debug builds. The DHU connects through gearhead too.
    override fun createHostValidator(): HostValidator =
        HostValidator.Builder(this).addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample).build()

    override fun onCreateSession(): Session = CarSession()
}

private class CarSession : Session() {
    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                val app = carContext.applicationContext
                Notify.car = true
                // Android 14+ refuses to start a camera|microphone FGS from the background, so the car keeps an idle one alive
                // (started while the phone app was visible) and goLive only reuses it. See StreamingService.
                if (!StreamingService.hold(app, "car")) toast(carContext, "Open MetaStream on the phone once to stream from the car")
                lifecycleScope.launch {
                    ChatFeed.chat.collect {
                        Notify.chat(app, it)
                        delay(1000)
                    }
                } // StateFlow conflates: at most 1 post/s
            }

            override fun onDestroy(owner: LifecycleOwner) {
                Notify.car = false
                Notify.reset()
                StreamingService.release(carContext.applicationContext, "car")
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen = MainScreen(carContext)
}

/** Re-renders [screen] when Engine state (and optionally chat) changes; at most one invalidate per 500 ms. */
private fun autoRefresh(screen: Screen, chat: Boolean) {
    // ponytail: status ticks with the bitrate (~1/s) and re-sends the same template type, which the host doesn't count against
    // the 5-template quota. Upgrade path: drop the bitrate from the status row if a host ever complains.
    val state = snapshotFlow {
        listOf(Engine.live, Engine.status, Engine.source, Engine.muted, Speaker.readAloud, OverlayStore.scene)
    }.drop(1)
    val flow = if (chat) merge(state, ChatFeed.chat.drop(1)) else state
    screen.lifecycleScope.launch {
        screen.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            flow.conflate().collect {
                screen.invalidate()
                delay(500)
            }
        }
    }
}

private fun icon(c: CarContext, res: Int) = CarIcon.Builder(IconCompat.createWithResource(c, res)).setTint(CarColor.DEFAULT).build()

private fun toast(c: CarContext, text: String) = CarToast.makeText(c, text, CarToast.LENGTH_SHORT).show()

private class MainScreen(c: CarContext) : Screen(c) {
    private val readUpTo = mutableMapOf<String, Long>()

    init {
        autoRefresh(this, chat = true)
    }

    override fun onGetTemplate(): Template {
        // ListTemplate accepts Row and ConversationItem in one ItemList (RowListConstraints checks both), so no SectionedItemTemplate.
        val list = ItemList.Builder()
            .addItem(Row.Builder().setTitle(carStatusText(Engine.live, Engine.status, Engine.source)).build())
            .addItem(
                Row.Builder().setTitle("Controls").setBrowsable(true).setOnClickListener {
                    screenManager.push(ControlsScreen(carContext))
                }.build()
            )
        for ((p, name) in listOf("kick" to "Kick", "twitch" to "Twitch")) {
            val msgs = ChatFeed.chat.value.filter { it.platform == p }.takeLast(5) // docs: at most the 5 most recent, oldest first
            if (msgs.isEmpty()) continue
            list.addItem(
                ConversationItem.Builder(
                    p,
                    CarText.create(name),
                    Person.Builder().setName("Me").setKey("self").build(),
                    msgs.map { m ->
                        CarMessage.Builder().setSender(Person.Builder().setName(m.user).setKey(m.user).build())
                            .setBody(
                                CarText.create(m.text)
                            ).setReceivedTimeEpochMillis(m.time).setRead(m.time <= (readUpTo[p] ?: 0L)).build()
                    },
                    object : ConversationCallback {
                        override fun onMarkAsRead() {
                            readUpTo[p] = System.currentTimeMillis()
                            invalidate()
                        }

                        // ponytail: sending isn't implemented (no OAuth). Upgrade path: platform send() on Engine, then drop the toast.
                        override fun onTextReply(replyText: String) {
                            applog("chat", "car reply to $p dropped: sending needs sign-in")
                            toast(carContext, "Replies need sign-in (coming soon)")
                        }
                    }
                )
                    .build()
            )
        }
        val live = Engine.live
        val header = Header.Builder().setTitle("MetaStream")
            .addEndHeaderAction(
                Action.Builder().setIcon(
                    icon(carContext, if (live) R.drawable.ic_car_stop else R.drawable.ic_car_live)
                ).setOnClickListener {
                    if (live) Engine.stop() else Engine.goLive()
                    toast(carContext, Engine.status)
                }.build()
            )
            .addEndHeaderAction(
                Action.Builder().setIcon(
                    icon(carContext, if (Engine.muted) R.drawable.ic_car_mic_off else R.drawable.ic_car_mic)
                ).setOnClickListener {
                    Engine.toggleMute()
                }.build()
            )
            .build()
        return ListTemplate.Builder().setHeader(header).setSingleList(list.build()).build()
    }
}

private class ControlsScreen(c: CarContext) : Screen(c) {
    init {
        autoRefresh(this, chat = false)
    }

    private fun row(title: String, text: String? = null, onClick: () -> Unit) =
        Row.Builder().setTitle(title).apply { text?.let { addText(it) } }.setOnClickListener(onClick).build()

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for ((s, name) in listOf(Source.Phone to "Phone", Source.Usb to "USB camera", Source.Glasses to "Glasses")) {
            list.addItem(
                row("Source: $name", if (Engine.source == s) "Selected" else null) {
                    Engine.pick(s)
                    if (Engine.source != s) toast(carContext, Engine.status) // pick() reports why it refused through status
                }
            )
        }
        list.addItem(
            Row.Builder().setTitle("Scene: ${OverlayStore.scene.ifEmpty { "None" }}").setBrowsable(true)
                .apply { if (Engine.source == Source.Glasses) addText("Off for glasses") }
                .setOnClickListener { screenManager.push(SceneScreen(carContext)) }.build()
        )
        list.addItem(row("Flip camera") { Engine.switchCamera() })
        list.addItem(row("Read chat aloud", if (Speaker.readAloud) "On" else "Off") { Speaker.updateReadAloud(!Speaker.readAloud) })
        val header = Header.Builder().setTitle("Controls").setStartHeaderAction(Action.BACK).build()
        return ListTemplate.Builder().setHeader(header).setSingleList(list.build()).build()
    }
}

/** Overlay scenes: None plus every imported scene, the active one marked. */
private class SceneScreen(c: CarContext) : Screen(c) {
    init {
        autoRefresh(this, chat = false)
    }

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for (name in listOf("") + OverlayStore.pack?.scenes?.map { it.name }.orEmpty()) {
            list.addItem(
                Row.Builder().setTitle(name.ifEmpty { "None" }).apply { if (OverlayStore.scene == name) addText("Active") }
                    .setOnClickListener { OverlayStore.select(name) }.build()
            )
        }
        val header = Header.Builder().setTitle("Scene").setStartHeaderAction(Action.BACK).build()
        return ListTemplate.Builder().setHeader(header).setSingleList(list.build()).build()
    }
}
