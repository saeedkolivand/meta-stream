// A feature module: Android + Compose, with the core modules every feature uses.
plugins { id("metastream.android.compose") }

dependencies {
    "implementation"(project(":core:model"))
    "implementation"(project(":core:logging"))
    "implementation"(project(":core:storage"))
    "implementation"(project(":core:ui"))
}
