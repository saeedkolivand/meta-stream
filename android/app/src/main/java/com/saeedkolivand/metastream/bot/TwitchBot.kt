package com.saeedkolivand.metastream.bot

import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.BuildConfig
import com.saeedkolivand.metastream.core.network.Endpoint
import com.saeedkolivand.metastream.core.network.Net
import com.saeedkolivand.metastream.core.network.PlatformException
import com.saeedkolivand.metastream.core.network.objects
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.storage.TokenStore
import com.saeedkolivand.metastream.platforms.Accounts
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

private const val TOKEN_URL = "https://id.twitch.tv/oauth2/token"
private const val SCOPES = "user:read:chat user:write:chat user:bot"

/** The app bot's own Twitch account (iOS AppBot.connectTwitch): a second device-code login, tokens under "twitchBot". */
internal object TwitchBot {
    var name by mutableStateOf(Prefs.string("botTwitchName"))
        private set
    val id get() = Prefs.string("botTwitchID")
    val connected get() = id.isNotEmpty() && TokenStore.has("twitchBotAccess")
    private var login: Job? = null

    val api = Endpoint("https://api.twitch.tv/helix", "twitchBotAccess", mapOf("Client-Id" to BuildConfig.TWITCH_CLIENT_ID)) {
        save(
            Net.form(
                TOKEN_URL,
                mapOf(
                    "grant_type" to "refresh_token",
                    "client_id" to BuildConfig.TWITCH_CLIENT_ID,
                    "refresh_token" to TokenStore.get("twitchBotRefresh").orEmpty()
                )
            )
        )
    }

    private fun save(json: JSONObject) {
        TokenStore.set("twitchBotAccess", json.optString("access_token").ifEmpty { throw PlatformException("no access_token in response") })
        json.optString("refresh_token").takeIf { it.isNotEmpty() }?.let { TokenStore.set("twitchBotRefresh", it) }
    }

    /**
     * The device flow has no account picker: the bot is whichever account is signed in on the activate page (use a
     * private tab or sign out first). A second tap restarts the login, so an older poll can't overwrite the tokens.
     */
    fun connect() {
        login?.cancel()
        login = Accounts.scope.launch {
            try {
                val cid = BuildConfig.TWITCH_CLIENT_ID
                val dev = Net.form("https://id.twitch.tv/oauth2/device", mapOf("client_id" to cid, "scopes" to SCOPES))
                val code = dev.optString("device_code").ifEmpty { throw PlatformException("no device_code in response") }
                AppBot.status = "Enter code ${dev.optString("user_code")} on Twitch as the bot account"
                val url = dev.optString("verification_uri").ifEmpty { "https://www.twitch.tv/activate" }
                Accounts.app.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                val interval = maxOf(dev.optInt("interval", 5), 5)
                repeat(900 / interval) {
                    // ponytail: 15 min ceiling
                    delay(interval * 1000L)
                    val grant = "urn:ietf:params:oauth:grant-type:device_code"
                    val r = Net.form(
                        TOKEN_URL,
                        mapOf("client_id" to cid, "scopes" to SCOPES, "device_code" to code, "grant_type" to grant),
                        allowError = true
                    )
                    if (r.has("access_token")) {
                        save(r)
                        val u = api.call("GET", "/users").objects("data").firstOrNull()
                        Prefs.put("botTwitchID", u?.optString("id").orEmpty())
                        name = u?.optString("display_name").orEmpty()
                        Prefs.put("botTwitchName", name)
                        AppBot.status = "Twitch bot connected as $name"
                        return@launch
                    }
                    if (r.optString("message") != "authorization_pending") throw PlatformException("Twitch: ${r.optString("message")}")
                }
                AppBot.status = "Twitch login timed out"
            } catch (e: CancellationException) {
                throw e // replaced by a newer tap: that login owns the status line now
            } catch (e: Exception) {
                AppBot.status = e.message.orEmpty()
            }
        }
    }

    fun disconnect() {
        login?.cancel()
        TokenStore.forget("twitchBot")
        Prefs.put("botTwitchID", "")
        Prefs.put("botTwitchName", "")
        name = ""
    }
}
