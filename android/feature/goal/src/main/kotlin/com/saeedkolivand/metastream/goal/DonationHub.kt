package com.saeedkolivand.metastream.goal

import androidx.compose.runtime.mutableStateMapOf
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.logging.applog
import com.saeedkolivand.metastream.core.model.ChatEvent
import com.saeedkolivand.metastream.core.model.Kind
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.core.network.http
import com.saeedkolivand.metastream.core.network.parseJson
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.storage.TokenStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray

enum class Site(val title: String, val keyLabel: String, val help: String) {
    Donofa("Donofa", "API key", "Find it in your Donofa panel under API settings."),
    Reymit("Reymit", "API token", "Find it in Reymit under Settings › Miscellaneous (متفرقه)."),
    StreamElements(
        "StreamElements",
        "JWT token",
        "Dashboard › your profile › Account › Channels › Show secrets (it resets about every two weeks)."
    ),
    Donito("Donito", "Overlay link", "Donito › Overlays: copy any overlay's link.");

    val id get() = name.lowercase()
}

enum class Outcome { Ok, Rejected, Unreachable }

/** A WebSocket as a frame channel for a coroutine: closes when the socket ends; [close] on the way out. */
class Ws(request: Request) {
    val frames = Channel<String>(Channel.UNLIMITED)
    private val ws = http.newWebSocket(
        request,
        object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                frames.trySend(text)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                frames.close()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                frames.close()
            }
        }
    )

    fun send(s: String) = ws.send(s)

    fun close() = ws.cancel()
}

/**
 * Donation sites (iOS DonationHub, adr/0006): Donofa (socket + history), Reymit and StreamElements (polled, SE also live),
 * Donito (socket). A donation is recorded in the goal BEFORE it is announced, so one reported twice is announced once;
 * ones found in a site's history are recorded as missed and never announced. Main thread; HTTP on IO.
 */
object DonationHub {
    val status = mutableStateMapOf<Site, String>().apply { Site.entries.forEach { put(it, "Not set up") } }
    const val REJECTED = "Key rejected — paste a new one"
    val backoff = listOf(2L, 5L, 10L, 30L)
    lateinit var scope: CoroutineScope
    private val jobs = HashMap<Site, List<Job>>()
    private val lastAt = HashMap<Site, Long>()
    private val logged = HashMap<Site, String>()

    fun key(site: Site) = TokenStore.get("donationKey.${site.id}").orEmpty()

    fun setKey(site: Site, raw: String) {
        var k = raw.trim()
        // Donito: the overlay link's last path part is the token.
        if (site == Site.Donito && k.startsWith("http")) k = k.substringBefore('?').trimEnd('/').substringAfterLast('/')
        storeKey("donationKey.${site.id}", k)
        lastAt.remove(site)
        run(site)
    }

    fun reymitOverlay() = TokenStore.get("donationKey.reymitOverlay").orEmpty()

    fun setReymitOverlay(link: String) {
        storeKey("donationKey.reymitOverlay", link.trim())
        run(Site.Reymit)
    }

    fun donofaWidget() = TokenStore.get("donationKey.donofaWidget").orEmpty()

    fun setDonofaWidget(link: String) {
        storeKey("donationKey.donofaWidget", link.trim())
        run(Site.Donofa)
    }

    fun storeKey(name: String, value: String) = if (value.isEmpty()) TokenStore.remove(name) else TokenStore.set(name, value)

    fun start(scope: CoroutineScope) {
        this.scope = scope
        Site.entries.forEach(::run)
    }

    /** (Re)starts one site; "Not set up" without a key. */
    fun run(site: Site) {
        jobs.remove(site)?.forEach { it.cancel() }
        val k = key(site)
        val overlay = if (site == Site.Reymit) reymitOverlay() else "" // Reymit's overlay link works without the API token
        if (k.isEmpty() && overlay.isEmpty()) return setStatus(site, "Not set up")
        setStatus(site, "Connecting…")
        jobs[site] = when (site) {
            Site.Donito -> listOf(scope.launch { runDonito(k) })
            Site.Donofa -> listOf(scope.launch { runDonofa(k) })
            Site.Reymit -> listOfNotNull(
                overlay.takeIf { it.isNotEmpty() }?.let { scope.launch { runReymitOverlay(it) } },
                k.takeIf { it.isNotEmpty() }?.let {
                    scope.launch {
                        poll(site, 10) {
                            val (o, j) = get(
                                "https://api.reymit.ir/user/${java.net.URLEncoder.encode(it, "UTF-8")}/donates/last-donates",
                                null,
                                setOf(401, 403, 404)
                            )
                            o to DonationParse.items(j).mapNotNull { d -> DonationParse.parse(d, Shape.reymit) }
                        }
                    }
                }
            ).also { if (k.isEmpty()) setStatus(site, "No API token (overlay only)") }
            Site.StreamElements -> listOf(scope.launch { runStreamElements(k) }, scope.launch { pollStreamElements(k) })
        }
    }

    private suspend fun pollStreamElements(k: String) {
        var channel = ""
        poll(Site.StreamElements, 15) {
            if (channel.isEmpty()) {
                val (o, j) = get("https://api.streamelements.com/kappa/v2/channels/me", "Bearer $k", setOf(401, 403))
                if (o != Outcome.Ok) return@poll o to emptyList()
                channel = (j as? org.json.JSONObject)?.optString("_id").orEmpty().ifEmpty { return@poll Outcome.Unreachable to emptyList() }
                seChannel = channel
            }
            val (o, j) = get("https://api.streamelements.com/kappa/v2/tips/$channel?limit=25&sort=-createdAt", "Bearer $k", setOf(401, 403))
            o to DonationParse.items(j).mapNotNull(DonationParse::parseStreamElements)
        }
    }

    var seChannel = ""

    /** The first successful poll is catch-up (unknown ids are missed); later polls are live. A rejected key ends it. */
    private suspend fun poll(site: Site, seconds: Int, fetch: suspend () -> Pair<Outcome, List<Parsed>>) {
        var first = true
        while (true) {
            val (o, items) = fetch()
            when (o) {
                Outcome.Rejected -> return setStatus(site, REJECTED)
                Outcome.Unreachable -> setStatus(site, "Can't reach ${site.title}")
                Outcome.Ok -> {
                    val n = ingest(site, items, live = !first)
                    if (first || n > 0) applog("goal", "${site.id} poll ok: ${items.size} donations, $n new")
                    first = false
                    setStatus(site, connectedText(site))
                }
            }
            delay(seconds * 1000L)
        }
    }

    /** True the first time a site reports an id (newest 500 kept across launches): "new" means new to the site's feed. */
    private fun firstSighting(site: Site, id: String): Boolean {
        val ids = runCatching { JSONArray(Prefs.string("donationSeen.${site.id}", "[]")) }.getOrDefault(JSONArray())
        val list = (0 until ids.length()).map { ids.getString(it) }
        if (id in list) return false
        Prefs.put("donationSeen.${site.id}", JSONArray((list + id).takeLast(500)).toString())
        return true
    }

    /** Record first, announce only what was new. */
    fun ingest(site: Site, items: List<Parsed>, live: Boolean, announce: Boolean = true): Int {
        var new = 0
        for (p in items.sortedBy { it.date }) {
            val key = "${site.id}:${p.id}"
            when (p.state) {
                Parsed.State.Pending -> continue
                Parsed.State.Refunded -> {
                    GoalStore.refund(key)
                    continue
                }
                Parsed.State.Paid -> Unit
            }
            val isLive = live && firstSighting(site, p.id)
            val at = if (isLive) System.currentTimeMillis() else p.date // some sites' timestamps have an unknown zone
            lastAt[site] = maxOf(lastAt[site] ?: 0, at)
            val note = listOf(p.name, p.message).filter { it.isNotEmpty() }.joinToString(" · ")
            if (GoalStore.record(key, site.id, p.money, at, missed = !isLive, note = note)) {
                if (isLive &&
                    announce
                ) {
                    ChatFeed.onChat(ChatEvent(site.id, p.name, p.message, kind = Kind.Tip, money = p.money, msgId = p.id))
                }
                new++
            }
        }
        return new
    }

    /** A site's test donation plays the alert but is never recorded. */
    fun announceTest(site: Site, name: String, message: String, amount: Any?, currency: String) {
        val a = DonationParse.decimal(amount)?.takeIf { it.signum() > 0 } ?: return
        applog("goal", "${site.id} test donation announced")
        ChatFeed.onChat(ChatEvent("test-donation", name.ifEmpty { "Someone" }, message, kind = Kind.Tip, money = Money.of(a, currency)))
    }

    /** Logs each status change once (the "· last donation" tail ignored). */
    fun setStatus(site: Site, text: String) {
        status[site] = text
        val head = text.substringBefore(" ·")
        if (logged[site] != head) applog("goal", "${site.id}: $head")
        logged[site] = head
    }

    fun connectedText(site: Site): String {
        val t = lastAt[site] ?: return "Connected"
        val mins = maxOf(1, (System.currentTimeMillis() - t) / 60_000)
        return "Connected · last donation " +
            if (mins < 60) {
                "$mins min ago"
            } else if (mins < 2880) {
                "${mins / 60} h ago"
            } else {
                "${mins / 1440} d ago"
            }
    }

    /** GET as JSON; [reject] are the codes that mean the key is wrong, other failures are "unreachable". */
    suspend fun get(url: String, auth: String?, reject: Set<Int>): Pair<Outcome, Any?> = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder().url(url).header("Accept", "application/json").apply {
                auth?.let { header("Authorization", it) }
            }.build()
            http.newCall(req).execute().use { r ->
                when {
                    r.code in reject -> Outcome.Rejected to null
                    !r.isSuccessful -> {
                        applog("goal", "donation site HTTP ${r.code} for ${r.request.url.host}")
                        Outcome.Unreachable to null
                    }
                    else -> Outcome.Ok to parseJson(r.body?.string().orEmpty())
                }
            }
        }.getOrDefault(Outcome.Unreachable to null)
    }

    /** Reconnects [session] with backoff until it reports a rejected key; true from [session] = it connected. */
    suspend fun reconnecting(site: Site, report: Boolean = true, session: suspend () -> Pair<Boolean, Boolean>) {
        var attempt = 0
        while (scope.isActive) {
            val (rejected, connected) = session()
            if (rejected) return
            if (connected) {
                attempt = 0
            } else if (report) {
                setStatus(site, "Can't reach ${site.title}")
            }
            delay(backoff[minOf(attempt, backoff.size - 1)] * 1000)
            attempt++
        }
    }
}
