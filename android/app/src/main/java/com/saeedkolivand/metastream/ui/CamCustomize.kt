package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.LiveControl

/** Pure list edit behind the reorder buttons; [to] is clamped, so moving past either end is a no-op. */
internal fun <T> List<T>.moved(from: Int, to: Int): List<T> {
    if (from !in indices || to !in indices) return this
    return toMutableList().apply { add(to, removeAt(from)) }
}

/**
 * iOS LiveControlsCustomizeView: which controls the strip shows and in what order. At least one stays on (the strip
 * would open onto nothing), and "Restore defaults" is always one tap away.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CamCustomize() {
    val order = Cam.settings.order
    fun save(next: List<LiveControl>) = Cam.update { it.copy(order = next) }
    Column(Modifier.fillMaxWidth(), Arrangement.spacedBy(2.dp)) {
        order.forEachIndexed { i, control ->
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Text(control.label)
                Row {
                    TextButton({ save(order.moved(i, i - 1)) }, enabled = i > 0) { Text("Up") }
                    TextButton({ save(order.moved(i, i + 1)) }, enabled = i < order.lastIndex) { Text("Down") }
                    TextButton({ save(order - control) }, enabled = order.size > 1) { Text("Remove") }
                }
            }
        }
        val available = LiveControl.entries.filter { it !in order }
        if (available.isNotEmpty()) {
            Text("Available", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
            FlowRow(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
                available.forEach { AssistChip({ save(order + it) }, { Text("+ ${it.label}") }) }
            }
        }
        TextButton({ save(LiveControl.defaultOrder) }) { Text("Restore defaults") }
    }
}
