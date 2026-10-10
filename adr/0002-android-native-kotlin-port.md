# Android is a native Kotlin port; phone camera is the default source, Meta glasses supported through the DAT SDK

The Android app is written natively in Kotlin (Compose) rather than sharing code with the Swift app
or using a cross-platform layer. Video, encoders and the glasses SDK are all platform APIs, so a shared
layer would only wrap them. The phone camera is the default source (RootEncoder `GenericStream`,
H.264 + AAC, which every ingest accepts); Meta glasses are a second source through the DAT Android SDK,
sent as HEVC passthrough over enhanced RTMP like on iOS.

## Consequences

Behavior is ported, not code: keep the domain terms in CONTEXT.md identical on both platforms.
