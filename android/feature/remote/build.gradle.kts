// Remote control: OBS WebSocket v5 server so Stream Deck / OBS tools can drive scenes and the stream.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.remote" }

dependencies {
    implementation(project(":feature:engine"))
    implementation(project(":feature:overlay"))
    implementation(libs.kotlinx.coroutines.core)
}
