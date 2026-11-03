// applog, the in-app log ring and the log file, with secret redaction.
plugins { id("metastream.android.library") }

android { namespace = "com.saeedkolivand.metastream.core.logging" }

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.runtime)
}
