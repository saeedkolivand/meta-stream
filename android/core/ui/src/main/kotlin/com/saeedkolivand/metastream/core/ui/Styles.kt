package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// iOS system colors (dark appearance), so the two apps read the same.
internal val Green = Color(0xFF30D158)
internal val Red = Color(0xFFFF453A)
internal val Orange = Color(0xFFFF9F0A)
internal val SystemBlue = Color(0xFF0A84FF)
internal val Scrim = Color.Black.copy(alpha = 0.45f)
internal val Hairline = Color.White.copy(alpha = 0.15f)

/** Light tap for buttons, strong for GO LIVE and the quick tiles (iOS hapticTap). */
@Composable
internal fun rememberHaptic(): (Boolean) -> Unit {
    val h = LocalHapticFeedback.current
    return { strong -> h.performHapticFeedback(if (strong) HapticFeedbackType.LongPress else HapticFeedbackType.ContextClick) }
}

/** iOS StripStyles.pill: translucent capsule, colored icon, small white monospaced-digit text. */
@Composable
internal fun Pill(icon: Int, text: String, color: Color, onClick: (() -> Unit)? = null) {
    val haptic = rememberHaptic()
    val tap = if (onClick == null) {
        Modifier
    } else {
        Modifier.clickable {
            haptic(false)
            onClick()
        }
    }
    Row(
        Modifier.clip(CircleShape).background(Scrim).border(1.dp, Hairline, CircleShape).then(tap)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        Arrangement.spacedBy(6.dp),
        Alignment.CenterVertically
    ) {
        Icon(painterResource(icon), null, Modifier.size(14.dp), tint = color)
        Text(
            text,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            style = LocalTextStyle.current.copy(fontFeatureSettings = "tnum")
        )
    }
}

/** iOS StripStyles.roundButton: 52dp circle, white with a black icon when [filled]; [fill] paints it a status colour instead. */
@Composable
internal fun RoundButton(
    icon: Int,
    filled: Boolean,
    size: Dp = 52.dp,
    fill: Color? = null,
    label: String? = null,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    val haptic = rememberHaptic()
    val base = Modifier.size(size).alpha(if (enabled) 1f else 0.4f).clip(CircleShape)
    Row(
        (
            if (filled) {
                base.background(Color.White)
            } else {
                base.background(fill ?: Scrim).border(
                    1.dp,
                    if (fill ==
                        null
                    ) {
                        Hairline
                    } else {
                        Color.Transparent
                    },
                    CircleShape
                )
            }
            )
            .clickable(enabled) {
                haptic(false)
                onClick()
            },
        Arrangement.Center,
        Alignment.CenterVertically
    ) {
        Icon(painterResource(icon), label, Modifier.size(size * 0.46f), tint = if (filled) Color.Black else Color.White)
    }
}
