package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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

/** iOS StripStyles.roundButton: 52dp circle, white with a black icon when [filled]. */
@Composable
internal fun RoundButton(icon: Int, filled: Boolean, onClick: () -> Unit) {
    val haptic = rememberHaptic()
    val base = Modifier.size(52.dp).clip(CircleShape)
    Row(
        (if (filled) base.background(Color.White) else base.background(Scrim).border(1.dp, Hairline, CircleShape))
            .clickable {
                haptic(false)
                onClick()
            },
        Arrangement.Center,
        Alignment.CenterVertically
    ) {
        Icon(painterResource(icon), null, Modifier.size(24.dp), tint = if (filled) Color.Black else Color.White)
    }
}

/** iOS quickButton: equal-width tile, icon over label; [tint] null = neutral. */
@Composable
internal fun RowScope.QuickTile(icon: Int, label: String, tint: Color?, enabled: Boolean = true, onClick: () -> Unit) {
    val haptic = rememberHaptic()
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier.weight(1f).height(56.dp).alpha(if (enabled) 1f else 0.4f).clip(shape)
            .background(tint ?: Scrim).border(BorderStroke(1.dp, if (tint == null) Hairline else Color.Transparent), shape)
            .clickable(enabled) {
                haptic(true)
                onClick()
            },
        Arrangement.Center,
        Alignment.CenterHorizontally
    ) {
        Icon(painterResource(icon), null, Modifier.size(22.dp), tint = Color.White)
        Text(label, Modifier.padding(top = 2.dp), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}
