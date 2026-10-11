package com.saeedkolivand.metastream.platforms

import com.saeedkolivand.metastream.core.applog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Credentials
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** A failed platform call; the message is shown in the Stream Manager footer, like iOS `PlatformNet.err`. */
internal class PlatformException(message: String) : Exception(message)

internal val http = OkHttpClient()
private val JSON = "application/json".toMediaType()

internal fun JSONObject.objects(key: String): List<JSONObject> = optJSONArray(key).objects()

internal fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

internal fun JSONArray?.strings(): List<String> = if (this == null) emptyList() else (0 until length()).map { optString(it) }

internal fun parseJson(text: String): Any = if (text.isBlank()) {
    JSONObject()
} else {
    runCatching { JSONTokener(text).nextValue() }.getOrNull()
        ?: JSONObject()
}

internal object Net {
    /** POST application/x-www-form-urlencoded -> JSON object. Non-2xx throws unless [allowError] (device-flow polling). */
    suspend fun form(
        url: String,
        fields: Map<String, String>,
        allowError: Boolean = false,
        basic: Pair<String, String>? = null
    ): JSONObject {
        val body = FormBody.Builder().apply { fields.forEach { (k, v) -> add(k, v) } }.build()
        val req = Request.Builder().url(url).post(body).apply {
            basic?.let { header("Authorization", Credentials.basic(it.first, it.second)) }
        }.build()
        val (code, text) = exec(req)
        // Field names only, never values or the response body: token responses are secrets.
        applog("auth", "POST ${req.url.host}${req.url.encodedPath} [${fields.keys.sorted().joinToString(",")}] -> $code")
        if (!allowError && code !in 200..299) throw PlatformException("HTTP $code: ${text.take(300)}")
        return parseJson(text) as? JSONObject ?: JSONObject()
    }

    suspend fun exec(req: Request): Pair<Int, String> = withContext(Dispatchers.IO) {
        http.newCall(req).execute().use { it.code to it.body?.string().orEmpty() }
    }
}

/**
 * The single authenticated-API factory (iOS PlatformEndpoint): base URL, token key, extra headers and a refresh
 * routine. One token refresh + retry on 401.
 */
internal class Endpoint(
    private val base: String,
    private val tokenKey: String,
    private val headers: Map<String, String> = emptyMap(),
    private val refresh: suspend () -> Unit
) {
    suspend fun call(method: String, path: String, query: Map<String, String> = emptyMap(), body: JSONObject? = null): JSONObject =
        callAny(method, path, query, body) as? JSONObject ?: JSONObject()

    suspend fun callAny(method: String, path: String, query: Map<String, String> = emptyMap(), body: JSONObject? = null): Any {
        var (code, text) = once(method, path, query, body)
        if (code == 401) {
            refreshLock.withLock { refresh() }
            once(method, path, query, body).let {
                code = it.first
                text = it.second
            }
        }
        if (code !in
            200..299
        ) {
            throw PlatformException("${path.trim('/').split('/').takeLast(2).joinToString("/")} -> HTTP $code: ${text.take(300)}")
        }
        return parseJson(text)
    }

    private suspend fun once(method: String, path: String, query: Map<String, String>, body: JSONObject?): Pair<Int, String> {
        val url = (base + path).toHttpUrl().newBuilder().apply { query.forEach { (k, v) -> addQueryParameter(k, v) } }.build()
        val payload: RequestBody? = when {
            body != null -> body.toString().toRequestBody(JSON)
            method == "GET" -> null
            else -> ByteArray(0).toRequestBody() // OkHttp rejects POST/PATCH/PUT without a body
        }
        val req = Request.Builder().url(url).method(method, payload)
            .header("Authorization", "Bearer ${TokenStore.get(tokenKey).orEmpty()}")
            .apply { headers.forEach { (k, v) -> header(k, v) } }
            .build()
        val result = try {
            Net.exec(req)
        } catch (e: CancellationException) {
            throw e
        } catch (e: java.io.IOException) {
            throw PlatformException("${e.javaClass.simpleName}: ${e.message}")
        }
        // Path + status only: response bodies can carry stream keys.
        applog("api", "$method ${url.host}${url.encodedPath} -> ${result.first}")
        return result
    }

    private companion object {
        // One refresh at a time per process: rotating refresh tokens would otherwise invalidate each other.
        val refreshLock = Mutex()
    }
}
