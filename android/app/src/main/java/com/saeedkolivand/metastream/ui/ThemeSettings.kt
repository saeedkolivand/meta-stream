package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.overlay.ColorTheme
import com.saeedkolivand.metastream.reach.InstagramStory
import kotlinx.coroutines.launch

/** Settings › Theme & story (iOS ThemeSettingsView): the colour theme for scene templates and the Instagram story. */
@Composable
internal fun ThemePage() {
    var theme by remember { mutableStateOf(ColorTheme.current) }
    Section(
        "Theme",
        "The theme colours the scene templates and the Instagram story. Changing it doesn't recolour scenes you already " +
            "made from a template; re-apply the template for that."
    ) {
        for (t in ColorTheme.entries) {
            ThemeRow(t, t == theme) {
                theme = t
                ColorTheme.select(t)
            }
        }
    }
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    val ready = remember { InstagramStory.available(ctx) }
    Section(
        "Instagram story",
        if (ready) {
            "Opens Instagram with this card, without going live. Add the Link sticker there."
        } else {
            "Needs Instagram installed and a Meta app ID in the build."
        }
    ) {
        var tpl by remember { mutableStateOf(InstagramStory.template) }
        Choice("Layout", InstagramStory.Template.entries.map { it to it.title }, tpl) {
            tpl = it
            Prefs.put("igStoryTemplate", it.name)
        }
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            val card = remember(tpl, theme) {
                InstagramStory.card(null, "Walking through Cologne", "https://kick.com/yourname", tpl, false).asImageBitmap()
            }
            Image(card, null, Modifier.size(180.dp, 320.dp))
            Text("Preview without a stream frame", Modifier.padding(top = 8.dp), color = Secondary, fontSize = 13.sp)
        }
        ActionRow("Test share to Instagram", ready) { scope.launch { InstagramStory.share(ctx, test = true) } }
    }
}

/** Name, Persian name and the five swatches, like the iOS inline picker row (check on the picked one). */
@Composable
private fun ThemeRow(t: ColorTheme, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(t.title, fontSize = 17.sp)
            Text(t.faName, color = Secondary, fontSize = 13.sp)
        }
        Row(Modifier.padding(end = 8.dp), Arrangement.spacedBy(3.dp)) {
            for (c in listOf(t.bg, t.surface, t.text, t.muted, t.accent)) {
                Box(Modifier.size(14.dp).background(Color(c), CircleShape).border(0.5.dp, Color.White.copy(alpha = 0.4f), CircleShape))
            }
        }
        Text(if (selected) "✓" else "", Modifier.size(20.dp), color = SystemBlue, fontSize = 17.sp)
    }
}
