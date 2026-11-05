plugins { id("metastream.android.application") }

android {
    namespace = "com.saeedkolivand.metastream"

    defaultConfig {
        applicationId = "com.saeedkolivand.metastream"
        versionCode = 1
        versionName = "1.0"

        // Meta DAT credentials; empty is fine with Developer Mode on.
        manifestPlaceholders["mwdat_application_id"] = localProperty("mwdat_application_id")
        manifestPlaceholders["mwdat_client_token"] = localProperty("mwdat_client_token")
    }

    // One APK per ABI: arm64 for modern phones, armeabi-v7a for 32-bit ones, x86_64 for the emulator.
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = false
        }
    }

    // One fixed key (signing/, gitignored; CI writes it from secrets) so every build updates the last one in place.
    val key = rootDir.resolve("../signing/android-release.jks")
    signingConfigs {
        if (key.exists()) {
            create("release") {
                storeFile = key
                storePassword = rootDir.resolve("../signing/android-keystore-password.txt").readText().trim()
                keyAlias = "metastream"
                keyPassword = storePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // No keystore (a fresh clone): the debug key, which can't update a release-key install.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    implementation(project(":feature:chat"))
    implementation(project(":feature:goal"))
    implementation(project(":feature:speech"))
    implementation(project(":feature:privacy"))
    implementation(project(":feature:engine"))
    implementation(project(":feature:overlay"))
    implementation(project(":feature:bot"))
    implementation(project(":feature:remote"))
    implementation(project(":feature:reach"))
    implementation(project(":feature:car"))
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
    implementation(libs.okhttp)
    implementation(libs.carapp)

    testImplementation(libs.junit)
    testImplementation(libs.org.json) // android.jar only has stubs for org.json on the JVM
}
