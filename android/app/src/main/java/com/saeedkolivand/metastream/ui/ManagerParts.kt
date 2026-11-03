package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.ui.TextRow

/** Small building blocks shared by the Stream Manager and read-aloud settings. */
@Composable
internal fun SectionTitle(title: String) = Text(
    title.uppercase(),
    Modifier.padding(top = 12.dp),
    color = Color.White.copy(alpha = 0.6f),
    fontSize = 12.sp,
    fontWeight = FontWeight.SemiBold
)

@Composable
internal fun Note(text: String, color: Color = Color.White.copy(alpha = 0.6f)) = Text(text, color = color, fontSize = 12.sp)

@Composable
internal fun Field(label: String, value: String, onChange: (String) -> Unit, singleLine: Boolean = true) =
    TextRow(label, value, onChange, singleLine = singleLine)

/** A button that greys out until its Twitch write scope was granted (no tap-time 401). */
@Composable
internal fun ActionButton(label: String, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) =
    Button(onClick, modifier, enabled = enabled) { Text(label) }
