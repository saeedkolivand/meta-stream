// Kick, Twitch, YouTube, Restream (and Spotify) accounts: OAuth, tokens, stream info, categories, ingest.
plugins { id("metastream.android.feature") }

android {
    namespace = "com.saeedkolivand.metastream.platforms"
    buildFeatures { buildConfig = true }
    defaultConfig {
        // Same names as the iOS secrets. The two *_SECRET values ship in the APK like iOS Info.plist (Kick/Restream need them).
        listOf(
            "KICK_CLIENT_ID",
            "KICK_CLIENT_SECRET",
            "TWITCH_CLIENT_ID",
            "RESTREAM_CLIENT_ID",
            "RESTREAM_CLIENT_SECRET",
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
