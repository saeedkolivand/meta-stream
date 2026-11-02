package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** iOS inset-grouped background colours. */
internal val CardColor = Color(0xFF1C1C1E)

/** iOS inset-grouped section: small grey header, then a rounded card holding the rows. No title = card alone. */
@Composable
internal fun Section(title: String?, content: @Composable () -> Unit) {
    if (title != null) {
        Text(
            title.uppercase(),
            Modifier.padding(start = 16.dp, top = 16.dp),
            color = Color.White.copy(alpha = 0.55f),
            fontSize = 13.sp
        )
    }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(CardColor).padding(horizontal = 16.dp, vertical = 12.dp),
        Arrangement.spacedBy(10.dp)
    ) { content() }
}

@Composable
internal fun Footnote(text: String) = Text(text, color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)

@Composable
internal fun SwitchRow(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label)
        Switch(checked, onChange, enabled = enabled)
    }
}

/** iOS NavigationLink row, with the Settings-style colour tile when [icon] is set. */
@Composable
internal fun NavRow(title: String, icon: Int? = null, tint: Color = Color(0xFF8E8E93), onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(7.dp)).background(tint), Alignment.Center) {
                Icon(painterResource(icon), null, Modifier.size(18.dp), tint = Color.White)
            }
            Spacer(Modifier.width(12.dp))
        }
        Text(title, Modifier.weight(1f), fontSize = 17.sp)
        Text("›", color = Color.White.copy(alpha = 0.35f), fontSize = 22.sp)
    }
}

/** Segmented picker, the Android take on iOS's inline Picker. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun <T> Choice(label: String, options: List<Pair<T, String>>, selected: T, enabled: Boolean = true, onSelect: (T) -> Unit) {
    Text(label)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (value, text) ->
            SegmentedButton(
                selected == value,
                { onSelect(value) },
                SegmentedButtonDefaults.itemShape(i, options.size),
                enabled = enabled,
                label = { Text(text, maxLines = 1, fontSize = 12.sp) }
            )
        }
    }
}

/** One radio row, for long lists such as microphones. */
@Composable
internal fun RadioRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected, onClick)
        Text(label)
    }
}
