package com.saeedkolivand.metastream.platforms

import android.annotation.SuppressLint
import android.app.Application
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.logging.applog
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Kick slash commands the public API lacks, run from a hidden signed-in kick.com page (iOS KickWeb, adr/0005). Endpoints
 * were captured from kick.com's own requests (2026-10-17 / 19); unofficial, they can change any day. Never logs cookies,
 * tokens or response bodies. Results come back by polling the page (no JavaScript bridge is exposed to kick.com's scripts).
 */
object KickWeb {
    val commands = listOf(
        "slow", "emoteonly", "followers", "followonly", "subscribers", "raid", "clip", "clear", "poll", "polldelete",
        "mod", "unmod", "vip", "unvip", "og", "unog", "prediction"
    )

    /** Signed-in kick.com username; "" = not signed in. */
    var user by mutableStateOf("")
        private set
    val signedIn get() = user.isNotEmpty()
    private var slug = ""
    private var channelId: Int? = null
    private lateinit var app: Application
    private var web: WebView? = null
    private var loaded = false
    private var seq = 0

    fun init(application: Application) {
        app = application
    }

    // pure parts (tested)

    /** PATCH body for /slow, /emoteonly, /followonly (/followers); null for anything else. */
    fun modeBody(name: String, a: List<String>): String? {
        val off = a.firstOrNull()?.lowercase() == "off"
        val n = a.firstNotNullOfOrNull { it.toIntOrNull() }
        return when (name) {
            "slow" -> """{"slow_mode":{"enabled":${!off},"duration_seconds":${if (off) 1 else maxOf(n ?: 5, 1)}}}"""
            "emoteonly" -> """{"emotes_only_mode":{"enabled":${!off}}}"""
            "followonly", "followers" ->
                """{"followers_only_mode":{"enabled":${!off},"duration_seconds":${if (off) 1 else maxOf((n ?: 0) * 60, 1)}}}"""
            else -> null
        }
    }

    /** "/poll Question? | a | b": 2..6 options of at least 2 characters (kick.com's rule). Null = invalid. */
    fun poll(a: List<String>): Pair<String, List<String>>? {
        val p = a.joinToString(" ").split("|").map { it.trim() }
        val title = p.first()
        if (title.isEmpty() || p.size - 1 !in 2..6 || p.drop(1).any { it.length < 2 }) return null
        return title to p.drop(1)
    }

    /** A typed username as kick.com wants it: no leading "@", lowercase; null when empty. */
    fun person(raw: String?) = raw?.removePrefix("@")?.lowercase()?.ifEmpty { null }

    private fun segment(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    // session

    /** Reads the signed-in user from the page, loading kick.com first if needed. */
    suspend fun refresh() {
        if (!page("/")) return
        val (status, text) = fetch("GET", "/api/v1/user", null)
        val j = runCatching { JSONObject(text) }.getOrNull()
        user = if (status == 200) j?.optString("username").orEmpty() else ""
        slug = if (user.isEmpty()) "" else j?.optJSONObject("streamer_channel")?.optString("slug").orEmpty()
    }

    suspend fun ready(): Boolean {
        if (!signedIn) refresh()
        return signedIn
    }

    /** Drops kick.com's cookies and storage only (other sites' sessions stay). */
    fun signOut() {
        val cm = CookieManager.getInstance()
        for (url in listOf("https://kick.com", "https://web.kick.com")) {
            cm.getCookie(url)?.split(";")?.map { it.substringBefore('=').trim() }?.filter { it.isNotEmpty() }?.forEach {
                cm.setCookie(url, "$it=; Max-Age=0; Path=/")
                cm.setCookie(url, "$it=; Max-Age=0; Path=/; Domain=.kick.com")
            }
            WebStorage.getInstance().deleteOrigin(url)
        }
        cm.flush()
        web?.destroy()
        web = null
        loaded = false
        channelId = null
        user = ""
        slug = ""
        applog("chat", "kick.com session removed")
    }

    // commands

    /** One-line note for the streamer. */
    suspend fun run(cmd: String, a: List<String>): String {
        val name = if (cmd == "followers") "followonly" else cmd // kick.com's own name
        if (!ready()) return "Sign in to kick.com in Settings › App bot to use /$cmd"
        if (name == "prediction") return "Kick predictions open a dialog on kick.com; not supported yet"
        if (name == "subscribers") return "Kick has no subscriber-only mode"
        val role = mapOf("mod" to "moderators", "vip" to "vips", "og" to "ogs")[name.removePrefix("un")]
        val who = person(a.firstOrNull())
        if (role != null && who == null) return "Usage: /$name user"
        if (!page("/popout/$slug/chat")) return "kick.com chat isn't ready; try again"
        val typed = "/" + (listOf(name) + a).joinToString(" ")
        val polls = "https://kick.com/api/v2/channels/$slug/polls"
        val (method, url, body) = when (name) {
            "poll" -> {
                val p = poll(a) ?: return "Usage: /poll Question? | option 1 | option 2 (2-6 options, each at least 2 characters)"
                // ponytail: fixed 30 s duration, the only value verified.
                Triple(
                    "POST",
                    polls,
                    JSONObject().put("title", p.first).put("options", JSONArray(p.second)).put("duration", 30)
                        .put("result_display_duration", 15).toString()
                )
            }
            "polldelete" -> Triple("DELETE", polls, null) // unverified on iOS too: the captured poll had expired
            "slow", "emoteonly", "followonly" -> {
                val id = channel() ?: return "Couldn't find your kick.com channel"
                Triple("PATCH", "https://web.kick.com/api/v1/channels/$id/chat/settings", modeBody(name, a))
            }
            "clear" -> Triple("POST", "https://kick.com/api/v2/channels/$slug/chat-commands", """{"command":"clear"}""")
            "mod", "unmod", "vip", "unvip", "og", "unog" -> {
                val base = "https://kick.com/api/internal/v1/channels/$slug/community/$role"
                if (name.startsWith("un")) {
                    Triple("DELETE", "$base/${segment(who!!)}", null)
                } else {
                    Triple("POST", base, JSONObject().put("username", who).toString())
                }
            }
            else -> return type(typed) // raid, clip: no known endpoint, typed like a person (unverified)
        }
        val (status, _) = fetch(method, url, body)
        applog("chat", "kick.com /$name -> HTTP $status")
        return when {
            status in 200..299 -> "Done: $typed"
            status == 401 || status == 403 -> "kick.com session expired — sign in again in Settings"
            role != null -> "kick.com refused $typed (HTTP $status)"
            else -> type(typed)
        }
    }

    private suspend fun channel(): Int? {
        if (channelId == null) {
            channelId = runCatching { JSONObject(fetch("GET", "/api/v2/channels/$slug", null).second).optInt("id") }
                .getOrNull()?.takeIf { it > 0 }
        }
        return channelId
    }

    // page

    /** The hidden web view, on a kick.com page ("/" = any kick.com page, else the popout chat). Main thread. */
    @SuppressLint("SetJavaScriptEnabled") // the page is kick.com itself, signed in by the user; no bridge is added
    private suspend fun page(path: String): Boolean = withContext(Dispatchers.Main) {
        val w = web ?: WebView(app).also {
            it.settings.javaScriptEnabled = true
            it.settings.domStorageEnabled = true
            it.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    loaded = true
                }
            }
            web = it
        }
        val at = w.url?.toUri()
        val there = loaded && at?.host == "kick.com" && (path == "/" || at.path?.startsWith("/popout/") == true)
        if (!there) {
            loaded = false
            w.loadUrl("https://kick.com$path")
            repeat(75) { if (!loaded) delay(200) }
        }
        loaded
    }

    private fun String.toUri() = android.net.Uri.parse(this)

    private suspend fun js(code: String): String? = withContext(Dispatchers.Main) {
        val out = kotlinx.coroutines.CompletableDeferred<String?>()
        val w = web ?: return@withContext null
        w.evaluateJavascript(code) { out.complete(it) }
        out.await()
    }

    /** Runs fetch() in the page with its session token; the answer is parked in window.__ms and polled. */
    private suspend fun fetch(method: String, url: String, body: String?): Pair<Int, String> {
        val id = "r${++seq}"
        val q = JSONObject::quote
        js(
            """(function(){window.__ms=window.__ms||{};
            const tok=decodeURIComponent((document.cookie.match(/(?:^|; )session_token=([^;]*)/)||[])[1]||'');
            fetch(${q(url)},{method:${q(method)},credentials:'include',body:${if (body == null) "null" else q(body)},
              headers:{Authorization:'Bearer '+tok,Accept:'application/json','Content-Type':'application/json'}})
            .then(async r=>{window.__ms[${q(id)}]={status:r.status,text:await r.text()}})
            .catch(e=>{window.__ms[${q(id)}]={status:0,text:String(e)}});})();"""
        )
        repeat(75) {
            val raw =
                js(
                    "(function(){const v=window.__ms&&window.__ms[${q(
                        id
                    )}];if(v)delete window.__ms[${q(id)}];return v?JSON.stringify(v):null})()"
                )
            val text = raw?.takeIf { it != "null" }?.let { runCatching { JSONArray("[$it]").getString(0) }.getOrNull() }
            if (text != null) return JSONObject(text).let { it.optInt("status") to it.optString("text") }
            delay(200)
        }
        return 0 to ""
    }

    /** Types the command into the page's chat box and presses Enter. No confirmation is available. */
    private suspend fun type(text: String): String {
        val code = """(function(){const els=[...document.querySelectorAll('[contenteditable="true"]')].filter(e=>e.offsetParent!==null);
            const el=els[els.length-1];if(!el)return 'none';el.focus();document.execCommand('insertText',false,${JSONObject.quote(text)});
            el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));return 'ok';})()"""
        repeat(5) {
            if (js(code) == "\"ok\"") return "Sent $text through kick.com"
            delay(1000)
        }
        return "kick.com chat isn't ready; try again"
    }
}
