// Convention plugins: precompiled scripts in src/main/kotlin, the file name is the plugin id.
plugins { `kotlin-dsl` }

dependencies {
    compileOnly(libs.android.gradle.plugin)
    compileOnly(libs.kotlin.gradle.plugin)
    compileOnly(libs.compose.gradle.plugin)
    compileOnly(libs.ktlint.gradle.plugin)
}
