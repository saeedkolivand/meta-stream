# Contributing

MetaStream is two native apps that behave the same: iOS/iPadOS in Swift and Android in Kotlin. A feature isn't done
until it works on both, with the same names, settings and layout
([`adr/0002`](adr/0002-android-native-kotlin-port.md)). Behaviour is ported from one app to the other, not shared code.

## Repo layout

```
MetaStream/                 iOS app target: entry, wiring (App/App.swift), main screen, HUD, settings catalog
MetaStreamScreen/           iOS broadcast extension (screen share)
MetaStreamLiveActivity/     iOS Live Activity widget
MetaStreamTests/            iOS unit tests (XCTest)
Packages/MetaStreamKit/     iOS feature modules, one Swift package: Sources/<Module>/
android/app/                Android app module: entry, wiring (core/App.kt), main screen, HUD, settings catalog
android/core/, android/feature/   Android modules with the same names as the iOS targets
android/build-logic/        Gradle convention plugins (metastream.android.library / .feature / .application ...)
adr/                        design decisions        CONTEXT.md   shared vocabulary
guide/                      user docs               docs/        landing page, OAuth redirect, Kick event rules
scripts/                    repo checks (folders.sh)
project.yml, screen.yml, liveactivity.yml   XcodeGen specs (the .xcodeproj is generated, never committed)
```

## Modules

The rules are in [`adr/0007`](adr/0007-feature-modules-mirrored-across-platforms.md). In short:

- **core** (`CoreModel`, `CoreLogging`, `CoreStorage`, `CoreNetwork`, `CoreUI`), then **features** (`Camera`,
  `Platforms`, `Chat`, `Goal`, `Speech`, `Privacy`, `Engine`, `Overlays`, `Bot`, `Reach`, `Remote`; plus `Signals`
  on iOS, `glasses` and `car` on Android), then the **app**. Dependencies only point down. A lower module reaches a higher one through a hook or one protocol that
  the app wires up (`SceneCompositor`, `Streamer.onSessionStarted`, `Speaker.skipMessage`). No DI framework.
- A feature's settings pages live in its own `UI/` folder (iOS) or `ui` package (Android).
- At most about 15 files a folder. Past that, split by sub-feature (`Widgets/Goal`, `Engine/Uplink`), never by file
  type (no `Models/`, `Views/`, `Helpers/`). Use the same folder names on both platforms.
- A new module goes into `Packages/MetaStreamKit/Package.swift` (plus the product in `project.yml`) and
  `android/settings.gradle.kts`, under the same name on both.

## Code rules

- **Simple first.** Use the standard library and the platform before adding a dependency, and plain code before an
  abstraction. If you take a deliberate shortcut, leave a comment that says so and names its limit.
- **Size.** Kotlin files warn over 300 code lines and fail over 400 (`android/loc.sh`). Keep Swift files in the same
  range; split by responsibility, not by line count.
- **Names.** Use the terms in [`CONTEXT.md`](CONTEXT.md) in code and UI on both platforms. Add new terms there.
- **On-stream rendering.** Everything drawn on the stream goes through the GPU on both platforms, uses icons rather
  than emoji, and stays flat (no glass or blur on widgets). Liquid Glass is for app chrome only.
- **iOS.**
  - Swift 6.2 with strict concurrency, and warnings are errors.
  - Observable state uses `@Observable`; views read it with `@Environment(Type.self)`.
  - Anything the app uses from a package target must be `public`, and a public struct needs an explicit public init.
- **Android.**
  - Kotlin with Jetpack Compose; stores are `object`s with Compose state.
  - Pages mirror the iOS ones ([`adr/0002`](adr/0002-android-native-kotlin-port.md)).
- **Decisions.** A choice someone would otherwise undo gets an ADR in `adr/` (copy the format of the existing ones).

## Checks before a PR

**Android** (JDK 17, Android 37 SDK):

```bash
cd android
./gradlew assembleDebug test lint ktlintCheck && bash loc.sh   # ./gradlew ktlintFormat fixes most style issues
```

**iOS** needs a Mac with Xcode 26 to build locally (`xcodegen generate`, then build the MetaStream scheme). Without
one, push your branch and run the workflow: CI builds the app and both extensions. SwiftLint runs strict against
`.swiftlint-baseline.json`:

```bash
swiftlint lint --strict --baseline .swiftlint-baseline.json
```

The baseline records old violations, keyed by file path. New code must not add any. If you move a file, re-record
its baseline entries instead of fixing unrelated code.

**Both:** `bash scripts/folders.sh` warns about folders over 15 files.

## CI

| Workflow | Runs | Trigger |
|---|---|---|
| `build-ipa` (`build.yml`) | SwiftLint on Linux, then XcodeGen + signed build on macOS, encrypted IPA artifact | push to `main`, or manual |
| `build-apk` (`build-apk.yml`) | build, unit tests, lint, ktlint, `loc.sh`, `folders.sh`, encrypted APK artifact | push to `main` under `android/`, or manual |

On a branch, start them by hand: `gh workflow run build.yml --ref <branch>` and
`gh workflow run build-apk.yml --ref <branch>`. A fork needs the secrets from the [build guide](guide/build.md).

## Commits and PRs

- One change per commit, with a message that says what changed and why. Port the same change to the other
  platform in the same PR when you can. If you can't, say what is missing in the PR description.
- Never commit `signing/`, `android/local.properties`, tokens or stream keys.
- Say what you tested on a device. A feature that only builds isn't verified yet.
