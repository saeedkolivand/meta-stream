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
        .library(name: "CoreModel", targets: ["CoreModel"])
    ],
    targets: [
        // Plain data shared by every feature: chat events and money. Foundation only.
        .target(name: "CoreModel", swiftSettings: strict)
    ]
)
