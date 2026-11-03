package com.saeedkolivand.metastream.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.goal.DonatePage
import com.saeedkolivand.metastream.reach.SessionRecord
import com.saeedkolivand.metastream.reach.WrappedBuilder
import com.saeedkolivand.metastream.reach.WrappedStore
import kotlinx.coroutines.launch

/**
 * Review a month's Wrapped before it goes public (iOS WrappedReviewView): switches and per-row exclusions edit what is sent;
 * nothing is published until Publish. ponytail: shares the page link, not iOS's rendered share card.
 */
@Composable
internal fun WrappedReview(month: String, records: List<SessionRecord>, close: () -> Unit) {
    val base = remember(month) { WrappedBuilder.build(month, records, WrappedStore.lang) } ?: return Note("No streams this month")
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var distance by remember { mutableStateOf(true) }
    var cities by remember { mutableStateOf(true) }
    var moment by remember { mutableStateOf(true) }
    var total by remember { mutableStateOf(Prefs.bool("telegramShowTotal", true)) }
    val excluded = remember { mutableStateListOf<String>() }
    var published by remember { mutableStateOf(month in WrappedStore.months(WrappedStore.PUBLISHED)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val names = excluded.map { it.drop(2) }
    // Exactly what Publish sends. An excluded name must not come back through the best moment's label ("€40 from Ali").
    val draft = base.copy(
        km = base.km.takeIf { distance },
        cities = if (cities) base.cities else emptyList(),
        donations = base.donations.takeIf { total },
        topChatters = base.topChatters.filter { "c:${it.first}" !in excluded },
        topDonors = base.topDonors.filter {
            "d:${it.first}" !in
                excluded
        },
        bestMoment = base.bestMoment.takeIf { m -> moment && names.none { m != null && it in m.second } }
    )
    fun run(work: suspend () -> String?, done: () -> Unit) {
        busy = true
        error = null
        scope.launch {
            error = work()
            busy = false
            if (error == null) done()
        }
    }
    TextButton(close) { Text("‹ Streams") }
    Text(WrappedStore.monthName(month) + " Wrapped")
    Section("Include") {
        SwitchRow("Include distance", distance) { distance = it }
        SwitchRow("Include cities", cities) { cities = it }
        SwitchRow("Include donation total", total) { total = it }
        SwitchRow("Include best moment", moment) { moment = it }
    }
    Section("Will be published") {
        Stat("Streams", "${draft.streams}")
        Stat("Hours", "%.1f".format(draft.hours))
        draft.km?.let { Stat("Distance", "%.1f km".format(it)) }
        if (draft.cities.isNotEmpty()) Stat("Cities", draft.cities.joinToString(", "))
        Stat("Peak viewers", "${draft.peakViewers}")
        Stat("Average viewers", "${draft.avgViewers}")
        Stat("New chatters", "${draft.newChatters}")
        draft.donations?.let { Stat("Donations", "${it.first} · ${it.second}") }
        draft.bestMoment?.let { Stat("Best moment", it.second) }
    }
    for ((title, prefix, rows) in listOf(
        Triple("Top chatters", "c:", base.topChatters.map { it.first to "${it.second}" }),
        Triple("Top donors", "d:", base.topDonors)
    )) {
        if (rows.isEmpty()) continue
        Section(title) {
            rows.forEach { (name, value) ->
                SwitchRow("$name · $value", prefix + name !in excluded) { on ->
                    if (on) {
                        excluded.remove(prefix + name)
                    } else {
                        excluded.add(
                            prefix + name
                        )
                    }
                }
            }
        }
    }
    if (!DonatePage.hasToken) Note("Set the donate page key in Settings › Goal first", Color(0xFFFF9F0A))
    error?.let { Note(it, Color(0xFFFF453A)) }
    Button(
        { run({ WrappedStore.publish(draft) }) { WrappedStore.add(month, WrappedStore.PUBLISHED).also { published = true } } },
        enabled =
        !busy && DonatePage.hasToken
    ) {
        Text(if (published) "Publish again" else "Publish")
    }
    if (published) {
        val link = WrappedStore.pageLink(month)
        OutlinedButton({ ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) }) { Text("Open the page") }
        OutlinedButton({
            ctx.startActivity(
                Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link), null)
            )
        }) {
            Text("Share link")
        }
        TextButton({
            run({ WrappedStore.withdraw(month) }) { WrappedStore.remove(month, WrappedStore.PUBLISHED).also { published = false } }
        }, enabled = !busy) {
            Text("Withdraw", color = Color(0xFFFF453A))
        }
    }
    TextButton({
        WrappedStore.add(month, WrappedStore.DISMISSED)
        close()
    }) { Text("Not this month") }
}
