# Consumer rules ship with and are applied for: Meta DAT (mwdat-core/mockdevice: keeps com.meta.wearable.**), OkHttp
# (okhttp3.pro), car-app (proguard.txt), UVCAndroid, androidx. RootEncoder ships none.

# RootEncoder: encoders/muxers are reached through MediaCodec/GL callbacks and its own stream-client reflection-free paths,
# but it ships no rules, so keep it whole rather than risk a release-only streaming failure (it is the app's core).
-keep class com.pedro.** { *; }
-dontwarn com.pedro.**
