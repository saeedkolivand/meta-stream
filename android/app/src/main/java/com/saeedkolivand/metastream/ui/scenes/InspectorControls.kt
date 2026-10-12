package com.saeedkolivand.metastream.ui.scenes

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.overlay.Layer
import com.saeedkolivand.metastream.overlay.WidgetFonts
import com.saeedkolivand.metastream.ui.Choice
import com.saeedkolivand.metastream.ui.SwitchRow
import kotlinx.coroutines.delay

private val Presets = listOf(
    0xFFFFFFFF,
    0xFF000000,
    0xFFFF453A,
    0xFFFF9F0A,
    0xFFFFC83D,
    0xFF53FC18,
    0xFF9146FF,
    0xFF0A84FF
).map { it.toInt() }

private const val RGB = 0x00FFFFFF

/**
 * A layer's string payload read and written by its keys, falling back to the style's defaults for missing keys. The keys are
 * the stored contract (shared with iOS), so this stays correct whatever type a style field uses.
 */
internal class DataKeys(
    private val layer: Layer,
    private val defaults: Map<String, String>,
    private val set: (Map<String, String>) -> Unit
) {
    fun str(k: String) = layer.data[k] ?: defaults[k].orEmpty()
    fun num(k: String) = str(k).toFloatOrNull() ?: 0f
    fun flag(k: String) = str(k) == "true"
    fun color(k: String) = str(k).toLongOrNull()?.toInt() ?: 0xFFFFFFFF.toInt()

    fun put(k: String, v: String) = set(layer.data + (k to v))
    fun putNum(k: String, v: Float) = put(k, v.toInt().toString())
    fun putFlag(k: String, v: Boolean) = put(k, v.toString())
    fun putColor(k: String, argb: Int) = put(k, (argb.toLong() and 0xFFFFFFFFL).toString())
}

/** The slider moves a local draft; the layer is written once, when the finger lifts, because each write rebuilds the scene on stream. */
@Composable
internal fun SliderRow(label: String, value: Float, range: ClosedFloatingPointRange<Float>, format: String, onCommit: (Float) -> Unit) {
    var draft by remember(value) { mutableFloatStateOf(value) }
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
        Text(label)
        Text(format.format(draft), color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp)
    }
    Slider(draft, { draft = it }, valueRange = range, onValueChangeFinished = { onCommit(draft) })
}

@Composable
internal fun DataKeys.NumSlider(key: String, label: String, range: ClosedFloatingPointRange<Float>, unit: String = "") =
    SliderRow(label, num(key).coerceIn(range), range, "%.0f$unit") { putNum(key, it) }

@Composable
internal fun DataKeys.Flag(key: String, label: String) = SwitchRow(label, flag(key)) { putFlag(key, it) }

@Composable
internal fun DataKeys.Field(key: String, label: String, singleLine: Boolean = true, keyboard: KeyboardType = KeyboardType.Text) =
    DebouncedField(label, str(key), singleLine, keyboard) { put(key, it) }

@Composable
internal fun DataKeys.Swatches(key: String, label: String) = SwatchRow(label, color(key)) { putColor(key, it) }

@Composable
internal fun DataKeys.FontPicker() = Choice("Font", WidgetFonts.faces, str("face")) { put("face", it) }

/** Typing rewrites the scene on stream, so a keystroke waits for a pause before it is committed. */
@Composable
internal fun DebouncedField(
    label: String,
    value: String,
    singleLine: Boolean = true,
    keyboard: KeyboardType = KeyboardType.Text,
    onCommit: (String) -> Unit
) {
    var draft by remember(value) { mutableStateOf(value) }
    LaunchedEffect(draft) {
        if (draft != value) {
            delay(600)
            onCommit(draft)
        }
    }
    OutlinedTextField(
        draft,
        { draft = it },
        Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = singleLine,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard)
    )
}

/** Eight presets plus the current colour when it isn't one of them; picking keeps the current alpha so translucent fills stay so. */
@Composable
internal fun SwatchRow(label: String, argb: Int, onPick: (Int) -> Unit) {
    Text(label)
    val shown = if (Presets.any { it and RGB == argb and RGB }) Presets else Presets + argb
    Row(Modifier.horizontalScroll(rememberScrollState()), Arrangement.spacedBy(10.dp), Alignment.CenterVertically) {
        for (c in shown) {
            val on = c and RGB == argb and RGB
            Box(
                Modifier.size(32.dp).clip(CircleShape).background(Color(c or (0xFF shl 24)))
                    .border(if (on) 3.dp else 1.dp, if (on) Color.White else Color.White.copy(alpha = 0.25f), CircleShape)
                    .semantics { contentDescription = "$label ${"%06X".format(c and RGB)}" }
                    .clickable { onPick((argb and RGB.inv()) or (c and RGB)) }
            )
        }
    }
}
