package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.saeedkolivand.metastream.goal.DonationHub
import com.saeedkolivand.metastream.goal.Site

/** iOS DonationSourcesSettingsView: one key per site, saved on Save; status shows whether it's connected. */
@Composable
internal fun DonationSourcesPage() {
    for (site in Site.entries) {
        Section(site.title) {
            SecretField(site.keyLabel, DonationHub.key(site)) { DonationHub.setKey(site, it) }
            Note(DonationHub.status[site].orEmpty())
            Footnote(site.help)
            when (site) {
                Site.Donofa -> {
                    SecretField("Alert widget link (optional)", DonationHub.donofaWidget(), DonationHub::setDonofaWidget)
                    Footnote("With the widget link, Donofa's own alert queue drives the alerts and its test button works here.")
                }
                Site.Reymit -> {
                    SecretField("Overlay link (optional)", DonationHub.reymitOverlay(), DonationHub::setReymitOverlay)
                    Footnote("The overlay link makes Reymit's test donation play here; real ones come through the API token.")
                }
                else -> Unit
            }
        }
    }
    Footnote(
        "Donations are counted toward the goal once, from the site's own report, and announced once. Ones found later in a site's history count but aren't announced."
    )
}

/** A hidden key field with Save; an empty save removes the key. */
@Composable
private fun SecretField(label: String, saved: String, onSave: (String) -> Unit) {
    var text by remember(saved) { mutableStateOf(saved) }
    OutlinedTextField(
        text,
        { text = it },
        Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation()
    )
    OutlinedButton({ onSave(text) }, enabled = text != saved) { Text(if (text.isEmpty()) "Remove" else "Save") }
}
