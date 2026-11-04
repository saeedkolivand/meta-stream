// The stream engine: RootEncoder pipeline, sources (phone, USB, screen, glasses), uplink (SRTLA bonding, bitrate),
// audio mix, health, recording, face-cam and looks, and the foreground service. Scenes come in via SceneCompositor.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.streaming" }

dependencies {
    implementation(project(":feature:camera"))
    implementation(project(":feature:glasses"))
    implementation(libs.androidx.activity.compose)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.androidx.core.ktx)
    implementation(libs.mwdat.core)
    implementation(libs.rootencoder)
    implementation(libs.rootencoder.extra)
    implementation(libs.uvcandroid) // UvcSource picks the camera format
}
