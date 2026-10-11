package com.saeedkolivand.metastream.platforms

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.saeedkolivand.metastream.core.applog
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Browser sign-in for the redirect flows. The system browser opens the provider's page; the redirect lands on
 * MainActivity as `metastream://oauth/...` (Kick/Restream via docs/oauth.html) or the Google custom scheme.
 * A redirect is accepted only if its `state` matches a flow we started, and only once.
 */
internal object OAuth {
    const val GOOGLE_SCHEME = "com.saeedkolivand.metastream"
    private const val TIMEOUT_MS = 10 * 60_000L
    private val pending = ConcurrentHashMap<String, CompletableDeferred<String?>>()

    /** Registers a flow expecting [state]; completed by [deliver]. */
    fun expect(state: String) = CompletableDeferred<String?>().also { pending[state] = it }

    /** Hands a redirect's [state]/[code] to the matching flow. False (and nothing happens) for an unknown or reused state. */
    fun deliver(state: String?, code: String?): Boolean {
        val flow = state?.let { pending.remove(it) }
        if (flow == null) applog("auth", "ignored redirect with unknown state")
        flow?.complete(code)
        return flow != null
    }

    /** Opens [authUrl] in the browser and waits for the redirect carrying [state]; null on denial, cancel or timeout. */
    suspend fun await(context: Context, authUrl: String, state: String): String? {
        val flow = expect(state)
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(authUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return try {
            withTimeoutOrNull(TIMEOUT_MS) { flow.await() }
        } finally {
            pending.remove(state)
        }
    }

    /** MainActivity entry point. True when [uri] was an OAuth redirect (valid or not), so callers don't treat it as anything else. */
    fun handle(uri: Uri?): Boolean {
        uri ?: return false
        val ours = (uri.scheme == "metastream" && uri.host == "oauth") || (uri.scheme == GOOGLE_SCHEME && uri.path == "/oauth2redirect")
        if (!ours) return false
        val code = if (uri.getQueryParameter("error") == null) uri.getQueryParameter("code") else null
        deliver(uri.getQueryParameter("state"), code)
        return true
    }
}
