package com.saeedkolivand.metastream.reach

import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.TokenStore
import com.saeedkolivand.metastream.platforms.http
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/**
 * Minimal Telegram Bot API client for the Live post (iOS Telegram.swift). Plain text only (no parse_mode, nothing to escape).
 * The token lives in the encrypted token store ("telegramToken"), the channel in Prefs. Failures never carry the request URL,
 * so the token can't reach the log.
 */
object Telegram {
    class Failure(text: String) : Exception(text)

    private val token get() = TokenStore.get("telegramToken").orEmpty()
    private val channel get() = Prefs.string("telegramChannel", "").trim()

    suspend fun sendMessage(text: String, replyTo: Long? = null): Long {
        val p = JSONObject().put("chat_id", channel).put("text", text.take(4096))
        replyTo?.let { p.put("reply_parameters", JSONObject().put("message_id", it).put("allow_sending_without_reply", true)) }
        return messageId(call("sendMessage", p))
    }

    suspend fun editText(id: Long, text: String) {
        call("editMessageText", JSONObject().put("chat_id", channel).put("message_id", id).put("text", text.take(4096)))
    }

    suspend fun editCaption(id: Long, caption: String) {
        call("editMessageCaption", JSONObject().put("chat_id", channel).put("message_id", id).put("caption", caption.take(1024)))
    }

    suspend fun deleteMessage(id: Long) {
        call("deleteMessage", JSONObject().put("chat_id", channel).put("message_id", id))
    }

    /** Replaces the photo (or turns a text message into a photo) and sets its caption. */
    suspend fun editPhoto(id: Long, jpeg: ByteArray, caption: String) {
        val media = JSONObject().put("type", "photo").put("media", "attach://frame").put("caption", caption.take(1024))
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("chat_id", channel).addFormDataPart("message_id", "$id").addFormDataPart("media", media.toString())
            .addFormDataPart("frame", "frame.jpg", jpeg.toRequestBody("image/jpeg".toMediaType())).build()
        send("editMessageMedia", body)
    }

    /** The post was deleted by hand (or never existed): nothing left to edit or delete. */
    fun isGone(e: Throwable): Boolean {
        val t = (e as? Failure)?.message?.lowercase() ?: return false
        return listOf("message to edit not found", "message to delete not found", "message_id_invalid").any { it in t }
    }

    /** What the bot can do in the channel, in words. Posts nothing. */
    suspend fun check(): String {
        if (token.isEmpty()) return "No bot token saved"
        if (channel.isEmpty()) return "No channel set"
        return runCatching {
            val me = result(call("getMe", JSONObject()))
            val chat = result(call("getChat", JSONObject().put("chat_id", channel)))
            val name = "@" + me.optString("username", "bot")
            val title = chat.optString("title", channel)
            val member = result(call("getChatMember", JSONObject().put("chat_id", channel).put("user_id", me.getLong("id"))))
            when (member.optString("status")) {
                "creator" -> "$name can post, edit and delete in $title"
                "administrator" -> listOf("can_post_messages" to "post", "can_edit_messages" to "edit", "can_delete_messages" to "delete")
                    .filter { !member.optBoolean(it.first) }.map { it.second }
                    .let {
                        if (it.isEmpty()) {
                            "$name can post, edit and delete in $title"
                        } else {
                            "$name cannot ${it.joinToString(
                                ", "
                            )} in $title: grant it in the channel's admin settings"
                        }
                    }
                else -> "$name is not an admin of $title"
            }
        }.getOrElse { it.message ?: "failed" }
    }

    private suspend fun call(method: String, params: JSONObject) =
        send(method, params.toString().toRequestBody("application/json".toMediaType()))

    /** POSTs; returns the reply once Telegram says ok ("message is not modified" counts). A 429 throws: callers retry next tick. */
    private suspend fun send(method: String, body: RequestBody): JSONObject = withContext(Dispatchers.IO) {
        if (token.isEmpty()) throw Failure("no bot token")
        val text = try {
            http.newCall(Request.Builder().url("https://api.telegram.org/bot$token/$method").post(body).build()).execute().use {
                it.body?.string().orEmpty()
            }
        } catch (e: Exception) {
            throw Failure("network error ${e.javaClass.simpleName}") // the class only: the message can hold the URL
        }
        val o = runCatching { JSONObject(text) }.getOrNull()
        if (o?.optBoolean("ok") == true) return@withContext o
        val desc = o?.optString("description").orEmpty().ifEmpty { "unreadable reply" }
        if ("message is not modified" in desc) return@withContext o ?: JSONObject()
        throw Failure(desc)
    }

    private fun result(o: JSONObject) = o.optJSONObject("result") ?: throw Failure("unexpected reply")

    private fun messageId(o: JSONObject) = result(o).optLong("message_id", -1).takeIf { it >= 0 } ?: throw Failure("no message id in reply")
}
