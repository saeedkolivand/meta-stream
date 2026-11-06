// Android library module: same SDK/Java levels as :app. Kotlin is built into AGP 9.
plugins {
    id("com.android.library")
    id("org.jlleitschuh.gradle.ktlint")
}

android {
    compileSdk = 37
    defaultConfig { minSdk = 33 }
    // android.util.Log (applog) is a stub on the JVM; make it a no-op instead of throwing.
    testOptions { unitTests.isReturnDefaultValues = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")
dependencies {
    "testImplementation"(libs.findLibrary("junit").get())
    "testImplementation"(libs.findLibrary("org-json").get())
}
