package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.chat.displayText
import com.saeedkolivand.metastream.speech.Speaker

@Composable
internal fun ChatPanel(modifier: Modifier) {
    val events by ChatFeed.chat.collectAsStateWithLifecycle()
    val list = rememberLazyListState()
    LaunchedEffect(events.lastOrNull()) { if (events.isNotEmpty()) list.scrollToItem(events.lastIndex) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(ChatFeed.kickSlug, ChatFeed::setKick, Modifier.weight(1f), label = {
                Text("Kick channel")
            }, singleLine = true)
            OutlinedTextField(ChatFeed.twitchChannel, ChatFeed::setTwitch, Modifier.weight(1f), label = {
                Text("Twitch channel")
            }, singleLine = true)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Switch(Speaker.readAloud, Speaker::updateReadAloud)
            Text("Read chat aloud", Modifier.padding(top = 12.dp))
        }
        LazyColumn(Modifier.fillMaxWidth().weight(1f), list) {
            items(events) { e ->
                Text(
                    buildAnnotatedString {
                        withStyle(SpanStyle(color = if (e.platform == "kick") Color(0xFF2BB600) else Color(0xFF9146FF))) { append(e.user) }
                        append(": ${displayText(e.text)}")
                    }
                )
            }
        }
    }
}
