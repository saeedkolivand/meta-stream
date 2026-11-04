// Android Auto: the car messaging app (live status, chat read-out, quick replies) and its notifications.
plugins { id("metastream.android.feature") }

android { namespace = "com.saeedkolivand.metastream.car" }

dependencies {
    implementation(project(":feature:platforms"))
    implementation(project(":feature:chat"))
    implementation(project(":feature:speech"))
    implementation(project(":feature:engine"))
    implementation(project(":feature:overlay"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.carapp)
}
