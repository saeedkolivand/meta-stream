package com.saeedkolivand.metastream.core.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.storage.Prefs

/** Small form building blocks the feature settings pages share: titles, notes, fields, Prefs-backed rows. */
@Composable
fun SectionTitle(title: String) = Text(
    title.uppercase(),
    Modifier.padding(top = 12.dp),
    color = Color.White.copy(alpha = 0.6f),
    fontSize = 12.sp,
    fontWeight = FontWeight.SemiBold
)

@Composable
fun Note(text: String, color: Color = Color.White.copy(alpha = 0.6f)) = Text(text, color = color, fontSize = 12.sp)

@Composable
fun Field(label: String, value: String, onChange: (String) -> Unit, singleLine: Boolean = true) =
    TextRow(label, value, onChange, singleLine = singleLine)

/** A button that greys out until its Twitch write scope was granted (no tap-time 401). */
@Composable
fun ActionButton(label: String, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) =
    Button(onClick, modifier, enabled = enabled) { Text(label) }

/** A Prefs-backed switch. */
@Composable
fun PrefSwitch(label: String, key: String, default: Boolean, enabled: Boolean = true) {
    var on by remember(key) { mutableStateOf(Prefs.bool(key, default)) }
    SwitchRow(label, on, enabled) {
        on = it
        Prefs.put(key, it)
    }
}

/** A Prefs-backed text field; an emptied template saves "" and so posts nothing. */
@Composable
fun PrefField(label: String, key: String, default: String) {
    var text by remember(key) { mutableStateOf(Prefs.string(key, default)) }
    Field(label, text, {
        text = it
        Prefs.put(key, it)
    })
}
