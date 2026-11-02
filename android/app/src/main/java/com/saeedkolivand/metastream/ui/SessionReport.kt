package com.saeedkolivand.metastream.ui

import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.goal.Money
import com.saeedkolivand.metastream.reach.LivePostText
import com.saeedkolivand.metastream.reach.Moment
import com.saeedkolivand.metastream.reach.SessionLog
import com.saeedkolivand.metastream.reach.SessionRecord
import java.text.DateFormat
import java.util.Date

/** One-line facts for sharing (the streamer's own copy; never posted by the app). */
internal fun reportSummary(r: SessionRecord) = listOf(
    r.title.ifEmpty { "Stream" } + " · " + DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(r.start)),
    "${LivePostText.duration(r.durationMs)} · peak ${r.peakViewers} · avg ${r.avgViewers}",
    "${r.donationCount} donations · ${Money(r.donationTotal, r.currency).display}",
    "${r.newChatters} new · ${r.returningChatters} returning chatters"
).joinToString("\n")

/**
 * The Session report (iOS SessionReportView): the streamer's private account of one stream, opened after END LIVE and from
 * Settings › Streams (both set [SessionLog.justEnded]). ponytail: one page of rows and a viewers line, not iOS's cards.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SessionReportSheet() {
    val r = SessionLog.justEnded ?: return
    val ctx = LocalContext.current
    ModalBottomSheet({ SessionLog.justEnded = null }, containerColor = Color(0xFF1C1C1E), contentColor = Color.White) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(16.dp), Arrangement.spacedBy(10.dp)) {
            Text(r.title.ifEmpty { "Stream" }, fontWeight = FontWeight.Bold, fontSize = 22.sp)
            Note(DateFormat.getDateTimeInstance(DateFormat.FULL, DateFormat.SHORT).format(Date(r.start)))
            val place = (
                r.cities.joinToString(", ") + if (r.distanceMeters >
                    0
                ) {
                    " · %.1f km".format(r.distanceMeters / 1000)
                } else {
                    ""
                }
                ).trim(' ', '·')
            Note(listOfNotNull(place.ifEmpty { null }, r.camera).joinToString(" · "))
            Section("Overview") {
                Stat("Duration", LivePostText.duration(r.durationMs))
                Stat("Viewers", "peak ${r.peakViewers} · avg ${r.avgViewers}")
                Stat("Donations", "${r.donationCount} · ${Money(r.donationTotal, r.currency).display}")
                r.topDonor?.let { Stat("Top donor", "$it ${r.topDonorDisplay.orEmpty()}") }
            }
            if (r.samples.size >= 2) {
                Section("Viewers per minute") { Line(r.samples.map { it.viewers.toFloat() }) }
            }
            if (r.moments.isNotEmpty()) {
                Section("Moments") { r.moments.forEach { Stat(LivePostText.hhmm(it.at), momentText(it)) } }
            }
            Section("Audience") {
                Stat("Chatters", "${r.chatterCounts.size} (${r.newChatters} new, ${r.returningChatters} returning)")
                if (r.trackingStarted) Note("Counting started this stream, so everyone looks new.")
                val top = r.chatterCounts.entries.sortedByDescending { it.value }.take(5)
                    .mapNotNull { (k, n) -> r.chatterNames[k]?.takeIf { it.isNotEmpty() }?.let { "$it ($n)" } }
                if (top.isNotEmpty()) Stat("Most active", top.joinToString(", "))
            }
            Section("Connection") {
                val last = r.samples.lastOrNull()
                Stat("Drops", "${last?.drops ?: 0}")
                Stat("Time down", "${last?.downSeconds ?: 0} s")
                Stat(
                    "Average bitrate",
                    "${r.samples.map {
                        it.kbps
                    }.filter { it > 0 }.average().takeIf { !it.isNaN() }?.toInt() ?: 0} kbps"
                )
            }
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
                OutlinedButton({
                    ctx.startActivity(
                        Intent.createChooser(
                            Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, reportSummary(r)),
                            null
                        )
                    )
                }) { Text("Share") }
                TextButton({
                    SessionLog.delete(r)
                    SessionLog.justEnded = null
                }) { Text("Delete this report", color = Color(0xFFFF453A)) }
            }
        }
    }
}

private fun momentText(m: Moment) = when (m.kind) {
    Moment.DONATION -> "${m.detail} from ${m.user}"
    Moment.RAID -> "Raid from ${m.user} (${m.detail})"
    else -> "Chat went wild (${m.detail})"
}

@Composable
internal fun Stat(label: String, value: String) = Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), Arrangement.SpaceBetween) {
    Text(label, color = Color.White.copy(alpha = 0.7f))
    Text(value)
}

@Composable
private fun Line(values: List<Float>) {
    val top = maxOf(values.max(), 1f)
    Canvas(Modifier.fillMaxWidth().height(120.dp)) {
        val path = Path()
        values.forEachIndexed { i, v ->
            val p = Offset(size.width * i / (values.size - 1), size.height * (1 - v / top))
            if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
        }
        drawPath(path, Color(0xFF53FC18), style = Stroke(3.dp.toPx()))
    }
    Note("Peak ${top.toInt()}")
}
