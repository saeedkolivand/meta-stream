package com.saeedkolivand.metastream.ui.settings

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
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.ActionRow
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.Secondary
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.SystemBlue
import com.saeedkolivand.metastream.core.ui.TextRow
import com.saeedkolivand.metastream.overlay.ColorTheme
import com.saeedkolivand.metastream.reach.InstagramStory
import kotlinx.coroutines.launch

/** Settings › Theme & story (iOS ThemeSettingsView): the colour theme for scene templates and the Instagram story. */
@Composable
fun ThemePage() {
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
            "Empty texts keep the layout's own wording. Test share opens Instagram with this card, without going live; add " +
                "the Link sticker there."
        } else {
            "Empty texts keep the layout's own wording. Sharing needs Instagram installed and a Meta app ID in the build."
        }
    ) {
        var tpl by remember { mutableStateOf(InstagramStory.template) }
        Choice("Layout", InstagramStory.Template.entries.map { it to it.title }, tpl) {
            tpl = it
            Prefs.put("igStoryTemplate", it.name)
        }
        var texts by remember { mutableStateOf(InstagramStory.Texts.current) }

        @Composable
        fun field(label: String, key: String, value: String, set: (String) -> InstagramStory.Texts) = TextRow(label, value, {
            Prefs.put(key, it)
            texts = set(it)
        })
        field("Live label (default LIVE)", "igStoryLive", texts.live) { InstagramStory.Texts(it, texts.soon, texts.title, texts.caption) }
        field("Live soon label (default LIVE SOON)", "igStorySoon", texts.soon) {
            InstagramStory.Texts(texts.live, it, texts.title, texts.caption)
        }
        field("Title (default: the Kick title)", "igStoryTitle", texts.title) {
            InstagramStory.Texts(texts.live, texts.soon, it, texts.caption)
        }
        field("Caption under the title", "igStoryCaption", texts.caption) { InstagramStory.Texts(texts.live, texts.soon, texts.title, it) }
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            val card = remember(tpl, theme, texts) {
                InstagramStory.card(null, "Walking through Cologne", "https://kick.com/yourname", tpl, false, texts).asImageBitmap()
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
