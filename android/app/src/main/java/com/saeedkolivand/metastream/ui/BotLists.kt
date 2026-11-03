package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AssistChip
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.bot.BotCommand
import com.saeedkolivand.metastream.bot.BotTimer
import com.saeedkolivand.metastream.bot.send
import kotlinx.coroutines.launch

private val DESTINATIONS = listOf("all" to "Both", "kick" to "Kick", "twitch" to "Twitch")

/** Settings › App bot › Timers: text, minutes, remove; saved on every edit. */
@Composable
internal fun TimersEditor() {
    var list by remember { mutableStateOf(BotTimer.stored()) }
    fun edit(next: List<BotTimer>) {
        list = next
        BotTimer.save(next)
    }
    list.forEachIndexed { i, t ->
        OutlinedTextField(t.text, { v -> edit(list.toMutableList().also { it[i] = t.copy(text = v) }) }, Modifier.fillMaxWidth(), label = {
            Text("Timer ${i + 1}")
        })
        Stepper("Every ${t.minutes} min", t.minutes, 5..240, 5) { m -> edit(list.toMutableList().also { it[i] = t.copy(minutes = m) }) }
        TextButton({ edit(list.filterIndexed { j, _ -> j != i }) }) { Text("Remove timer") }
    }
    TextButton({ edit(list + BotTimer("")) }) { Text("Add timer") }
}

/** Settings › App bot › Saved commands: the chips above the chat input. */
@Composable
internal fun CommandsEditor() {
    var list by remember { mutableStateOf(BotCommand.stored()) }
    fun edit(next: List<BotCommand>) {
        list = next
        BotCommand.save(next)
    }
    list.forEachIndexed { i, c ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(c.text, { v ->
                edit(list.toMutableList().also { it[i] = c.copy(text = v) })
            }, Modifier.weight(1f), singleLine = true)
            TextButton({ edit(list.filterIndexed { j, _ -> j != i }) }) { Text("Remove") }
        }
        Choice("Send to", DESTINATIONS, c.destination) { d -> edit(list.toMutableList().also { it[i] = c.copy(destination = d) }) }
    }
    TextButton({ edit(list + BotCommand("")) }) { Text("Add command") }
    Footnote("Sent as you, so other bots (BotRix, Nightbot) obey them. A /command runs on each platform instead of posting.")
}

/** One tap sends a saved command (iOS ChatSheetView's command strip); [onNote] gets a slash command's outcome. */
@Composable
internal fun BotCommandsBar(onNote: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val list = remember { BotCommand.stored().filter { it.text.isNotBlank() } }
    if (list.isEmpty()) return
    Row(Modifier.horizontalScroll(rememberScrollState()), Arrangement.spacedBy(8.dp)) {
        for (c in list) AssistChip({ scope.launch { c.send().takeIf { it.isNotEmpty() }?.let(onNote) } }, { Text(c.text) })
    }
}
