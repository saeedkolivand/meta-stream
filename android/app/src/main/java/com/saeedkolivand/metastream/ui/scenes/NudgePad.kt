package com.saeedkolivand.metastream.ui.scenes

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Four arrows that move the selected widget 2 px a press, repeating while held. */
@Composable
internal fun NudgePad(modifier: Modifier, nudge: (Float, Float) -> Unit) {
    val scope = rememberCoroutineScope()
    val now by rememberUpdatedState(nudge)
    val grid = listOf(
        Triple(1, 0, "▲" to (0f to -2f)),
        Triple(0, 1, "◀" to (-2f to 0f)),
        Triple(2, 1, "▶" to (2f to 0f)),
        Triple(
            1,
            2,
            "▼" to (0f to 2f)
        )
    )
    Box(modifier.padding(6.dp).size(84.dp)) {
        for ((col, row, key) in grid) {
            val (glyph, step) = key
            Text(
                glyph,
                Modifier.offset(28.dp * col, 28.dp * row).size(28.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape)
                    .wrapContentSize().pointerInput(Unit) {
                        awaitEachGesture {
                            awaitFirstDown()
                            val job = scope.launch {
                                now(step.first, step.second)
                                delay(400)
                                while (true) {
                                    now(step.first, step.second)
                                    delay(60)
                                }
                            }
                            waitForUpOrCancellation()
                            job.cancel()
                        }
                    },
                color = Color.White,
                fontSize = 12.sp
            )
        }
    }
}
