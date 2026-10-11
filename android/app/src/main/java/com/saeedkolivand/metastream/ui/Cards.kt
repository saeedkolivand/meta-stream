package com.saeedkolivand.metastream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.saeedkolivand.metastream.R

private val Secondary = Color.White.copy(alpha = 0.6f)

@Composable
private fun Card(icon: Int, title: String, body: String, button: String, footer: String?, onClick: () -> Unit) {
    val haptic = rememberHaptic()
    Column(
        Modifier.widthIn(max = 320.dp).clip(RoundedCornerShape(22.dp)).background(Color(0xFF2C2C2E).copy(alpha = 0.92f)).padding(22.dp),
        Arrangement.spacedBy(14.dp),
        Alignment.CenterHorizontally
    ) {
        Icon(painterResource(icon), null, Modifier.size(40.dp), tint = Color.White)
        Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(body, fontSize = 13.sp, color = Secondary, textAlign = TextAlign.Center)
        Button({
            haptic(false)
            onClick()
        }, Modifier.fillMaxWidth()) { Text(button) }
        footer?.let { Text(it, fontSize = 11.sp, fontFamily = FontFamily.Monospace, color = Secondary) }
    }
}

/** iOS registerCard, shown over the preview until the glasses are registered. */
@Composable
internal fun RegisterCard(state: String, onRegister: () -> Unit) = Card(
    R.drawable.ic_glasses,
    "Connect your glasses",
    "In the Meta AI app: Settings → App Info → tap the version 5× → turn on Developer Mode. Then register this app.",
    "Register with Meta AI",
    state,
    onRegister
)

@Composable
internal fun PermissionCard(onGrant: () -> Unit) = Card(
    R.drawable.ic_videocam,
    "Camera access needed",
    "MetaStream needs camera and microphone access to stream.",
    "Grant",
    null,
    onGrant
)
