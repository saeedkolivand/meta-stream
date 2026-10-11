package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.platforms.Account
import com.saeedkolivand.metastream.platforms.Category
import com.saeedkolivand.metastream.platforms.Kick
import com.saeedkolivand.metastream.platforms.Restream
import com.saeedkolivand.metastream.platforms.Twitch
import com.saeedkolivand.metastream.platforms.YouTube
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

internal fun cleanTags(raw: String) = raw.split(',').map(String::trim).filter(String::isNotEmpty)

@Composable
private fun CategoryPicker(selected: Category?, search: suspend (String) -> List<Category>, onPick: (Category) -> Unit) {
    var q by remember { mutableStateOf("") }
    var results by remember { mutableStateOf(emptyList<Category>()) }
    // Debounced so typing doesn't fire a request per keystroke.
    LaunchedEffect(q) {
        if (q.isBlank()) {
            results = emptyList()
        } else {
            delay(300)
            results = search(q)
        }
    }
    Text("Category: ${selected?.name ?: "—"}")
    Field("Search category…", q, { q = it })
    for (c in results) {
        TextButton({
            onPick(c)
            q = ""
        }) { Text(c.name + if (c == selected) "  ✓" else "") }
    }
}

@Composable
private fun Choice(options: List<Pair<String, String>>, value: String, onPick: (String) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()), Arrangement.spacedBy(8.dp)) {
        for ((id, label) in options) FilterChip(value == id, { onPick(id) }, { Text(label) })
    }
}

@Composable
private fun Stepper(label: String, value: Int, step: Int, range: IntRange, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton({ onChange((value - step).coerceAtLeast(range.first)) }, enabled = value > range.first) { Text("−") }
            OutlinedButton({ onChange((value + step).coerceAtMost(range.last)) }, enabled = value < range.last) { Text("+") }
        }
    }
}

@Composable
private fun ApplyButton(label: String, enabled: Boolean, apply: suspend () -> Unit) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    Button({
        busy = true
        scope.launch {
            apply()
            busy = false
        }
    }, Modifier.fillMaxWidth(), enabled = enabled && !busy) { Text(if (busy) "Applying…" else label) }
}

/** The editable stream-info form for [account]; drafts reset whenever the loaded values change (refresh/apply). */
@Composable
internal fun InfoSection(account: Account) {
    when (account) {
        Kick -> KickInfo()
        Twitch -> TwitchInfo()
        Restream -> RestreamInfo()
        YouTube -> YouTubeInfo()
        else -> Unit
    }
}

@Composable
private fun KickInfo() {
    var title by remember(Kick.title) { mutableStateOf(Kick.title) }
    var category by remember(Kick.category) { mutableStateOf(Kick.category) }
    var tags by remember(Kick.tags) { mutableStateOf(Kick.tags.joinToString(", ")) }
    Field("Title", title, { title = it }, singleLine = false)
    CategoryPicker(category, Kick::search) { category = it }
    Field("Tags, comma separated", tags, { tags = it })
    ApplyButton("Apply changes", title.isNotEmpty()) { Kick.apply(title, category, cleanTags(tags)) }
}

@Composable
private fun TwitchInfo() {
    var title by remember(Twitch.title) { mutableStateOf(Twitch.title) }
    var category by remember(Twitch.category) { mutableStateOf(Twitch.category) }
    var tags by remember(Twitch.tags) { mutableStateOf(Twitch.tags.joinToString(", ")) }
    var language by remember(Twitch.language) { mutableStateOf(Twitch.language) }
    var delay by remember(Twitch.delay) { mutableStateOf(Twitch.delay) }
    val options = Twitch.labelOptions
    var labels by remember(Twitch.labels, options) { mutableStateOf(options.associate { (id, _) -> id to (id in Twitch.labels) }) }
    Field("Title", title, { title = it }, singleLine = false)
    CategoryPicker(category, Twitch::search) { category = it }
    Field("Tags, comma separated", tags, { tags = it })
    Field("Language (e.g. en)", language, { language = it })
    Stepper("Stream delay: ${delay}s", delay, 15, 0..900) { delay = it }
    for ((id, name) in options) ToggleRow(name, labels[id] == true) { labels = labels + (id to it) }
    Note("Stream delay is Partner-only; Twitch ignores or errors it otherwise. It's the anti-stream-sniping delay, worth it for IRL.")
    ApplyButton("Apply changes", title.isNotEmpty()) { Twitch.apply(title, category, cleanTags(tags), labels, delay, language) }
}

@Composable
private fun RestreamInfo() {
    var title by remember(Restream.title) { mutableStateOf(Restream.title) }
    Field("Title", title, { title = it }, singleLine = false)
    ApplyButton("Apply title to all destinations", title.isNotEmpty()) { Restream.apply(title) }
}

@Composable
private fun YouTubeInfo() {
    var title by remember(YouTube.title) { mutableStateOf(YouTube.title) }
    var description by remember(YouTube.description) { mutableStateOf(YouTube.description) }
    var privacy by remember(YouTube.privacy) { mutableStateOf(YouTube.privacy) }
    var latency by remember(YouTube.latency) { mutableStateOf(YouTube.latency) }
    Field("Title", title, { title = it }, singleLine = false)
    Field("Description", description, { description = it }, singleLine = false)
    Choice(listOf("public" to "Public", "unlisted" to "Unlisted", "private" to "Private"), privacy) { privacy = it }
    Choice(listOf("normal" to "Normal", "low" to "Low", "ultraLow" to "Ultra-low"), latency) { latency = it }
    ApplyButton("Apply changes", title.isNotEmpty()) { YouTube.apply(title, description, privacy, latency) }
}
