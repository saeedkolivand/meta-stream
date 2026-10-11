import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.ktlint)
}

val localProperties =
    Properties().apply {
        val file = rootDir.resolve("local.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

// Platform OAuth credentials: CI env vars win, local.properties for dev builds; empty means the app shows "no client ID".
fun credential(name: String) =
    (System.getenv(name)?.takeIf { it.isNotBlank() } ?: localProperties.getProperty(name, "")).trim().replace("\"", "")

android {
    namespace = "com.saeedkolivand.metastream"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.saeedkolivand.metastream"
        minSdk = 37
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
        // Phones are arm64 and the emulator x86_64; the 32-bit copies of RootEncoder/ML Kit/UVC natives only add size.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }

        // Meta DAT credentials; empty is fine with Developer Mode on.
        manifestPlaceholders["mwdat_application_id"] = localProperties.getProperty("mwdat_application_id", "")
        manifestPlaceholders["mwdat_client_token"] = localProperties.getProperty("mwdat_client_token", "")

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

    buildFeatures { buildConfig = true }

    // android.util.Log (applog) is a stub on the JVM; make it a no-op instead of throwing.
    testOptions { unitTests.isReturnDefaultValues = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
}

dependencies {
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.documentfile)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.material3)
    implementation(libs.mwdat.core)
    implementation(libs.mwdat.camera)
    implementation(libs.mwdat.mockdevice)
    implementation(libs.rootencoder)
    implementation(libs.rootencoder.extra)
    implementation(libs.mlkit.face)
    implementation(libs.mlkit.text)
    implementation(libs.mlkit.barcode)
    implementation(libs.okhttp)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.carapp)

    testImplementation(libs.junit)
    testImplementation(libs.org.json) // android.jar only has stubs for org.json on the JVM
}
