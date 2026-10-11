package com.saeedkolivand.metastream.ui

import androidx.compose.runtime.Composable
import com.saeedkolivand.metastream.privacy.Privacy
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.Source

/** iOS PrivacySettingsView: one master switch, then what to hide, then the honest limits. */
@Composable
internal fun PrivacySettings() {
    SwitchRow("Privacy blur", Privacy.on, onChange = Privacy::updateOn)
    if (Privacy.on) {
        SwitchRow("Faces", Privacy.faces, onChange = Privacy::updateFaces)
        SwitchRow("Text and licence plates", Privacy.text, onChange = Privacy::updateText)
        SwitchRow("QR codes and barcodes", Privacy.barcodes, onChange = Privacy::updateBarcodes)
    }
    Footnote("Pixellates faces, text and codes in the outgoing video. Licence plates come from the text detector, since a plate is text.")
    Footnote(
        "This is best effort, not a guarantee. Detection runs per frame and misses profile faces, motion blur, distance and low " +
            "light, so some frames go out unobscured and there is no undo on a live stream. It reduces what gets seen; it is not a " +
            "substitute for not pointing the camera at something."
    )
    Footnote(
        "If detection stops working the whole picture is pixellated and you are told, rather than the stream quietly going clear."
    )
    // iOS words this in Privacy.swift: passthrough never reaches the mixer, so it can never be blurred.
    if (Engine.source == Source.Glasses) {
        Footnote(
            "HEVC glasses passthrough never reaches the encoder here, so it can never be blurred. Blur applies to the phone and USB cameras."
        )
    }
}
