package com.saeedkolivand.metastream.remote

import com.saeedkolivand.metastream.overlay.OverlayStore
import com.saeedkolivand.metastream.overlay.SceneRoles
import com.saeedkolivand.metastream.overlay.Scenes
import com.saeedkolivand.metastream.streaming.AudioMix
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.NetStats
import com.saeedkolivand.metastream.streaming.Recording
import com.saeedkolivand.metastream.streaming.Soundboard
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/** The request handlers: plain main-thread calls into the app. */
object ObsRequests {
    private val none = JSONObject()

    private fun ok(data: JSONObject = JSONObject()) = Triple(100, null, data)

    private fun fail(code: Int, why: String) = Triple(code, why, none)

    private fun ms(since: Long?) = since?.let { System.currentTimeMillis() - it } ?: 0L

    private fun tc(t: Long) = String.format(Locale.US, "%02d:%02d:%02d.%03d", t / 3_600_000, t / 60_000 % 60, t / 1000 % 60, t % 1000)

    private fun scene() = OverlayStore.scene.let {
        JSONObject().put("currentProgramSceneName", it).put("sceneName", it).put("currentProgramSceneUuid", it).put("sceneUuid", it)
    }

    private fun startStream() = if (Engine.live) fail(500, "Stream is already running") else ok().also { Engine.goLive() }

    private fun stopStream() = if (!Engine.live) fail(501, "Stream is not running") else ok().also { SceneRoles.requestStop() }

    private fun record(on: Boolean): Triple<Int, String?, JSONObject> {
        if (on ==
            (Recording.since != null)
        ) {
            return fail(if (on) 500 else 501, if (on) "Record is already running" else "Record is not running")
        }
        if (on) Recording.start() else Recording.stop()
        return ok(if (on) JSONObject() else JSONObject().put("outputPath", ""))
    }

    private fun mic(name: String?, want: (Boolean) -> Boolean): Triple<Int, String?, JSONObject> {
        name ?: return fail(300, "Missing inputName")
        if (name != "Mic") return fail(600, "No input named $name")
        if (want(Engine.muted) != Engine.muted) Engine.toggleMute()
        return ok(JSONObject().put("inputMuted", Engine.muted))
    }

    fun run(type: String, q: JSONObject): Triple<Int, String?, JSONObject> {
        val input = (q.optString("inputName").ifEmpty { q.optString("inputUuid") }).ifEmpty { null }
        return when (type) {
            "GetVersion" -> ok(
                JSONObject().put("obsVersion", "30.0.0").put("obsWebSocketVersion", "5.5.0").put("rpcVersion", 1)
                    .put("availableRequests", JSONArray(ObsServer.requests)).put("supportedImageFormats", JSONArray())
                    .put("platform", "android").put("platformDescription", "MetaStream")
            )
            "GetSceneList" -> ok(
                scene().put(
                    "currentPreviewSceneName",
                    JSONObject.NULL
                ).put("currentPreviewSceneUuid", JSONObject.NULL).put("scenes", ObsServer.sceneList())
            )
            "GetCurrentProgramScene" -> ok(scene())
            "SetCurrentProgramScene" -> {
                val n = q.optString("sceneName").ifEmpty { q.optString("sceneUuid") }.ifEmpty { return fail(300, "Missing sceneName") }
                if (OverlayStore.scenes.none { it.name == n }) fail(600, "No scene named $n") else ok().also { Scenes.select(n) }
            }
            "GetStudioModeEnabled" -> ok(JSONObject().put("studioModeEnabled", false))
            "GetStreamStatus" -> ms(Engine.liveSince).let { t ->
                ok(
                    JSONObject().put("outputActive", Engine.live).put("outputReconnecting", Engine.live && NetStats.connectedSince == null)
                        .put("outputTimecode", tc(t)).put("outputDuration", t).put("outputCongestion", 0).put("outputBytes", 0)
                        .put("outputSkippedFrames", 0).put("outputTotalFrames", 0)
                )
            }
            "StartStream" -> startStream()
            "StopStream" -> stopStream()
            "ToggleStream" -> Engine.live.let { was ->
                (if (was) stopStream() else startStream()).let { r ->
                    if (r.first ==
                        100
                    ) {
                        ok(JSONObject().put("outputActive", !was))
                    } else {
                        r
                    }
                }
            }
            "GetRecordStatus" -> ms(Recording.since).let { t ->
                ok(
                    JSONObject().put("outputActive", Recording.since != null).put("outputPaused", false).put("outputTimecode", tc(t))
                        .put("outputDuration", t).put("outputBytes", 0)
                )
            }
            "StartRecord" -> record(true)
            "StopRecord" -> record(false)
            "ToggleRecord" -> (Recording.since != null).let { was ->
                record(!was).let { r -> if (r.first == 100) ok(JSONObject().put("outputActive", !was)) else r }
            }
            "GetInputList" -> {
                fun row(n: String, kind: String) =
                    JSONObject().put("inputName", n).put("inputUuid", n).put("inputKind", kind).put("unversionedInputKind", kind)
                ok(
                    JSONObject().put(
                        "inputs",
                        JSONArray(
                            listOf(row("Mic", "pulse_input_capture")) + Soundboard.sounds.map { row(it.name, "ffmpeg_source") }
                        )
                    )
                )
            }
            "GetInputMute" -> mic(input) { it }
            "SetInputMute" -> if (!q.has("inputMuted")) {
                fail(300, "Missing inputMuted")
            } else {
                q.optBoolean("inputMuted").let { m ->
                    mic(input) { m }
                }
            }
            "ToggleInputMute" -> mic(input) { !it }
            "TriggerMediaInputAction" -> {
                val action = q.optString("mediaAction")
                if (input == null || action.isEmpty()) return fail(300, "Missing inputName or mediaAction")
                val snd = Soundboard.sounds.firstOrNull { it.name == input } ?: return fail(600, "No input named $input")
                if (action.endsWith("_RESTART") || action.endsWith("_PLAY")) AudioMix.playSound(snd)
                ok()
            }
            "GetHotkeyList" -> ok(JSONObject().put("hotkeys", JSONArray()))
            else -> fail(204, "Not supported by MetaStream")
        }
    }
}
