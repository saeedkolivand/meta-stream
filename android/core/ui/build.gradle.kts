// The shared look: iOS system colours, inset-grouped settings rows, pills and round buttons.
plugins { id("metastream.android.compose") }

android { namespace = "com.saeedkolivand.metastream.core.ui" }

dependencies { implementation(project(":core:storage")) }
