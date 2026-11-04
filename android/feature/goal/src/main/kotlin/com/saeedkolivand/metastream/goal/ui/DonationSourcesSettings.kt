package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SystemBlue
import com.saeedkolivand.metastream.core.ui.TextRow
import com.saeedkolivand.metastream.goal.DonationHub
import com.saeedkolivand.metastream.goal.Site

/** iOS DonationSourcesSettingsView: one card row per site (status, secure key, help, Save). */
@Composable
internal fun DonationSourcesPage() {
    Section(
        "Donation sources",
        "Donations are counted toward the goal once, from the site's own report, and announced once. Ones found later in a " +
            "site's history count but aren't announced."
    ) {
        for (site in Site.entries) {
            Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(site.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                DonationHub.status[site]?.takeIf { it.isNotEmpty() }?.let { Text(it, color = Secondary, fontSize = 13.sp) }
                SecretField(site.keyLabel, DonationHub.key(site), site.help) { DonationHub.setKey(site, it) }
                when (site) {
                    Site.Donofa -> SecretField(
                        "Widget link (alerts)",
                        DonationHub.donofaWidget(),
                        "Paste a Donofa widget or widget-group link. Donofa then sends its alerts here (one at a time, like in " +
                            "OBS); real donations still count through your API key.",
                        DonationHub::setDonofaWidget
                    )
                    Site.Reymit -> SecretField(
                        "Overlay link (test alerts)",
                        DonationHub.reymitOverlay(),
                        "Paste the Reymit overlay link. Reymit's test button only reaches the overlay; tests play the alert and never count.",
                        DonationHub::setReymitOverlay
                    )
                    else -> Unit
                }
            }
        }
    }
}

/** A hidden key field, its help and Save (iOS SiteKeyRow); an empty save removes the key. */
@Composable
private fun SecretField(label: String, saved: String, help: String, onSave: (String) -> Unit) {
    var text by remember(saved) { mutableStateOf(saved) }
    TextRow(label, text, { text = it }, secure = true)
    Text(help, color = Secondary, fontSize = 13.sp)
    Text(
        if (text.isEmpty() && saved.isNotEmpty()) "Remove" else "Save",
        Modifier.clickable(text != saved) { onSave(text) }.padding(vertical = 6.dp),
        color = if (text != saved) SystemBlue else Secondary,
        fontSize = 17.sp
    )
}
