// swift-tools-version: 6.2
// MetaStreamKit: the app's modules (adr/0007). One package, many targets: same module names as the Android Gradle
// modules. Core targets stay nonisolated; feature/UI targets get MainActor default isolation as they move in.
import PackageDescription

/// Every warning fails the build, deprecations stay warnings (same as the app target's OTHER_SWIFT_FLAGS).
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error), .treatWarning("DeprecatedDeclaration", as: .warning)]

let package = Package(
    name: "MetaStreamKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CoreModel", targets: ["CoreModel"]),
        .library(name: "CoreLogging", targets: ["CoreLogging"]),
        .library(name: "CoreStorage", targets: ["CoreStorage"]),
        .library(name: "CoreNetwork", targets: ["CoreNetwork"]),
        .library(name: "ScreenIPC", targets: ["ScreenIPC"]),
        .library(name: "ActivityShared", targets: ["ActivityShared"]),
        .library(name: "CoreUI", targets: ["CoreUI"]),
        .library(name: "Camera", targets: ["Camera"])
    ],
    targets: [
        // Plain data shared by every feature: chat events, money, text patterns. Foundation only.
        .target(name: "CoreModel", swiftSettings: strict),
        // applog, the Logs screen's store and file, secret redaction.
        .target(name: "CoreLogging", dependencies: ["CoreModel"], swiftSettings: strict),
        // TokenStore (Keychain).
        .target(name: "CoreStorage", swiftSettings: strict),
        // OAuth form posts, PKCE, the authenticated PlatformEndpoint.
        .target(name: "CoreNetwork", dependencies: ["CoreLogging", "CoreStorage"], swiftSettings: strict),
        // Contracts the extensions share with the app: screen-share frame files, Live Activity state.
        .target(name: "ScreenIPC", swiftSettings: strict),
        .target(name: "ActivityShared", swiftSettings: strict),
        // The shared look: theme colours, display names, strip pills/round buttons, settings sliders and toggles.
        .target(name: "CoreUI", dependencies: ["CoreModel"], swiftSettings: strict),
        // Phone camera: lens discovery, capabilities, CameraSettings and applying them to an AVCaptureDevice.
        .target(name: "Camera", dependencies: ["CoreLogging"], swiftSettings: strict)
    ]
)
