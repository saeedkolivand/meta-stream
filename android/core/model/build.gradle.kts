// Plain data shared by every feature: chat events and money. No Android, no I/O.
plugins { id("metastream.jvm.library") }

dependencies { implementation(libs.kotlinx.coroutines.core) }
