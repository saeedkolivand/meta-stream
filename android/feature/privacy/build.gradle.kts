// Privacy blur: ML Kit face/text/barcode detection feeding a GL pixelate filter; fails closed.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.privacy" }

dependencies {
    implementation(project(":feature:engine"))
    implementation(libs.rootencoder)
    implementation(libs.mlkit.face)
    implementation(libs.mlkit.text)
    implementation(libs.mlkit.barcode)
}
