package com.saeedkolivand.metastream.bot.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AssistChip
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
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Red
import com.saeedkolivand.metastream.core.ui.Segmented
import com.saeedkolivand.metastream.core.ui.Stepper
import com.saeedkolivand.metastream.core.ui.TextRow
import kotlinx.coroutines.launch

private val DESTINATIONS = listOf("kick" to "Kick", "twitch" to "Twitch", "all" to "Both")

/** iOS AppBotTimersView rows: message, interval, delete; saved on every edit. */
@Composable
fun TimersEditor() {
    var list by remember { mutableStateOf(BotTimer.stored()) }
    fun edit(next: List<BotTimer>) {
        list = next
        BotTimer.save(next)
    }
    list.forEachIndexed { i, t ->
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f)) {
                    TextRow("Message", t.text, { v -> edit(list.toMutableList().also { it[i] = t.copy(text = v) }) })
                }
                TextButton({ edit(list.filterIndexed { j, _ -> j != i }) }) { Text("Delete", color = Red) }
            }
            Stepper("Every ${t.minutes} min", t.minutes, 5..120, 5) { m -> edit(list.toMutableList().also { it[i] = t.copy(minutes = m) }) }
        }
    }
    ActionRow("Add timer") { edit(list + BotTimer("")) }
}

/** iOS CommandsSettingsView rows: the command, where it goes (segmented), delete. */
@Composable
fun CommandsEditor() {
    var list by remember { mutableStateOf(BotCommand.stored()) }
    fun edit(next: List<BotCommand>) {
        list = next
        BotCommand.save(next)
    }
    list.forEachIndexed { i, c ->
        Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f)) {
                    TextRow("!command", c.text, { v -> edit(list.toMutableList().also { it[i] = c.copy(text = v) }) })
                }
                TextButton({ edit(list.filterIndexed { j, _ -> j != i }) }) { Text("Delete", color = Red) }
            }
            Segmented(DESTINATIONS, c.destination) { d -> edit(list.toMutableList().also { it[i] = c.copy(destination = d) }) }
        }
    }
    ActionRow("Add command") { edit(list + BotCommand("!", "all")) }
}

/** One tap sends a saved command (iOS ChatSheetView's command strip); [onNote] gets a slash command's outcome. */
@Composable
fun BotCommandsBar(onNote: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val list = remember { BotCommand.stored().filter { it.text.isNotBlank() } }
    if (list.isEmpty()) return
    Row(Modifier.horizontalScroll(rememberScrollState()), Arrangement.spacedBy(8.dp)) {
        for (c in list) AssistChip({ scope.launch { c.send().takeIf { it.isNotEmpty() }?.let(onNote) } }, { Text(c.text) })
    }
}
