package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.chat.Emotes
import com.saeedkolivand.metastream.chat.Run
import com.saeedkolivand.metastream.chat.tokenize
import com.saeedkolivand.metastream.overlay.EmoteBitmaps
import com.saeedkolivand.metastream.overlay.thermalHot
import kotlinx.coroutines.delay

// Square slot at 1.5x the text size: providers return wildly different native sizes, so one fixed slot keeps every emote
// the same height next to body text (iOS resizes to a fixed height too).
private val EMOTE_SLOT = Placeholder(1.5.em, 1.5.em, PlaceholderVerticalAlign.TextCenter)

// ponytail: animated emotes redraw at 10 fps and freeze on their first frame when the phone is hot.
private const val ANIM_TICK_MS = 100L

/** One emote from the shared decoder cache, so GIF/animated WebP play; a still just draws its bitmap. */
@Composable
private fun EmoteImage(url: String, alt: String, size: Int, animate: Boolean) {
    EmoteBitmaps.version.collectAsState().value // recompose when a load lands
    val px = with(LocalDensity.current) { (size * 1.5f).sp.toPx().toInt() }
    var t by remember { mutableLongStateOf(0L) }
    if (animate && EmoteBitmaps.isAnimated(url)) {
        LaunchedEffect(url) {
            while (true) {
                t = if (thermalHot()) 0L else System.currentTimeMillis()
                delay(ANIM_TICK_MS)
            }
        }
    }
    EmoteBitmaps.get(url, px, t)?.let { Image(it.asImageBitmap(), alt) }
}

/** A chat line with Kick and 7TV/BTTV/FFZ emotes drawn inline as images (EmoteBitmaps) through InlineTextContent. */
@Composable
internal fun MessageText(text: String, size: Int, modifier: Modifier = Modifier, animate: Boolean = true) {
    val byName = Emotes.byName
    val runs = remember(text, byName) { tokenize(text, byName) }
    val (annotated, inline) = remember(runs, animate) {
        val content = mutableMapOf<String, InlineTextContent>()
        val built = buildAnnotatedString {
            for (run in runs) {
                when (run) {
                    is Run.Text -> append(run.text)
                    is Run.Emote -> {
                        appendInlineContent(run.url, run.name)
                        content.getOrPut(run.url) {
                            InlineTextContent(EMOTE_SLOT) { alt -> EmoteImage(run.url, alt, size, animate) }
                        }
                    }
                }
            }
        }
        built to content.toMap()
    }
    Text(annotated, modifier, color = Color.White, fontSize = size.sp, lineHeight = (size * 1.3f).sp, inlineContent = inline)
}
