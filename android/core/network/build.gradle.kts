// The one OkHttp client, JSON helpers, the authenticated Endpoint and PKCE.
plugins { id("metastream.android.library") }

android { namespace = "com.saeedkolivand.metastream.core.network" }

dependencies {
    implementation(project(":core:logging"))
    implementation(project(":core:storage"))
    api(libs.okhttp)
    implementation(libs.kotlinx.coroutines.core)
}
