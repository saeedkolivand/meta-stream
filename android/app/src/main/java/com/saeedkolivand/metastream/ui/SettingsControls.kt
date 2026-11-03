package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R

/** iOS inset-grouped colours. */
internal val CardColor = Color(0xFF1C1C1E)
internal val Secondary = Color(0xFF8E8E93)
private val SwitchOff = Color(0xFF39393D)
private val SwitchOn = Color(0xFF34C759)

/**
 * iOS inset-grouped section: grey header, a rounded card whose rows are split by hairlines (each row at least 44 dp,
 * centred), and a grey [footer] under the card. No title = card alone.
 */
@Composable
internal fun Section(title: String?, footer: String? = null, content: @Composable () -> Unit) {
    Column {
        if (title != null) {
            Text(title.uppercase(), Modifier.padding(start = 16.dp, top = 16.dp, bottom = 6.dp), color = Secondary, fontSize = 13.sp)
        }
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(CardColor).padding(start = 16.dp, end = 16.dp)) {
            Rows(content)
        }
        if (footer != null) Text(footer, Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), color = Secondary, fontSize = 13.sp)
    }
}

/** Children stacked as list rows: min 44 dp, vertically centred, a hairline between visible ones (iOS Form rows). */
@Composable
private fun Rows(content: @Composable () -> Unit) {
    val lines = remember { ArrayList<Int>() }
    Layout(
        content,
        Modifier.fillMaxWidth().drawWithContent {
            drawContent()
            lines.forEach { y ->
                drawLine(Hairline, Offset(0f, y.toFloat()), Offset(size.width + 16.dp.toPx(), y.toFloat()), 0.5.dp.toPx())
            }
        }
    ) { ms, c ->
        val min = 44.dp.roundToPx()
        val pad = 8.dp.roundToPx()
        val ps = ms.map { it.measure(c.copy(minHeight = 0, maxHeight = Int.MAX_VALUE)) }.filter { it.height > 0 }
        val heights = ps.map { maxOf(min, it.height + pad) }
        layout(c.maxWidth, heights.sum()) {
            lines.clear()
            var y = 0
            ps.forEachIndexed { i, p ->
                if (i > 0) lines += y
                p.place(0, y + (heights[i] - p.height) / 2)
                y += heights[i]
            }
        }
    }
}

/** A grey explanatory line inside a card (iOS puts most of these in the section footer instead). */
@Composable
internal fun Footnote(text: String) = Text(text, color = Secondary, fontSize = 13.sp)

/** iOS UISwitch: green when on, a full-size white thumb both ways. */
@Composable
internal fun IosSwitch(checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true) = Switch(
    checked,
    onChange,
    enabled = enabled,
    thumbContent = {},
    colors = SwitchDefaults.colors(
        checkedTrackColor = SwitchOn,
        checkedThumbColor = Color.White,
        checkedBorderColor = Color.Transparent,
        uncheckedTrackColor = SwitchOff,
        uncheckedThumbColor = Color.White,
        uncheckedBorderColor = Color.Transparent
    )
)

@Composable
internal fun SwitchRow(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = if (enabled) Color.White else Secondary, fontSize = 17.sp)
        IosSwitch(checked, onChange, enabled)
    }
}

/** iOS NavigationLink row, with the Settings-style colour tile when [icon] is set and a grey [value] before the chevron. */
@Composable
internal fun NavRow(title: String, icon: Int? = null, tint: Color = Secondary, value: String = "", badge: Int = 0, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(7.dp)).background(tint), Alignment.Center) {
                Icon(painterResource(icon), null, Modifier.size(18.dp), tint = Color.White)
            }
            Spacer(Modifier.width(12.dp))
        }
        Text(title, Modifier.weight(1f), fontSize = 17.sp, maxLines = 1)
        if (value.isNotEmpty()) Text(value, Modifier.padding(start = 8.dp), color = Secondary, fontSize = 17.sp, maxLines = 1)
        if (badge > 0) {
            Text(
                "$badge",
                Modifier.padding(start = 8.dp).clip(RoundedCornerShape(50)).background(Orange).padding(horizontal = 7.dp, vertical = 1.dp),
                color = Color.Black,
                fontSize = 12.sp
            )
        }
        Text("  ›", color = Color.White.copy(alpha = 0.3f), fontSize = 22.sp)
    }
}

/** iOS LabeledContent: a label and a grey value on one row. */
@Composable
internal fun ValueRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), fontSize = 17.sp)
        Text(value, color = Secondary, fontSize = 17.sp, maxLines = 1)
    }
}

/** iOS labeledSlider: the label and its value on one line, the slider under them, all one row. */
@Composable
internal fun SliderRow(
    label: String,
    valueText: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    enabled: Boolean = true,
    steps: Int = 0,
    onChange: (Float) -> Unit
) {
    Column(Modifier.fillMaxWidth().padding(top = 6.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(label, Modifier.weight(1f), color = if (enabled) Color.White else Secondary, fontSize = 17.sp)
            Text(valueText, color = Secondary, fontSize = 17.sp)
        }
        Slider(
            value.coerceIn(range),
            onChange,
            enabled = enabled && range.endInclusive > range.start,
            valueRange = range,
            steps = steps,
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = SystemBlue,
                inactiveTrackColor = Color(0xFF3A3A3C),
                activeTickColor = Color.Transparent,
                inactiveTickColor = Color.Transparent
            )
        )
    }
}

/** iOS Stepper: the label, then a grey − | + pill stepping [value] by [step] inside [range]. */
@Composable
internal fun Stepper(label: String, value: Int, range: IntRange, step: Int = 1, enabled: Boolean = true, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = if (enabled) Color.White else Secondary, fontSize = 17.sp)
        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(Color(0xFF3A3A3C)), verticalAlignment = Alignment.CenterVertically) {
            val down = enabled && value - step >= range.first
            val up = enabled && value + step <= range.last
            Text(
                "−",
                Modifier.clickable(down) {
                    onChange(value - step)
                }.padding(horizontal = 14.dp, vertical = 4.dp),
                color = if (down) Color.White else Secondary,
                fontSize = 20.sp
            )
            Box(Modifier.size(1.dp, 18.dp).background(Hairline))
            Text(
                "+",
                Modifier.clickable(up) {
                    onChange(value + step)
                }.padding(horizontal = 14.dp, vertical = 4.dp),
                color = if (up) Color.White else Secondary,
                fontSize = 20.sp
            )
        }
    }
}

/** iOS Form Button: a full-width blue (or red) text row. */
@Composable
internal fun ActionRow(text: String, enabled: Boolean = true, destructive: Boolean = false, onClick: () -> Unit) = Text(
    text,
    Modifier.fillMaxWidth().clickable(enabled, onClick = onClick).padding(vertical = 4.dp),
    color = if (!enabled) {
        Secondary
    } else if (destructive) {
        Red
    } else {
        SystemBlue
    },
    fontSize = 17.sp
)

/** iOS Form TextField / SecureField: borderless, the label as its placeholder. */
@Composable
internal fun TextRow(
    placeholder: String,
    value: String,
    onChange: (String) -> Unit,
    enabled: Boolean = true,
    secure: Boolean = false,
    singleLine: Boolean = true,
    keyboard: KeyboardType = KeyboardType.Text,
    mono: Boolean = false
) = BasicTextField(
    value,
    onChange,
    Modifier.fillMaxWidth(),
    enabled = enabled,
    singleLine = singleLine,
    maxLines = if (singleLine) 1 else 6,
    textStyle = TextStyle(
        color = if (enabled) Color.White else Secondary,
        fontSize = if (mono) 13.sp else 17.sp,
        fontFamily = if (mono) androidx.compose.ui.text.font.FontFamily.Monospace else null
    ),
    keyboardOptions = KeyboardOptions(keyboardType = if (secure) KeyboardType.Password else keyboard),
    visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
    cursorBrush = SolidColor(SystemBlue),
    decorationBox = { inner ->
        Box {
            if (value.isEmpty()) Text(placeholder, color = Color.White.copy(alpha = 0.3f), fontSize = if (mono) 13.sp else 17.sp)
            inner()
        }
    }
)

/** iOS menu Picker: the label, the picked value in grey with ⌃⌄; a tap opens the list with a check on the current one. */
@Composable
internal fun <T> Choice(label: String, options: List<Pair<T, String>>, selected: T, enabled: Boolean = true, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().clickable(enabled) { open = true }, verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = if (enabled) Color.White else Secondary, fontSize = 17.sp)
        Box {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(options.firstOrNull { it.first == selected }?.second.orEmpty(), color = Secondary, fontSize = 17.sp, maxLines = 1)
                Icon(painterResource(R.drawable.ic_updown), null, Modifier.padding(start = 4.dp).size(14.dp), tint = Secondary)
            }
            DropdownMenu(open, { open = false }, containerColor = Color(0xFF2C2C2E)) {
                options.forEach { (v, text) ->
                    DropdownMenuItem(
                        { Text(text, fontSize = 17.sp) },
                        {
                            open = false
                            onSelect(v)
                        },
                        leadingIcon = { Text(if (v == selected) "✓" else "", Modifier.width(16.dp), color = Color.White) }
                    )
                }
            }
        }
    }
}

/** iOS .pickerStyle(.segmented): a grey track with the picked segment raised as a lighter pill. */
@Composable
internal fun <T> Segmented(options: List<Pair<T, String>>, selected: T, enabled: Boolean = true, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(Color(0xFF2C2C2E)).padding(2.dp)) {
        options.forEach { (value, text) ->
            val on = selected == value
            Text(
                text,
                Modifier.weight(1f).clip(RoundedCornerShape(7.dp)).background(if (on) Color(0xFF636366) else Color.Transparent)
                    .clickable(enabled) { onSelect(value) }.padding(vertical = 6.dp),
                color = if (enabled) Color.White else Secondary,
                fontSize = 13.sp,
                fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
        }
    }
}

/** One check row of an inline iOS picker (long lists such as microphones or themes). */
@Composable
internal fun RadioRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), fontSize = 17.sp)
        if (selected) Text("✓", color = SystemBlue, fontSize = 17.sp)
    }
}
