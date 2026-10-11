package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R
import com.saeedkolivand.metastream.chat.ChatFeed
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.platforms.Accounts
import kotlinx.coroutines.launch

private val NAMES = mapOf("kick" to "Kick", "twitch" to "Twitch", "youtube" to "YouTube")

/** Compose bar with the "Send to" picker (iOS ChatSheetView.composeBar). [onFocus] lets the sheet grow above the keyboard. */
@Composable
internal fun ComposeBar(expanded: Boolean, onFocus: () -> Unit) {
    val scope = rememberCoroutineScope()
    val origins = Accounts.sendOrigins(ChatFeed.kickSlug)
    var picked by remember { mutableStateOf(Prefs.string("chatOrigin", "kick")) }
    var text by remember { mutableStateOf("") }
    var notice by remember { mutableStateOf("") }
    // Falls back to the first available origin when the saved one is not connected, like iOS sendChat.
    val target = origins.firstOrNull { it == picked } ?: origins.firstOrNull()
    fun send() {
        val t = text.trim()
        val to = target ?: return
        if (t.isEmpty()) return
        text = ""
        scope.launch {
            val before = Accounts.status
            Accounts.send(to, t)
            // Successful sends leave the status alone, so a changed status after a send is the failure reason.
            notice = if (Accounts.status != before) Accounts.status else ""
        }
    }
    val inset = if (expanded) {
        Modifier.windowInsetsPadding(
            WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)
        )
    } else {
        Modifier.imePadding()
    }
    Column(Modifier.fillMaxWidth().then(inset).padding(horizontal = 12.dp, vertical = 8.dp), Arrangement.spacedBy(6.dp)) {
        if (origins.size > 1) {
            Row(Modifier.horizontalScroll(rememberScrollState()), Arrangement.spacedBy(8.dp)) {
                for (o in origins) {
                    FilterChip(o == target, {
                        picked = o
                        Prefs.put("chatOrigin", o)
                    }, { Text(NAMES.getValue(o)) })
                }
            }
        }
        if (notice.isNotEmpty()) Text(notice, color = Orange, fontSize = 12.sp)
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                text,
                {
                    text = it
                    notice = ""
                },
                Modifier.weight(1f).onFocusChanged { if (it.isFocused) onFocus() },
                placeholder = {
                    Text(
                        if (target ==
                            null
                        ) {
                            "Connect an account in Stream Manager to send"
                        } else {
                            "Message ${NAMES.getValue(target)}"
                        }
                    )
                },
                enabled = target != null,
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { send() })
            )
            IconButton(::send, enabled = target != null && text.isNotBlank()) {
                Icon(painterResource(R.drawable.ic_send), "Send", tint = if (text.isNotBlank()) Color.White else Color.Gray)
            }
        }
    }
}
