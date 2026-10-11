package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.saeedkolivand.metastream.chat.Emotes
import com.saeedkolivand.metastream.chat.Run
import com.saeedkolivand.metastream.chat.tokenize

// Square slot at 1.5x the text size: providers return wildly different native sizes, so one fixed slot keeps every emote
// the same height next to body text (iOS resizes to a fixed height too).
private val EMOTE_SLOT = Placeholder(1.5.em, 1.5.em, PlaceholderVerticalAlign.TextCenter)

/** A chat line with Kick and 7TV/BTTV/FFZ emotes drawn inline as images (Coil) through InlineTextContent. */
@Composable
internal fun MessageText(text: String, size: Int, modifier: Modifier = Modifier) {
    val byName = Emotes.byName
    val runs = remember(text, byName) { tokenize(text, byName) }
    val (annotated, inline) = remember(runs) {
        val content = mutableMapOf<String, InlineTextContent>()
        val built = buildAnnotatedString {
            for (run in runs) {
                when (run) {
                    is Run.Text -> append(run.text)
                    is Run.Emote -> {
                        appendInlineContent(run.url, run.name)
                        content.getOrPut(run.url) {
                            InlineTextContent(EMOTE_SLOT) { alt -> AsyncImage(run.url, alt) }
                        }
                    }
                }
            }
        }
        built to content.toMap()
    }
    Text(annotated, modifier, color = Color.White, fontSize = size.sp, lineHeight = (size * 1.3f).sp, inlineContent = inline)
}
