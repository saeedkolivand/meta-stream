// swift-tools-version: 6.2
// MetaStreamKit: the app's modules (adr/0007). One package, many targets: same module names as the Android Gradle
// modules. Core targets stay nonisolated; feature/UI targets get MainActor default isolation as they move in.
import PackageDescription

/// Every warning fails the build, deprecations stay warnings (same as the app target's OTHER_SWIFT_FLAGS).
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error), .treatWarning("DeprecatedDeclaration", as: .warning)]
// Leaf UI/feature targets (nothing runs off the main thread): MainActor by default, as Xcode 26 sets up app targets.
// ponytail: Bot and Reach only. Engine/Overlays/Camera/Signals work off main, and CoreUI helpers are called from there.
let ui: [SwiftSetting] = strict + [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")
]

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
        .library(name: "Camera", targets: ["Camera"]),
        .library(name: "Platforms", targets: ["Platforms"]),
        .library(name: "Chat", targets: ["Chat"]),
        .library(name: "Goal", targets: ["Goal"]),
        .library(name: "Speech", targets: ["Speech"]),
        .library(name: "Privacy", targets: ["Privacy"]),
        .library(name: "Signals", targets: ["Signals"]),
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "Overlays", targets: ["Overlays"]),
        .library(name: "Bot", targets: ["Bot"]),
        .library(name: "Reach", targets: ["Reach"]),
        .library(name: "Remote", targets: ["Remote"])
    ],
    // Same URL and floor as project.yml, so Xcode resolves one copy for the app and the package.
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", from: "2.3.0"),
        .package(url: "https://github.com/facebook/meta-wearables-dat-ios", exact: "0.9.0")
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
        .target(name: "Camera", dependencies: ["CoreLogging"], swiftSettings: strict),
        // Kick, Twitch, Restream, YouTube accounts: OAuth, tokens, stream info, categories, ingest.
        .target(name: "Platforms", dependencies: ["CoreLogging", "CoreNetwork", "CoreStorage"], swiftSettings: strict),
        // Chat feed: Kick/Twitch/YouTube providers, emotes, AI moderation and summary, slash commands, kick.com web session.
        .target(name: "Chat", dependencies: ["CoreModel", "CoreLogging", "CoreUI", "Platforms"], swiftSettings: strict),
        // Donation goal: GoalStore, Money, exchange rates, donation-site sources, the donate page publisher.
        .target(name: "Goal", dependencies: ["CoreModel", "CoreLogging", "CoreStorage", "Chat"], swiftSettings: strict),
        // Read-aloud: Speaker's three TTS lanes (System, Alert, Chat).
        .target(name: "Speech", dependencies: ["CoreModel", "CoreUI", "Platforms", "Chat", "Goal"], swiftSettings: strict),
        // Privacy blur: a HaishinKit VideoEffect that pixellates faces, text and barcodes found by Vision.
        .target(name: "Privacy", dependencies: ["CoreLogging", .product(name: "HaishinKit", package: "HaishinKit.swift")],
                swiftSettings: strict),
        // Real-world signals: location (city, distance), weather, Spotify now playing, iPhone-to-iPad GPS share.
        .target(name: "Signals", dependencies: ["CoreLogging", "CoreNetwork", "CoreStorage", "Platforms"], swiftSettings: strict),
        // The streaming engine: Streamer and its components (uplink, SRTLA bonding, bitrate, health, recording, PiP,
        // sound mix, looks, phone/glasses/screen sources). Scene direction stays in the app (SceneCompositor).
        .target(name: "Engine", dependencies: [
            "CoreLogging", "CoreUI", "Camera", "Privacy", "Speech", "ScreenIPC", "ActivityShared",
            .product(name: "HaishinKit", package: "HaishinKit.swift"),
            .product(name: "RTMPHaishinKit", package: "HaishinKit.swift"),
            .product(name: "SRTHaishinKit", package: "HaishinKit.swift"),
            .product(name: "MWDATCore", package: "meta-wearables-dat-ios"),
            .product(name: "MWDATCamera", package: "meta-wearables-dat-ios")
        ], swiftSettings: strict),
        // Scenes on the stream: store, compositor, widgets, stingers, donation alerts, and the SceneDirector the engine
        // calls through SceneCompositor.
        .target(name: "Overlays", dependencies: [
            "CoreModel", "CoreLogging", "CoreUI", "Platforms", "Chat", "Goal", "Signals", "Engine",
            .product(name: "HaishinKit", package: "HaishinKit.swift")
        ], swiftSettings: strict),
        // The streamer's own chat bot: saved commands, role messages, donation thanks.
        .target(name: "Bot", dependencies: [
            "CoreModel", "CoreLogging", "CoreNetwork", "CoreStorage", "CoreUI", "Platforms", "Chat", "Goal", "Signals", "Engine", "Overlays"
        ], swiftSettings: ui),
        // Beyond the stream: Telegram live post, session log, Wrapped, Instagram story, the Streams screens.
        .target(name: "Reach", dependencies: [
            "CoreModel", "CoreLogging", "CoreStorage", "CoreUI", "Platforms", "Chat", "Goal", "Signals", "Engine", "Overlays", "Bot"
        ], swiftSettings: ui),
        // OBS-websocket server: drive scenes and the stream from a desk.
        .target(name: "Remote", dependencies: ["CoreModel", "CoreLogging", "Engine", "Overlays"], swiftSettings: strict)
    ]
)
