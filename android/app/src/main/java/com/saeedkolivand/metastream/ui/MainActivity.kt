package com.saeedkolivand.metastream.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.saeedkolivand.metastream.streaming.Engine
import com.saeedkolivand.metastream.streaming.StreamingService
import kotlinx.coroutines.CompletableDeferred

class MainActivity : ComponentActivity() {
    // Camera permission for the glasses is granted in the Meta AI app; one request at a time is enough here.
    private var pending: CompletableDeferred<PermissionStatus>? = null
    private val wearablesPermission =
        registerForActivityResult(Wearables.RequestPermissionContract()) {
            pending?.complete(it.getOrDefault(PermissionStatus.Denied))
        }

    private suspend fun askWearables(p: Permission): PermissionStatus {
        val d = CompletableDeferred<PermissionStatus>().also { pending = it }
        wearablesPermission.launch(p)
        return d.await()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Engine.setWearablesAsker(::askWearables)
        setContent { MaterialTheme { MainScreen() } }
    }

    // Visible activity = the one place Android allows starting the camera|microphone service; keep it idle for the car
    // (see StreamingService).
    override fun onStart() {
        super.onStart()
        StreamingService.hold(this, "app")
    }

    override fun onStop() {
        StreamingService.release(this, "app")
        super.onStop()
    }

    override fun onDestroy() {
        Engine.setWearablesAsker(null) // don't keep this activity alive from the process-wide Engine
        super.onDestroy()
    }
}
