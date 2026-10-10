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

android {
    namespace = "com.saeedkolivand.metastream"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.saeedkolivand.metastream"
        minSdk = 37
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"

        // Meta DAT credentials; empty is fine with Developer Mode on.
        manifestPlaceholders["mwdat_application_id"] = localProperties.getProperty("mwdat_application_id", "")
        manifestPlaceholders["mwdat_client_token"] = localProperties.getProperty("mwdat_client_token", "")
    }

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
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.material3)
    implementation(libs.mwdat.core)
    implementation(libs.mwdat.camera)
    implementation(libs.mwdat.mockdevice)
    implementation(libs.rootencoder)
    implementation(libs.rootencoder.extra)
    implementation(libs.okhttp)
    implementation(libs.carapp)

    testImplementation(libs.junit)
    testImplementation(libs.org.json) // android.jar only has stubs for org.json on the JVM
}
