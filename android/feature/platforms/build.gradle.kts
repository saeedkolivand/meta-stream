// Kick, Twitch, YouTube, Restream (and Spotify) accounts: OAuth, tokens, stream info, categories, ingest.
plugins { id("metastream.android.feature") }

android {
    namespace = "com.saeedkolivand.metastream.platforms"
    buildFeatures { buildConfig = true }
    defaultConfig {
        // Same names as the iOS build settings. Client secrets live in the auth-proxy Worker, never in the APK.
        listOf(
            "KICK_CLIENT_ID",
            "TWITCH_CLIENT_ID",
            "RESTREAM_CLIENT_ID",
            "YOUTUBE_CLIENT_ID"
        )
            .forEach { buildConfigField("String", it, "\"${credential(it)}\"") }
    }
}

dependencies {
    implementation(project(":core:network"))
    implementation(libs.androidx.activity.compose)
    implementation(libs.kotlinx.coroutines.core)
}
