// Overlays: scene store and OBS import, the GL compositor (SceneCompositor), widgets, alerts, stingers, role scenes.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.overlay" }

dependencies {
    implementation(libs.androidx.activity.compose)
    implementation(project(":core:network"))
    implementation(project(":feature:camera"))
    implementation(project(":feature:platforms"))
    implementation(project(":feature:chat"))
    implementation(project(":feature:goal"))
    implementation(project(":feature:speech"))
    implementation(project(":feature:privacy"))
    implementation(project(":feature:engine"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.documentfile)
    implementation(libs.rootencoder)
    implementation(libs.zxing.core) // QR widget: encoding a QR code by hand is ~600 lines; core is pure Java, no Android deps
}
