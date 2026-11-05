package com.saeedkolivand.metastream.core

import android.app.Application
import com.saeedkolivand.metastream.bot.AppBot
import com.saeedkolivand.metastream.bot.BotCommand
import com.saeedkolivand.metastream.bot.BotList
import com.saeedkolivand.metastream.bot.send
import com.saeedkolivand.metastream.car.Notify
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.ChatModerator
import com.saeedkolivand.metastream.core.logging.LogFile
import com.saeedkolivand.metastream.core.logging.applogListener
import com.saeedkolivand.metastream.core.storage.AppSettings
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.goal.DonatePage
import com.saeedkolivand.metastream.goal.DonationHub
import com.saeedkolivand.metastream.goal.GoalStore
import com.saeedkolivand.metastream.goal.countDonation
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.Overlays
import com.saeedkolivand.metastream.overlay.SceneRoles
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.overlay.WidgetFonts
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.KickWeb
import com.saeedkolivand.metastream.platforms.Spotify
import com.saeedkolivand.metastream.privacy.Privacy
import com.saeedkolivand.metastream.reach.LivePost
import com.saeedkolivand.metastream.reach.SessionLog
import com.saeedkolivand.metastream.remote.ObsServer
import com.saeedkolivand.metastream.speech.Speaker
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source
import com.saeedkolivand.metastream.streaming.StreamingService
import com.saeedkolivand.metastream.streaming.audio.AudioMix
import com.saeedkolivand.metastream.streaming.audio.Mics
import com.saeedkolivand.metastream.streaming.audio.Soundboard
import com.saeedkolivand.metastream.streaming.compositor
import com.saeedkolivand.metastream.streaming.video.Looks
import io.sentry.Sentry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Creates the process-wide singletons and wires them together; this is the only place that knows all of them. */
class App : Application() {
    // The one app-level scope; lives as long as the process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        super.onCreate()
        applogListener = { category, message -> Sentry.addBreadcrumb(message, category) } // Sentry itself starts before onCreate
        LogFile.start(this)
        Prefs.init(this)
        WidgetFonts.init(this)
        AppSettings.init()
        Mics.init(this)
        KickWeb.init(this)
        Mics.log(this, "at launch")
        Soundboard.init(this)
        Looks.init(this)
        AudioMix.init()
        Speaker.init(this)
        Speaker.skipMessage = { !BotList.reads(it.user, it.text) || AppBot.isOwn(it) }
        OverlayStore.init(this)
        Overlays.init(this)
        compositor = Overlays
        SceneRoles.onRole = AppBot::role
        Privacy.init(Speaker::speakSystem)
        Privacy.resync = Overlays::syncPrivacy
        Privacy.isApplicable = { Engine.source != Source.Glasses }
        Privacy.isLive = { Engine.live }
        Accounts.init(this, scope)
        Spotify.init()
        ChatModerator.init(scope)
        ChatFeed.init(scope) {
            Speaker.speakChat(it)
            // providers call from their socket thread; the bot and the goal are main-thread
            scope.launch {
                countDonation(it)
                AppBot.handle(it)
                SessionLog.record(it)
            }
        }
        AppBot.init()
        GoalStore.init(this, scope)
        DonationHub.start(scope)
        DonatePage.start(scope)
        SessionLog.init(this)
        LivePost.start(scope)
        ObsServer.sync(scope)
        GoalStore.onReached = {
            Speaker.speakSystem("Goal reached")
            AppBot.goalReached(GoalStore.config.title)
        }
        StreamingService.notifyCommand = { notifyCommand()?.text }
        StreamingService.sendNotifyCommand = { notifyCommand()?.let { c -> scope.launch { c.send() } } } // re-read at tap time
        Engine.init(this, scope, speak = Speaker::speakSystem, alert = { Notify.alert(this, it) })
        Scenes.init(scope)
        Scenes.updateRotation()
    }
}

/** The saved command chosen for the live notification's action (Settings › Chat commands). */
private fun notifyCommand() =
    Prefs.string("notifyCommand").takeIf { it.isNotEmpty() }?.let { t -> BotCommand.stored().firstOrNull { it.text == t } }
