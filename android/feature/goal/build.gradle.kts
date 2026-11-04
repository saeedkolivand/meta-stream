// Donation goal: GoalStore, donation sites (Donofa, Donito, Reymit, StreamElements), rates, the donate page.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.goal" }

dependencies {
    implementation(project(":core:network"))
    implementation(project(":feature:platforms"))
    implementation(project(":feature:chat"))
    implementation(libs.kotlinx.coroutines.core)
}
