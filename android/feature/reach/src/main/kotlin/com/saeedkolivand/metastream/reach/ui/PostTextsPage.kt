package com.saeedkolivand.metastream.reach.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.TextRow
import com.saeedkolivand.metastream.reach.LivePostText
import com.saeedkolivand.metastream.reach.LivePostText.Kind

/**
 * Settings › Telegram › Post texts (iOS PostTextsView): each post's template, its placeholders and a preview. A template
 * left as the built-in one is stored as "" so it keeps following the language setting.
 */
@Composable
fun PostTextsPage() {
    val lang = remember { Prefs.string("telegramLang", "fa") }
    var kind by remember { mutableStateOf(Kind.Live) }
    val default = LivePostText.default(kind, lang)
    var text by remember(kind) { mutableStateOf(LivePostText.stored(kind) ?: default) }
    fun save(t: String) {
        text = t
        Prefs.put(kind.pref, if (t == default) "" else t)
    }
    Section(
        null,
        "An empty placeholder hides its line; put optional parts in [ ], like [ · {title}]. Goal, donations, moments and " +
            "chatters come worded in the post language."
    ) {
        Choice("Post", Kind.entries.map { it to it.title }, kind) { kind = it }
        TextRow("Template", text, ::save, singleLine = false, maxLines = 12)
    }
    if (kind.keys.isNotEmpty()) {
        Section("Placeholders") { Text(kind.keys.joinToString("  ") { "{$it}" }, fontSize = 15.sp) }
    }
    Section("Preview", "Made-up values; the real post fills in the stream's.") {
        Text(LivePostText.preview(kind, lang, text), fontSize = 15.sp)
    }
    Section(null) { ActionRow("Reset to default", text != default, destructive = true) { save(default) } }
}
