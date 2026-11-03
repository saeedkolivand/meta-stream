package com.saeedkolivand.metastream.remote

import androidx.compose.runtime.snapshotFlow
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Recording
import java.net.NetworkInterface
import java.net.ServerSocket
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Remote control (iOS ObsServer, adr/0004): a subset of the obs-websocket v5 server, so Stream Deck, Touch Portal and
 * Streamer.bot drive the app as if it were OBS. Local network peers only, behind a password of 8+ characters; 8 clients,
 * 2 logging in at once, 10 s to log in, and a failed login locks new connections out for 2 s. Protocol work is on main.
 * ponytail: JSON only (no msgpack), no studio mode, no per-input audio beyond Mic, unknown requests answer 204.
 */
object ObsServer {
    const val PORT = 4455
    private const val CHARS = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private val supported = listOf(
        "GetVersion", "GetSceneList", "GetCurrentProgramScene", "SetCurrentProgramScene", "GetStudioModeEnabled", "GetStreamStatus",
        "StartStream", "StopStream", "ToggleStream", "GetRecordStatus", "StartRecord", "StopRecord", "ToggleRecord", "GetInputList",
        "GetInputMute", "SetInputMute", "ToggleInputMute", "TriggerMediaInputAction", "GetHotkeyList"
    )

    private class Client(val ws: WsConn) {
        val challenge = random()
        val salt = random()
        var ok = false
        var alive = true
        var subs = 2047 // OBS default: everything but high-volume events
    }

    private val rng = SecureRandom()
    private val clients = ArrayList<Client>() // main thread
    private var server: ServerSocket? = null
    private var jobs = ArrayList<Job>()
    private var lastFail = 0L
    private lateinit var scope: CoroutineScope
    private val password get() = Prefs.string("obsPassword", "")

    private fun random() = Base64.getEncoder().encodeToString(ByteArray(32).also(rng::nextBytes))

    fun randomPassword() = String(CharArray(12) { CHARS[rng.nextInt(CHARS.length)] })

    /** base64(sha256(base64(sha256(password + salt)) + challenge)), per the obs-websocket spec. */
    fun auth(pw: String, salt: String, challenge: String): String {
        fun h(s: String) = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(s.toByteArray()))
        return h(h(pw + salt) + challenge)
    }

    /** (label, ip) for each IPv4 address a controller could reach on Wi-Fi or this phone's hotspot. */
    fun addresses(): List<Pair<String, String>> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }.flatMap { i ->
            i.inetAddresses.toList().filter { it is java.net.Inet4Address && it.isSiteLocalAddress }
                .map {
                    (
                        if (i.name.startsWith("wlan")) {
                            "Wi-Fi"
                        } else if (i.name.startsWith("ap") ||
                            i.name.startsWith("swlan")
                        ) {
                            "Hotspot"
                        } else {
                            i.name
                        }
                        ) to
                        it.hostAddress.orEmpty()
                }
        }
    }.getOrDefault(emptyList())

    /** Idempotent: makes the server match the "obsServerOn" setting. At launch and when the switch changes. */
    fun sync(scope: CoroutineScope) {
        this.scope = scope
        if (Prefs.bool("obsServerOn", false)) {
            if (password.isEmpty()) Prefs.put("obsPassword", randomPassword())
            if (server == null) start()
        } else if (server != null) {
            stop()
        }
    }

    private fun start() {
        val s = runCatching { ServerSocket(PORT) }.getOrElse {
            applog("remote", "listener could not be created")
            return
        }
        server = s
        jobs += scope.launch(Dispatchers.IO) {
            while (!s.isClosed) {
                val sock = runCatching { s.accept() }.getOrNull() ?: break
                withContext(Dispatchers.Main) { accept(WsConn(sock), sock) }
            }
        }
        observe()
        applog("remote", "obs-websocket listening on $PORT")
    }

    private fun stop() {
        runCatching { server?.close() }
        server = null
        jobs.forEach { it.cancel() }
        jobs.clear()
        clients.toList().forEach { drop(it) }
        applog("remote", "obs-websocket stopped")
    }

    /** Events follow the app's state, so every path that changes it (app UI, remote, rotation) is covered. */
    private fun observe() {
        fun <T> on(read: () -> T, send: (T) -> Unit) = jobs.add(scope.launch { snapshotFlow(read).drop(1).collect(send) })
        on({ Engine.live }) { event("StreamStateChanged", 64, out(it)) }
        on({ Recording.since != null }) { event("RecordStateChanged", 64, out(it).put("outputPath", "")) }
        on({
            Engine.muted
        }) { event("InputMuteStateChanged", 8, JSONObject().put("inputName", "Mic").put("inputUuid", "Mic").put("inputMuted", it)) }
        on({ OverlayStore.scene }) { event("CurrentProgramSceneChanged", 4, JSONObject().put("sceneName", it).put("sceneUuid", it)) }
        on({ OverlayStore.scenes.map { it.name } }) { event("SceneListChanged", 4, JSONObject().put("scenes", sceneList())) }
    }

    private fun accept(ws: WsConn, sock: java.net.Socket) {
        // At most 2 clients mid-login at once, so guesses can't run in parallel; logged-in controllers don't count.
        if (!WsConn.isLocal(ws.peer) ||
            !onLan(sock) ||
            clients.size >= 8 ||
            clients.count { !it.ok } >= 2 ||
            System.currentTimeMillis() - lastFail < 2000
        ) {
            applog("remote", "connection refused (not local, too many clients, or right after a failed login)")
            return ws.close(1008)
        }
        val cl = Client(ws)
        clients += cl
        scope.launch(Dispatchers.IO) {
            sock.soTimeout = 10_000 // the upgrade must arrive quickly too
            if (!ws.handshake("obswebsocket.json")) return@launch withContext(Dispatchers.Main) { drop(cl) }
            sock.soTimeout = 0
            ws.text(
                JSONObject().put("op", 0).put(
                    "d",
                    JSONObject().put("obsWebSocketVersion", "5.5.0").put("rpcVersion", 1)
                        .put("authentication", JSONObject().put("challenge", cl.challenge).put("salt", cl.salt))
                ).toString()
            )
            applog("remote", "client connected")
            while (true) {
                val msg = ws.read() ?: break
                withContext(Dispatchers.Main) { handle(cl, msg) }
                if (!cl.alive) break
            }
            withContext(Dispatchers.Main) { drop(cl) }
        }
        // An unidentified client gets 10 s to log in, so idle sockets can't pile up.
        scope.launch {
            delay(10_000)
            if (cl.alive && !cl.ok) close(cl, 4009)
        }
    }

    /** Arrived on Wi-Fi, this phone's hotspot or loopback, never a cellular interface (a carrier address can be public). */
    private fun onLan(sock: java.net.Socket): Boolean {
        val local = sock.localAddress
        if (local.isLoopbackAddress) return true
        val name = runCatching { NetworkInterface.getByInetAddress(local)?.name }.getOrNull() ?: return false
        return listOf("wlan", "ap", "swlan", "eth").any { name.startsWith(it) }
    }

    /** The password changed: every controller logs in again with the new one. */
    fun revokeSessions() {
        if (clients.isNotEmpty()) applog("remote", "sessions revoked (password changed)")
        clients.toList().forEach { close(it, 4009) }
    }

    private fun drop(cl: Client) {
        if (!cl.alive) return
        cl.alive = false
        clients.remove(cl)
        scope.launch(Dispatchers.IO) { cl.ws.close() }
        applog("remote", "client gone")
    }

    private fun send(cl: Client, o: JSONObject) {
        val text = o.toString()
        scope.launch(Dispatchers.IO) { cl.ws.text(text) }
    }

    /** obs-websocket close codes are 4000+ (4009 authentication failed, 4007 not identified, 4002 bad message). */
    private fun close(cl: Client, code: Int) {
        cl.ok = false
        cl.alive = false
        clients.remove(cl)
        scope.launch(Dispatchers.IO) { cl.ws.close(code) }
    }

    private fun event(type: String, bit: Int, data: JSONObject) {
        for (cl in clients) {
            if (cl.ok && cl.subs and bit != 0) {
                send(
                    cl,
                    JSONObject().put("op", 5).put("d", JSONObject().put("eventType", type).put("eventIntent", bit).put("eventData", data))
                )
            }
        }
    }

    private fun handle(cl: Client, raw: String) {
        val m = runCatching { JSONObject(raw) }.getOrNull()
        val op = m?.optInt("op", -1) ?: -1
        if (op < 0) return close(cl, 4002)
        val d = m?.optJSONObject("d") ?: JSONObject()
        when (op) {
            1, 3 -> {
                if (op == 1 && (password.length < 8 || d.optString("authentication") != auth(password, cl.salt, cl.challenge))) {
                    lastFail = System.currentTimeMillis()
                    applog("remote", "authentication failed")
                    // ponytail: one guess per 2 s for everyone pending; logged-in controllers stay connected.
                    clients.filter { !it.ok && it !== cl }.forEach { close(it, 4009) }
                    return close(cl, 4009)
                }
                if (op == 3 && !cl.ok) return close(cl, 4007)
                cl.ok = true
                cl.subs = d.optInt("eventSubscriptions", 2047)
                send(cl, JSONObject().put("op", 2).put("d", JSONObject().put("negotiatedRpcVersion", 1)))
            }
            6 -> if (cl.ok) send(cl, JSONObject().put("op", 7).put("d", response(d))) else close(cl, 4007)
            8 -> if (cl.ok) {
                val reqs = d.optJSONArray("requests") ?: JSONArray()
                val results = JSONArray((0 until reqs.length()).mapNotNull { reqs.optJSONObject(it)?.let(::response) })
                send(
                    cl,
                    JSONObject().put("op", 9).put("d", JSONObject().put("requestId", d.opt("requestId") ?: "").put("results", results))
                )
            } else {
                close(cl, 4007)
            }
        }
    }

    private fun response(d: JSONObject): JSONObject {
        val type = d.optString("requestType")
        val (code, comment, data) = ObsRequests.run(type, d.optJSONObject("requestData") ?: JSONObject())
        val st = JSONObject().put("result", code == 100).put("code", code).apply { comment?.let { put("comment", it) } }
        return JSONObject().put("requestType", type).put("requestId", d.opt("requestId") ?: "").put("requestStatus", st)
            .apply { if (data.length() > 0) put("responseData", data) }
    }

    fun out(on: Boolean): JSONObject =
        JSONObject().put("outputActive", on).put("outputState", if (on) "OBS_WEBSOCKET_OUTPUT_STARTED" else "OBS_WEBSOCKET_OUTPUT_STOPPED")

    /** OBS lists scenes bottom-to-top. */
    fun sceneList() = JSONArray(
        OverlayStore.scenes.map {
            it.name
        }.reversed().mapIndexed { i, n -> JSONObject().put("sceneIndex", i).put("sceneName", n).put("sceneUuid", n) }
    )

    val requests get() = supported
}
