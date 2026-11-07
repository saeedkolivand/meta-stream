# Consumer rules ship with and are applied for: Meta DAT (mwdat-core/mockdevice: keeps com.meta.wearable.**), OkHttp
# (okhttp3.pro), car-app (proguard.txt), UVCAndroid, androidx. RootEncoder ships none.

# RootEncoder: encoders/muxers are reached through MediaCodec/GL callbacks and its own stream-client reflection-free paths,
# but it ships no rules, so keep it whole rather than risk a release-only streaming failure (it is the app's core).
-keep class com.pedro.** { *; }
-dontwarn com.pedro.**

# ML Kit builds its component registrars by reflection (Class.forName + no-arg constructor) from manifest meta-data.
# firebase-components' own rule keeps the classes but not their constructors, which R8 full mode then strips, so
# every ML Kit client (face/text/barcode) came back null in release builds (Sentry META-STREAM-1).
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
