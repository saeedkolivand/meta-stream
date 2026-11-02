package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.camera.Cam
import com.saeedkolivand.metastream.camera.LiveControl

/** Pure list edit behind the reorder buttons; [to] is clamped, so moving past either end is a no-op. */
internal fun <T> List<T>.moved(from: Int, to: Int): List<T> {
    if (from !in indices || to !in indices) return this
    return toMutableList().apply { add(to, removeAt(from)) }
}

/**
 * iOS LiveControlsCustomizeView: which controls the strip shows and in what order. At least one stays on (the strip would
 * open onto nothing). ponytail: up/down buttons stand in for iOS's drag handles and swipe-to-delete.
 */
@Composable
internal fun CamCustomize() {
    val order = Cam.settings.order
    fun save(next: List<LiveControl>) = Cam.update { it.copy(order = next) }
    Section("On the strip", "Move a control up or down, or remove it. At least one control stays on.") {
        order.forEachIndexed { i, control ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(control.label, Modifier.weight(1f), fontSize = 17.sp)
                TextButton({ save(order.moved(i, i - 1)) }, enabled = i > 0) { Text("↑") }
                TextButton({ save(order.moved(i, i + 1)) }, enabled = i < order.lastIndex) { Text("↓") }
                TextButton({ save(order - control) }, enabled = order.size > 1) {
                    Text(
                        "Remove",
                        color = if (order.size >
                            1
                        ) {
                            Red
                        } else {
                            Secondary
                        }
                    )
                }
            }
        }
    }
    val available = LiveControl.entries.filter { it !in order }
    if (available.isNotEmpty()) Section("Available") { available.forEach { ActionRow("⊕  ${it.label}") { save(order + it) } } }
    Section("Preview") {
        Text(if (order.isEmpty()) "Nothing shown" else order.joinToString("  ·  ") { it.label }, color = Secondary, fontSize = 13.sp)
    }
    Section(null) { ActionRow("Restore defaults") { save(LiveControl.defaultOrder) } }
}
