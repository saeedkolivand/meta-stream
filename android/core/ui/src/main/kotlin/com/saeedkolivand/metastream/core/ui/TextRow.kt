package com.saeedkolivand.metastream.core.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.BasicSecureTextField
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldDecorator
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.sp

/** iOS Form TextField / SecureField: borderless, the label as its placeholder. */
@Composable
fun TextRow(
    placeholder: String,
    value: String,
    onChange: (String) -> Unit,
    enabled: Boolean = true,
    secure: Boolean = false,
    singleLine: Boolean = true,
    keyboard: KeyboardType = KeyboardType.Text,
    mono: Boolean = false,
    maxLines: Int = 6
) {
    val state = rememberTextFieldState(value)
    val emit by rememberUpdatedState(onChange)
    // User edits go out synchronously (InputTransformation only sees user input), so [value] is never
    // stale when SideEffect pulls caller-side changes (a reset, a clear) back into the field.
    val forward = remember { InputTransformation { emit(asCharSequence().toString()) } }
    SideEffect { if (state.text.toString() != value) state.setTextAndPlaceCursorAtEnd(value) }
    val style = TextStyle(
        color = if (enabled) Color.White else Secondary,
        fontSize = if (mono) 13.sp else 17.sp,
        fontFamily = if (mono) FontFamily.Monospace else null
    )
    val decorator = TextFieldDecorator { inner ->
        Box {
            if (state.text.isEmpty()) Text(placeholder, color = Color.White.copy(alpha = 0.3f), fontSize = if (mono) 13.sp else 17.sp)
            inner()
        }
    }
    val cursor = SolidColor(SystemBlue)
    if (secure) {
        BasicSecureTextField(
            state,
            Modifier.fillMaxWidth(),
            enabled = enabled,
            inputTransformation = forward,
            textStyle = style,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            cursorBrush = cursor,
            decorator = decorator
        )
    } else {
        BasicTextField(
            state,
            Modifier.fillMaxWidth(),
            enabled = enabled,
            inputTransformation = forward,
            textStyle = style,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard),
            lineLimits = if (singleLine) TextFieldLineLimits.SingleLine else TextFieldLineLimits.MultiLine(maxHeightInLines = maxLines),
            cursorBrush = cursor,
            decorator = decorator
        )
    }
}
