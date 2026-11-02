package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.saeedkolivand.metastream.reach.Heatmap
import com.saeedkolivand.metastream.reach.LivePostText
import com.saeedkolivand.metastream.reach.SessionLog
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Settings › Streams (iOS StreamsView): the heatmap, then every recorded stream by month; a row opens its report. */
@Composable
internal fun StreamsPage() {
    // Re-read when the report sheet closes (a report may have been deleted there).
    val records = remember(SessionLog.justEnded) { SessionLog.all() }
    if (records.isEmpty()) return Note("No streams recorded yet")
    Section("When your viewers show up") {
        if (records.size < Heatmap.MIN_STREAMS) {
            Footnote("The best-time heatmap appears after ${Heatmap.MIN_STREAMS} streams (${records.size} so far).")
        } else {
            var metric by remember { mutableStateOf(Heatmap.Metric.Viewers) }
            Choice("Metric", Heatmap.Metric.entries.map { it to it.title }, metric) { metric = it }
            HeatGrid(Heatmap.cells(records, metric))
            Heatmap.bestSlot(records)?.let { Text("Best slot: $it") }
            Footnote("Rows Monday to Sunday, columns 0–23 h. Gray: fewer than 2 streams in that slot, not enough to compare.")
        }
    }
    val month = SimpleDateFormat("MMMM yyyy", Locale.getDefault())
    val day = SimpleDateFormat("EEE d, HH:mm", Locale.getDefault())
    for ((name, list) in records.groupBy { month.format(Date(it.start)) }) {
        Section(name) {
            for (r in list) {
                Column(Modifier.fillMaxWidth().clickable { SessionLog.justEnded = r }.padding(vertical = 8.dp)) {
                    Text(r.title.ifEmpty { "Stream" })
                    Note(
                        "${day.format(
                            Date(r.start)
                        )} · ${LivePostText.duration(r.durationMs)} · peak ${r.peakViewers} · ${r.donationCount} donations"
                    )
                }
            }
        }
    }
}

@Composable
private fun HeatGrid(cells: List<Heatmap.Cell>) {
    val top = maxOf(cells.filter { it.enough }.maxOfOrNull { it.value } ?: 0.0, 0.0001)
    val byKey = cells.associateBy { it.weekday * 24 + it.hour }
    Canvas(Modifier.fillMaxWidth().height(160.dp)) {
        val cw = size.width / 24
        val ch = size.height / 7
        for (d in 0 until 7) {
            for (h in 0 until 24) {
                val c = byKey[d * 24 + h]
                val color = when {
                    c == null -> Color.White.copy(alpha = 0.04f)
                    !c.enough -> Color.Gray.copy(alpha = 0.25f)
                    else -> Color(0xFF53FC18).copy(alpha = (0.15 + 0.85 * c.value / top).toFloat())
                }
                drawRoundRect(color, Offset(h * cw + 1, d * ch + 1), Size(cw - 2, ch - 2), CornerRadius(2f))
            }
        }
    }
}
