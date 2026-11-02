package com.saeedkolivand.metastream.ui

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
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.core.Prefs
import com.saeedkolivand.metastream.overlay.ColorTheme
import com.saeedkolivand.metastream.reach.InstagramStory
import com.saeedkolivand.metastream.streaming.Engine
import kotlinx.coroutines.launch

/** Settings › Theme & story (iOS ThemeSettingsView): the colour theme for scene templates and the Instagram story. */
@Composable
internal fun ThemePage() {
    var theme by remember { mutableStateOf(ColorTheme.current) }
    Section("Theme") {
        for (t in ColorTheme.entries) {
            ThemeRow(t, t == theme) {
                theme = t
                ColorTheme.select(t)
            }
        }
    }
    Footnote(
        "The theme colours the scene templates and the Instagram story. Changing it doesn't recolour scenes you already " +
            "made from a template; re-apply the template for that."
    )
    val scope = rememberCoroutineScope()
    Section("Instagram story") {
        val ctx = LocalContext.current
        val ready = remember { InstagramStory.available(ctx) }
        var tpl by remember { mutableStateOf(InstagramStory.template) }
        Choice("Card", InstagramStory.Template.entries.map { it to it.title }, tpl) {
            tpl = it
            Prefs.put("igStoryTemplate", it.name)
        }
        Button({
            scope.launch { InstagramStory.share(ctx) }
        }, enabled = ready) { Text(if (Engine.live) "Share to Instagram story" else "Share \"live soon\" story") }
        OutlinedButton({ scope.launch { InstagramStory.share(ctx, test = true) } }, enabled = ready) { Text("Test share") }
        Footnote(
            if (ready) {
                "Opens Instagram's story editor with the card (a frame of the stream while live). Add the Link sticker in the empty lower part."
            } else {
                "Needs Instagram installed and the Meta app ID in the build."
            }
        )
    }
}

/** Name, Persian name and the five swatches, like the iOS picker row. */
@Composable
private fun ThemeRow(t: ColorTheme, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected, onClick)
        Column(Modifier.weight(1f)) {
            Text(t.title)
            Text(t.faName, color = Color.White.copy(alpha = 0.55f), fontSize = 13.sp)
        }
        Row(Modifier.padding(end = 4.dp), Arrangement.spacedBy(3.dp)) {
            for (c in listOf(t.bg, t.surface, t.text, t.muted, t.accent)) {
                Box(Modifier.size(14.dp).background(Color(c), CircleShape).border(0.5.dp, Color.White.copy(alpha = 0.4f), CircleShape))
            }
        }
    }
}
