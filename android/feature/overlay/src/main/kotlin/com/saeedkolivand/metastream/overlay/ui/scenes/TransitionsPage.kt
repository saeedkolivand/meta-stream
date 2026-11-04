package com.saeedkolivand.metastream.ui.scenes

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.saeedkolivand.metastream.core.storage.Prefs
import com.saeedkolivand.metastream.core.ui.Choice
import com.saeedkolivand.metastream.core.ui.NavRow
import com.saeedkolivand.metastream.core.ui.RadioRow
import com.saeedkolivand.metastream.core.ui.Section
import com.saeedkolivand.metastream.core.ui.Segmented
import com.saeedkolivand.metastream.core.ui.Stepper
import com.saeedkolivand.metastream.core.ui.SwitchRow
import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.overlay.StingerKind
import com.saeedkolivand.metastream.ui.ObsImportSection

private val Intervals = listOf(15 to "15 seconds", 30 to "30 seconds", 60 to "1 min", 120 to "2 min", 300 to "5 min")

/** Settings › Transitions (iOS SceneOptionsView): the transition, scene roles, auto-rotate and the optional OBS import. */
@Composable
internal fun TransitionsPage(openStinger: () -> Unit) {
    Section(
        "Transition",
        "Fade dims the old widgets out and the new ones in. A stinger plays over the change, which happens underneath it " +
            "once the screen is covered. The camera itself switches instantly."
    ) {
        Segmented(
            listOf("cut" to "Cut", "fade" to "Fade", "stinger" to "Stinger"),
            OverlayStore.transition,
            onSelect = OverlayStore::setTransition
        )
        if (OverlayStore.transition == "stinger") {
            val kind = StingerKind.of(Prefs.string("stingerKind", StingerKind.Lens.id)) ?: StingerKind.Lens
            NavRow("Stinger", value = kind.title, onClick = openStinger)
        }
    }
    Section(
        "Scene roles",
        "Give a scene a role in its editor. Starting shows after going live for the countdown (use {countdown} in a " +
            "text widget), BRB while the connection is too weak, Ending for the hold after you tap END (tap again to " +
            "stop at once). Picking a scene by hand cancels the role."
    ) {
        Seconds("Starting countdown", "startCountdown", 60, 0..300, 5)
        Seconds("Ending hold", "endingHold", 10, 0..60, 1)
    }
    RotationSection()
    ObsImportSection()
}

@Composable
private fun RotationSection() {
    val on = OverlayStore.rotateOn
    Section(
        "Auto-rotate",
        if (on) {
            "Pick at least two scenes. Picking a scene by hand that isn't in the list turns rotation off."
        } else {
            "Cycles through the scenes you pick while you stream."
        }
    ) {
        SwitchRow("Rotate scenes automatically", on) {
            OverlayStore.setRotateOn(it)
            Scenes.updateRotation()
        }
        if (!on) return@Section
        Choice("Every", Intervals, OverlayStore.rotateSeconds) {
            OverlayStore.setRotateSeconds(it)
            Scenes.updateRotation()
        }
        for (s in OverlayStore.scenes) {
            val picked = s.name in OverlayStore.rotateScenes
            RadioRow(s.name, picked) {
                OverlayStore.setRotateScenes(if (picked) OverlayStore.rotateScenes - s.name else OverlayStore.rotateScenes + s.name)
                Scenes.updateRotation()
            }
        }
    }
}

/** A seconds setting in Prefs [key]; 0 reads "off". */
@Composable
private fun Seconds(title: String, key: String, default: Int, range: IntRange, step: Int) {
    var v by remember { mutableIntStateOf(Prefs.int(key, default)) }
    Stepper("$title: ${if (v == 0) "off" else "$v s"}", v, range, step) {
        v = it
        Prefs.put(key, it)
    }
}
