package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.overlay.ANIMATED_ROWS

private val SIZES = listOf(16, 20, 26, 32)

@Composable
private fun Header(step: Int, resize: (Int) -> Unit, maximized: Boolean, onMaximize: () -> Unit) {
    val haptic = rememberHaptic()
    fun tap(action: () -> Unit) = {
        haptic(false)
        action()
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        TextButton(tap { resize(step - 1) }, enabled = step > 0) { Text("A−", fontSize = 16.sp, color = Color.White) }
        TextButton(tap { resize(step + 1) }, enabled = step < SIZES.lastIndex) { Text("A+", fontSize = 20.sp, color = Color.White) }
        Spacer(Modifier.weight(1f))
        IconButton(tap(onMaximize)) {
            Icon(
                painterResource(if (maximized) R.drawable.ic_fullscreen_exit else R.drawable.ic_fullscreen),
                "Resize chat",
                tint = Color.White
            )
        }
    }
}

/** Sheet contents; [ChatSheet] owns the surface, sizing and dragging. */
@Composable
internal fun ChatPanel(sheet: SheetArgs, onSettings: () -> Unit) {
    // Default one step above system size: chat is read at a glance from a phone mounted on a dash.
    var step by remember { mutableIntStateOf(Prefs.string("chatTextSize", "1").toIntOrNull()?.coerceIn(0, SIZES.lastIndex) ?: 1) }
    val size = SIZES[step]
    fun resize(to: Int) {
        step = to.coerceIn(0, SIZES.lastIndex)
        Prefs.put("chatTextSize", step.toString())
    }
    val maximized = sheet.detent == Detent.Expanded
    val toggle = { sheet.onDetent(if (maximized) Detent.Partial else Detent.Expanded) }
    ChatSheet(sheet, { Header(step, ::resize, maximized, toggle) }) {
        if (!ChatFeed.configured) {
            Column(
                Modifier.fillMaxSize().padding(16.dp),
                Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
                Alignment.CenterHorizontally
            ) {
                Text("No chat source set", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                Text(
                    "Set a channel name in Settings, or connect a platform in Stream Manager.",
                    fontSize = 14.sp,
                    color = Color.White.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onSettings) { Text("Settings") }
                    Button({ ManagerState.open = true }) { Text("Stream Manager") }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                MessageList(size, Modifier.weight(1f))
                ComposeBar(maximized) { sheet.onDetent(Detent.Expanded) }
            }
        }
    }
}

/** The only composable that reads the message list, so a new message recomposes just this and not the panel around it. */
@Composable
private fun MessageList(size: Int, modifier: Modifier) {
    val events by ChatFeed.chat.collectAsStateWithLifecycle()
    val list = rememberLazyListState()
    // Follow new messages only while the bottom is on screen; scrolled up to read history = stay put.
    // The layout still reflects the previous list here, so canScrollForward says where the user was.
    LaunchedEffect(events.size) {
        if (events.isNotEmpty() && !list.canScrollForward) list.scrollToItem(events.lastIndex)
    }
    LazyColumn(modifier, list) {
        // Keyed rows stay put when the 200-message cap drops the oldest: positions don't resettle per message.
        // Only the newest rows animate their emotes, same as the stream widget.
        val live = events.takeLast(ANIMATED_ROWS).map { it.id }.toSet()
        items(events, key = { it.id }) { ChatRow(it, size, it.id in live) }
    }
}
