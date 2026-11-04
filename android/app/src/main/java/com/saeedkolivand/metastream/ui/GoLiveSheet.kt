package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.Field
import com.saeedkolivand.metastream.core.ui.Green
import com.saeedkolivand.metastream.core.ui.Note
import com.saeedkolivand.metastream.core.ui.Orange
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.platforms.Accounts
import com.saeedkolivand.metastream.platforms.Category
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.ui.CategoryPicker
import com.saeedkolivand.metastream.ui.cleanTags
import kotlinx.coroutines.launch
import org.json.JSONObject

private data class Draft(val title: String, val category: Category?, val tags: String)

private val BRAND = mapOf("kick" to Color(0xFF53FC18), "twitch" to Color(0xFF9146FF))
private val NAME = mapOf("kick" to "Kick", "twitch" to "Twitch")

/**
 * iOS StreamInfoSheet: title, category and tags for each connected Kick/Twitch account before the stream starts,
 * prefilled with what was entered last time; only edited platforms are updated. "Ask before going live" turns it off.
 */
object GoLiveSheet {
    var open by mutableStateOf(false)

    private fun ids() = listOfNotNull("kick".takeIf { Kick.connected }, "twitch".takeIf { Twitch.connected })

    /** The GO LIVE tap: the sheet first when there's something to check, else straight live. */
    fun goLive() = if (Prefs.bool("askStreamInfo", true) && ids().isNotEmpty()) open = true else Engine.goLive()

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Sheet() {
        if (!open) return
        val ids = remember { ids() }
        val scope = rememberCoroutineScope()
        val originals = remember { ids.associateWith(::current) }
        val drafts = remember { mutableStateMapOf<String, Draft>().apply { ids.forEach { put(it, saved(it) ?: originals.getValue(it)) } } }
        val failed = remember { mutableStateMapOf<String, String>() }
        var working by remember { mutableStateOf<String?>(null) }
        var shared by remember { mutableStateOf(Prefs.bool("streamInfoShared", true)) }
        var ask by remember { mutableStateOf(Prefs.bool("askStreamInfo", true)) }
        fun edited(id: String) = drafts[id]?.let { d ->
            val o = originals.getValue(id)
            d.title != o.title || d.category != o.category || cleanTags(d.tags) != cleanTags(o.tags)
        } == true
        fun update(id: String, d: Draft) {
            drafts[id] = d
            failed.remove(id)
            // Same title and tags everywhere: the first card's copied to the others; categories stay per platform.
            if (shared && id == ids.first()) ids.drop(1).forEach { drafts[it] = drafts.getValue(it).copy(title = d.title, tags = d.tags) }
        }
        fun go() {
            ids.forEach { id -> drafts[id]?.let { save(id, it) } }
            if (failed.isNotEmpty()) { // the button now means "anyway": don't retry, just start
                open = false
                return Engine.goLive()
            }
            scope.launch {
                for (id in ids.filter(::edited)) {
                    val d = drafts.getValue(id)
                    working = id
                    if (id == "kick") {
                        Kick.apply(d.title, d.category, cleanTags(d.tags))
                    } else {
                        Twitch.apply(d.title, d.category, cleanTags(d.tags), emptyMap(), Twitch.delay, Twitch.language)
                    }
                    // mutate leaves "<Platform> ... updated" on success, the error text otherwise.
                    if (!Accounts.status.endsWith("updated")) failed[id] = Accounts.status
                }
                working = null
                if (failed.isEmpty()) {
                    open = false
                    Engine.goLive()
                }
            }
        }
        ModalBottomSheet({ if (working == null) open = false }, containerColor = Color(0xFF1C1C1E), contentColor = Color.White) {
            Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(16.dp), Arrangement.spacedBy(14.dp)) {
                Text("Stream info", fontWeight = FontWeight.Bold)
                if (ids.size > 1) {
                    SwitchRow("Same title and tags everywhere", shared) {
                        shared = it
                        Prefs.put("streamInfoShared", it)
                        if (it) update(ids.first(), drafts.getValue(ids.first()))
                    }
                }
                for (id in ids) {
                    Card(id, drafts.getValue(id), edited(id), failed[id], editsText = !(shared && ids.size > 1 && id != ids.first())) {
                        update(id, it)
                    }
                }
                SwitchRow("Ask before going live", ask) {
                    ask = it
                    Prefs.put("askStreamInfo", it)
                }
                if (failed.isNotEmpty()) Text("Some changes didn't save. You can still go live.", color = Orange)
                Button(
                    ::go,
                    Modifier.fillMaxWidth().heightIn(min = 54.dp),
                    enabled = working == null,
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(if (failed.isEmpty()) Green else Orange, Color.Black)
                ) {
                    Text(
                        working?.let { "Saving to ${NAME[it]}…" }
                            ?: if (failed.isNotEmpty()) {
                                "Go live anyway"
                            } else if (ids.any(::edited)) {
                                "Save and go live"
                            } else {
                                "Go live"
                            },
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }

    @Composable
    private fun Card(id: String, d: Draft, edited: Boolean, failure: String?, editsText: Boolean, onChange: (Draft) -> Unit) {
        val brand = BRAND.getValue(id)
        Column(
            Modifier.fillMaxWidth().background(brand.copy(alpha = 0.08f), RoundedCornerShape(16.dp)).padding(14.dp),
            Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(10.dp).background(brand, CircleShape))
                Text("  " + NAME.getValue(id), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                if (edited) Text("Edited", color = brand)
            }
            if (editsText) {
                Field("Title (${d.title.length}/140)", d.title, { onChange(d.copy(title = it.take(140))) }, singleLine = false)
            } else {
                Note("Title and tags: ${d.title}")
            }
            CategoryPicker(d.category, if (id == "kick") Kick::search else Twitch::search) { onChange(d.copy(category = it)) }
            if (editsText) Field("Tags, comma separated", d.tags, { onChange(d.copy(tags = it)) })
            failure?.let { Text(it, color = Orange) }
        }
    }

    private fun current(id: String) = if (id == "kick") {
        Draft(Kick.title, Kick.category, Kick.tags.joinToString(", "))
    } else {
        Draft(Twitch.title, Twitch.category, Twitch.tags.joinToString(", "))
    }

    /** What was entered last time, restored as the next prefill. */
    private fun saved(id: String): Draft? = runCatching {
        val o = JSONObject(Prefs.string("lastStreamInfo.$id").ifEmpty { return null })
        val cat = o.optString("categoryId").ifEmpty { null }?.let { Category(it, o.optString("categoryName")) }
        Draft(o.getString("title"), cat, o.optString("tags"))
    }.getOrNull()

    private fun save(id: String, d: Draft) = Prefs.put(
        "lastStreamInfo.$id",
        JSONObject().put(
            "title",
            d.title
        ).put("categoryId", d.category?.id ?: "").put("categoryName", d.category?.name ?: "").put("tags", d.tags).toString()
    )
}
