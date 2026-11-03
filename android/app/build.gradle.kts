plugins { id("metastream.android.application") }

android {
    namespace = "com.saeedkolivand.metastream"

    defaultConfig {
        applicationId = "com.saeedkolivand.metastream"
        versionCode = 1
        versionName = "1.0"
        // Phones are arm64 and the emulator x86_64; the 32-bit copies of RootEncoder/ML Kit/UVC natives only add size.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }

        // Meta DAT credentials; empty is fine with Developer Mode on.
        manifestPlaceholders["mwdat_application_id"] = localProperty("mwdat_application_id")
        manifestPlaceholders["mwdat_client_token"] = localProperty("mwdat_client_token")

        // Instagram's source_application for story sharing: the Meta Wearables app's ID (public, not a secret).
        // The META_APP_ID secret (env, as on iOS) or local.properties; falls back to the local mwdat_application_id.
        val metaAppId = credential("META_APP_ID").ifEmpty { localProperty("mwdat_application_id") }
        buildConfigField("String", "META_APP_ID", "\"$metaAppId\"")
    }

    buildFeatures { buildConfig = true }

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
    implementation(project(":core:model"))
    implementation(project(":core:logging"))
    implementation(project(":core:storage"))
    implementation(project(":core:network"))
    implementation(project(":core:ui"))
    implementation(project(":feature:camera"))
    implementation(project(":feature:glasses"))
    implementation(project(":feature:platforms"))
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
    implementation(libs.uvcandroid) // UvcSource picks the camera format; extra-sources keeps UVCAndroid off our compile classpath
    implementation(libs.mlkit.face)
    implementation(libs.mlkit.text)
    implementation(libs.mlkit.barcode)
    implementation(libs.mlkit.genai.prompt) // on-device Gemini Nano (AICore) for AI chat moderation, like iOS FoundationModels
    implementation(libs.okhttp)
    implementation(libs.zxing.core) // QR widget: encoding a QR code by hand is ~600 lines; core is pure Java, no Android deps
    implementation(libs.carapp)

    testImplementation(libs.junit)
    testImplementation(libs.org.json) // android.jar only has stubs for org.json on the JVM
}
