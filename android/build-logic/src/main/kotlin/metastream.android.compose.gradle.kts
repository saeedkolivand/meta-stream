// Compose on top of an Android library module.
plugins {
    id("metastream.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
}

android { buildFeatures { compose = true } }

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")
dependencies {
    "implementation"(platform(libs.findLibrary("androidx-compose-bom").get()))
    "implementation"(libs.findLibrary("androidx-material3").get())
    "implementation"(libs.findLibrary("androidx-lifecycle-runtime-compose").get())
}
