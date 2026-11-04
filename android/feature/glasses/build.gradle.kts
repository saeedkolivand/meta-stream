// Meta glasses through the DAT SDK: session, HEVC passthrough and the decoder for the preview.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.glasses" }

dependencies {
    implementation(libs.mwdat.core)
    implementation(libs.mwdat.camera)
    implementation(libs.mwdat.mockdevice)
    implementation(libs.rootencoder)
}
