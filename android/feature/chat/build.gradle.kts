// Chat feed: Kick/Twitch/YouTube providers, parsers, emotes, moderation, slash commands, chat settings.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.chat" }

dependencies {
    implementation(project(":core:network"))
    implementation(project(":feature:platforms"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.mlkit.genai.prompt) // on-device Gemini Nano (AICore) for AI chat moderation, like iOS FoundationModels
}
