// Reach: the Telegram live post, session log and report, Wrapped, Instagram story card.
plugins { id("metastream.android.feature") }

android {
    namespace = "com.saeedkolivand.metastream.reach"
    buildFeatures { buildConfig = true }
    defaultConfig {
        // Instagram's source_application for story sharing: the Meta Wearables app's ID (public, not a secret).
        // The META_APP_ID secret (env, as on iOS) or local.properties; falls back to the local mwdat_application_id.
        val metaAppId = credential("META_APP_ID").ifEmpty { localProperty("mwdat_application_id") }
        buildConfigField("String", "META_APP_ID", "\"$metaAppId\"")
    }
}

dependencies {
    implementation(project(":core:network"))
    implementation(project(":feature:platforms"))
    implementation(project(":feature:chat"))
    implementation(project(":feature:goal"))
    implementation(project(":feature:privacy"))
    implementation(project(":feature:engine"))
    implementation(project(":feature:overlay"))
    implementation(project(":feature:bot"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.androidx.core.ktx) // FileProvider for the Instagram story card
}
