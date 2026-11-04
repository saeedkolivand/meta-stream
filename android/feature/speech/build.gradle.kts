// Read aloud: Speaker (TextToSpeech), sentences, speech settings.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.speech" }

dependencies {
    implementation(project(":feature:platforms"))
    implementation(project(":feature:chat"))
    implementation(project(":feature:goal"))
    implementation(libs.kotlinx.coroutines.core)
}
