package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
internal fun Section(title: String, content: @Composable () -> Unit) {
    Text(
        title.uppercase(),
        Modifier.padding(top = 12.dp),
        color = Color.White.copy(alpha = 0.6f),
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold
    )
    content()
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

/** iOS NavigationLink row. */
@Composable
internal fun NavRow(title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp), Arrangement.SpaceBetween) {
        Text(title)
        Text("›", color = Color.White.copy(alpha = 0.5f))
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
