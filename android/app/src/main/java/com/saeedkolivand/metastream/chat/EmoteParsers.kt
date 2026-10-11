package com.saeedkolivand.metastream.chat

import com.saeedkolivand.metastream.platforms.objects
import org.json.JSONArray
import org.json.JSONObject

// Response shapes (verified against the live APIs by the iOS port):
//   7TV   /v3/emote-sets/global -> {"emotes":[{"name","data":{"host":{"url","files":[...]}}}]}
//         /v3/users/twitch/{id}  -> {"emote_set":{"emotes":[...same...]}}
//   BTTV  /3/cached/emotes/global -> [{"id","code"}]; /3/cached/users/twitch/{id} -> {"channelEmotes":[..],"sharedEmotes":[..]}
//   FFZ   /v1/set/global -> {"default_sets":[Int],"sets":{"<id>":{"emoticons":[{"name","urls":{"1","2","4"}}]}}}
//         /v1/room/id/{id} -> {"room":{"set":Int},"sets":{...}}

/** One piece of a chat line: plain text, or an emote image. */
sealed interface Run {
    data class Text(val text: String) : Run

    data class Emote(val url: String, val name: String) : Run
}

private val kickEmote = Regex("""\[emote:(\d+):([^\]]*)]""")

/**
 * Splits a message into text/emote runs: Kick's inline `[emote:id:name]` tokens first (unambiguous), then any
 * whitespace-delimited word exactly matching a name in [byName]. Case-sensitive, whole-word only, like every chat client.
 */
fun tokenize(text: String, byName: Map<String, String>): List<Run> {
    val runs = mutableListOf<Run>()
    var last = 0
    for (m in kickEmote.findAll(text)) {
        runs += wordRuns(text.substring(last, m.range.first), byName)
        runs += Run.Emote("https://files.kick.com/emotes/${m.groupValues[1]}/fullsize", m.groupValues[2])
        last = m.range.last + 1
    }
    return runs + wordRuns(text.substring(last), byName)
}

private fun wordRuns(text: String, byName: Map<String, String>): List<Run> {
    if (text.isEmpty()) return emptyList()
    val runs = mutableListOf<Run>()
    val buffer = StringBuilder()
    fun flush() {
        if (buffer.isNotEmpty()) runs += Run.Text(buffer.toString())
        buffer.clear()
    }
    // Keep the original spacing around words so "a  b" and emote-adjacent text read the same as typed.
    for ((i, word) in text.split(' ').withIndex()) {
        val url = byName[word]
        if (url != null) {
            if (i > 0) buffer.append(' ') // the space before an emote stays with the text
            flush()
            runs += Run.Emote(url, word)
        } else {
            if (i > 0) buffer.append(' ')
            buffer.append(word)
        }
    }
    flush()
    return runs
}

/** 7TV emote list -> name to URL. Uses `static_name`, a genuinely single-frame WebP, so animated emotes stay still. */
internal fun sevenTvEmotes(emotes: JSONArray?): Map<String, String> = buildMap {
    for (e in emotes.objects()) {
        val host = e.optJSONObject("data")?.optJSONObject("host") ?: continue
        val files = host.optJSONArray("files").objects()
        val file = files.firstOrNull { it.optString("name") == "2x.webp" } ?: files.firstOrNull { it.optString("name") == "1x.webp" }
        val static = file?.optString("static_name").orEmpty()
        if (e.has("name") && static.isNotEmpty()) put(e.optString("name"), "https:${host.optString("url")}/$static")
    }
}

/** BTTV serves the image straight off `/emote/{id}/2x` with no extension; the content type comes from the response. */
internal fun bttvEmotes(emotes: List<JSONObject>): Map<String, String> = emotes.filter { it.has("code") && it.has("id") }.associate {
    it.optString("code") to
        "https://cdn.betterttv.net/emote/${it.optString("id")}/2x"
}

internal fun ffzEmotes(json: JSONObject, setIds: List<Int>): Map<String, String> = buildMap {
    val sets = json.optJSONObject("sets") ?: return@buildMap
    for (id in setIds) {
        for (e in sets.optJSONObject("$id")?.objects("emoticons").orEmpty()) {
            val urls = e.optJSONObject("urls") ?: continue
            val url = listOf("2", "1").firstNotNullOfOrNull { urls.optString(it).ifEmpty { null } } ?: continue
            put(e.optString("name"), if (url.startsWith("//")) "https:$url" else url) // FFZ urls are protocol-relative
        }
    }
}
