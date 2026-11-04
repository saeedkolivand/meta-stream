// The app bot: rules, saved commands, Kick/Twitch bot accounts, event and role notices.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.bot" }

dependencies {
    implementation(project(":core:network"))
    implementation(project(":feature:platforms"))
    implementation(project(":feature:chat"))
    implementation(project(":feature:goal"))
    implementation(project(":feature:engine"))
    implementation(project(":feature:overlay"))
    implementation(libs.kotlinx.coroutines.core)
}
