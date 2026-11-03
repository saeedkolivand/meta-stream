package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.model.Money
import com.saeedkolivand.metastream.reach.Heatmap
import com.saeedkolivand.metastream.reach.LivePostText
import com.saeedkolivand.metastream.reach.SessionLog
import com.saeedkolivand.metastream.reach.SessionRecord
import com.saeedkolivand.metastream.reach.WrappedStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** The month being reviewed; the bar's Wrapped… menu sets it too. */
private var review by mutableStateOf<String?>(null)

/** Settings › Streams (iOS StreamsView): the Wrapped card, the heatmap, then every recorded stream by month; a row opens its report. */
@Composable
internal fun StreamsPage() {
    // Re-read when the report sheet closes (a report may have been deleted there).
    val records = remember(SessionLog.justEnded) { SessionLog.all() }
    if (records.isEmpty()) {
        return Text(
            "No streams recorded yet",
            Modifier.fillMaxWidth().padding(top = 120.dp),
            color = Secondary,
            fontSize = 17.sp
        )
    }
    review?.let { return WrappedReview(it, records) { review = null } }
    WrappedStore.pendingMonth(records)?.let { m ->
        Section(null) {
            Row(Modifier.fillMaxWidth().clickable { review = m }, verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${WrappedStore.monthName(m)} Wrapped is ready", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("Review before it goes on your page", color = Secondary, fontSize = 15.sp)
                }
                Text("›", color = Secondary, fontSize = 22.sp)
            }
        }
    }
    Section(null) {
        Column(Modifier.padding(vertical = 4.dp)) {
            Text("When your viewers show up", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            if (records.size < Heatmap.MIN_STREAMS) {
                Text(
                    "The best-time heatmap appears after ${Heatmap.MIN_STREAMS} streams (${records.size} so far)",
                    color = Secondary,
                    fontSize = 13.sp
                )
            } else {
                var metric by remember { mutableStateOf(Heatmap.Metric.Viewers) }
                Box(Modifier.padding(vertical = 10.dp)) { Segmented(Heatmap.Metric.entries.map { it to it.title }, metric) { metric = it } }
                HeatGrid(Heatmap.cells(records, metric))
                Text(
                    "Gray cells: fewer than 2 streams in that slot, not enough data to compare.",
                    Modifier.padding(top = 8.dp),
                    color = Secondary,
                    fontSize = 11.sp
                )
                Heatmap.bestSlot(records)?.let { Text("Best slot: $it", Modifier.padding(top = 6.dp), fontSize = 15.sp) }
            }
        }
    }
    val month = SimpleDateFormat("MMMM yyyy", LocalConfiguration.current.locales[0])
    for ((name, list) in records.groupBy { month.format(Date(it.start)) }) {
        Section(name) { for (r in list) StreamRow(r) }
    }
}

/** iOS StreamsView toolbar: Wrapped… picks any month's recap. */
@Composable
internal fun StreamsToolbar() = Box {
    var open by remember { mutableStateOf(false) }
    val months = remember { WrappedStore.allMonths(SessionLog.all()) }
    Text(
        "Wrapped…",
        Modifier.clickable(months.isNotEmpty()) { open = true }.padding(horizontal = 8.dp),
        color = if (months.isEmpty()) Secondary else SystemBlue,
        fontSize = 17.sp
    )
    DropdownMenu(open, { open = false }) {
        for (m in months) {
            DropdownMenuItem({ Text(WrappedStore.monthName(m)) }, {
                open = false
                review = m
            })
        }
    }
}

/** iOS StreamRow: title, day · length · donations, a viewer sparkline and the peak. */
@Composable
private fun StreamRow(r: SessionRecord) {
    val day = remember { SimpleDateFormat("EEE d MMM, HH:mm", Locale.getDefault()) }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable {
            SessionLog.justEnded = r
        },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(r.title.ifEmpty { "Untitled stream" }, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            val meta = listOfNotNull(
                day.format(Date(r.start)),
                LivePostText.duration(r.durationMs),
                Money(r.donationTotal, r.currency).display.takeIf { r.donationTotal.signum() > 0 }
            )
            Text(meta.joinToString(" · "), color = Secondary, fontSize = 13.sp, maxLines = 1)
        }
        val viewers = r.samples.map { it.viewers }
        Canvas(Modifier.padding(horizontal = 12.dp).size(64.dp, 26.dp)) {
            if (viewers.size < 2) return@Canvas
            val top = maxOf(viewers.max(), 1)
            val path = Path()
            viewers.forEachIndexed { i, v ->
                val x = size.width * i / (viewers.size - 1)
                val y = size.height * (1 - v.toFloat() / top)
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, Green, style = Stroke(1.5.dp.toPx()))
        }
        Column(Modifier.widthIn(min = 34.dp), horizontalAlignment = Alignment.End) {
            Text("${r.peakViewers}", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text("peak", color = Secondary, fontSize = 11.sp)
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
