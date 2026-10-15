package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Health
import com.saeedkolivand.metastream.streaming.NetStats
import com.saeedkolivand.metastream.streaming.duration
import com.saeedkolivand.metastream.streaming.kbpsText
import com.saeedkolivand.metastream.streaming.relative
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.delay

object NetworkState {
    var open by mutableStateOf(false)
}

private val dim = Color.White.copy(alpha = 0.6f)
private val clock = SimpleDateFormat("HH:mm:ss", Locale.US)

/** Tabular digits so the figures don't jitter as they tick. */
@Composable
private fun Figure(text: String, size: TextUnit, weight: FontWeight = FontWeight.SemiBold, color: Color = Color.White) = Text(
    text,
    color = color,
    fontSize = size,
    fontWeight = weight,
    style = LocalTextStyle.current.copy(fontFeatureSettings = "tnum")
)

@Composable
private fun StatusLine(now: Long) {
    val (color, text) = when {
        !Engine.live -> Color.Gray to "Not live"
        Engine.connected -> Green to "Connected" + (NetStats.connectedSince?.let { " · ${duration(now - it)}" } ?: "")
        else -> Orange to (NetStats.downStart?.let { "Reconnecting · down ${duration(now - it)}" } ?: "Connecting")
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(color))
        Figure(text, 16.sp)
    }
}

@Composable
private fun Figures() {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.Bottom) {
        Column {
            Text("Sending", color = dim, fontSize = 12.sp)
            Figure("${kbpsText(NetStats.samples.lastOrNull()?.sentKbps ?: 0)} kbps", 22.sp, FontWeight.Bold)
        }
        Column {
            Text("Target", color = dim, fontSize = 12.sp)
            Figure("${kbpsText(Health.capKbps)} kbps", 22.sp, FontWeight.Bold)
            Figure("ceiling ${kbpsText(Health.ceilingKbps)}", 11.sp, FontWeight.Normal, dim)
        }
        Column {
            Text("Frame rate", color = dim, fontSize = 12.sp)
            Figure("${Health.fps} fps", 22.sp, FontWeight.Bold)
        }
    }
}

@Composable
private fun Session(now: Long) {
    SectionTitle("Session")
    val last = NetStats.lastDropAt?.let { relative(now - it) } ?: "none"
    Figure("Drops ${NetStats.drops} · downtime ${duration(NetStats.downtimeMs(now))} · last drop $last", 14.sp, FontWeight.Normal)
}

@Composable
private fun PathLine() {
    SectionTitle("Network")
    val flags = listOfNotNull("Metered".takeIf { NetStats.metered }, "Data Saver".takeIf { NetStats.dataSaver })
    Figure((listOf(NetStats.path) + flags).joinToString(" · "), 14.sp, FontWeight.Normal)
}

@Composable
private fun Changes() {
    SectionTitle("Bitrate changes")
    if (NetStats.changes.isEmpty()) Note("None yet.")
    NetStats.changes.forEach {
        val arrow = if (it.up) "↑" else "↓"
        Figure("${clock.format(Date(it.atMs))}  $arrow ${kbpsText(it.kbps)} kbps  ${it.why.text}", 13.sp, FontWeight.Normal)
    }
}

/** In-app view of what the connection is doing; the stream itself never shows any of this. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NetworkSheet() {
    if (!NetworkState.open) return
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = System.currentTimeMillis()
        }
    }
    ModalBottomSheet(
        { NetworkState.open = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Color(0xFF1C1C1E),
        contentColor = Color.White
    ) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            Arrangement.spacedBy(8.dp)
        ) {
            Text("Network", fontWeight = FontWeight.Bold)
            StatusLine(now)
            if (Engine.live) {
                Figures()
                NetworkChart(NetStats.samples, Health.ceilingKbps)
                Session(now)
            }
            PathLine()
            if (Engine.live) Changes() else Note("Go live to see bitrate and drops.")
        }
    }
}
