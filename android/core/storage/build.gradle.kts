// Prefs, AppSettings and the Keystore-encrypted TokenStore.
plugins { id("metastream.android.library") }

android { namespace = "com.saeedkolivand.metastream.core.storage" }

dependencies {
    implementation(project(":core:logging"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.runtime)
    implementation(libs.androidx.core.ktx)
}
