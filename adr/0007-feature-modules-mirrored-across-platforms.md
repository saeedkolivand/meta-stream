# Both apps are split into feature modules with the same names, wired by hand in the app

The iOS app is a thin app target over one local Swift package (`Packages/MetaStreamKit`); the Android app is a thin
`:app` module over Gradle modules. Both use the same module names, so a feature lives in the same place on each:

| Layer | Modules (iOS target / Android module) |
|---|---|
| core | CoreModel / `:core:model`, CoreLogging / `:core:logging`, CoreStorage / `:core:storage`, CoreNetwork / `:core:network`, CoreUI / `:core:ui` |
| feature | Camera, Platforms, Chat, Signals (iOS), Goal, Speech, Privacy, Engine, Overlays, Bot, Reach, Remote / `:feature:*`; Glasses and Car on Android |
| app | the shell and the settings catalog, plus the wiring (iOS `App.swift`, Android `core/App.kt`) |

Rules:

- Arrows point down only: app → feature → core. Features import only the features below them (Engine never imports
  Overlays, Bot or Reach). Where a lower module must reach a higher one it exposes a hook or one protocol the app
  wires up: `SceneCompositor` (Overlays implements it for Engine), `Streamer.onSessionStarted/onSecond/onSessionEnded`,
  `Speaker.skipMessage`, `liveActivity.commands`, Android `Session.live`.
- No DI framework and no api/impl split: each module has one implementation, and the wiring is a page of plain code.
- A feature's settings pages live in that feature (iOS `<Target>/UI/`, Android `<feature>.ui`). The app keeps the
  pages that read several features at once: main screen, HUD, Go Live, chat panel, Stream Manager, Accounts and the
  settings catalog. A separate shell or settings module would only ever be used by the app.
- At most about 15 files a folder. Past that, split by sub-feature (`Widgets/Goal`, `Engine/Uplink`), never by file
  type, with the same folder names on both platforms. `scripts/folders.sh` warns in CI.

## Considered Options

- **One app module per platform, folders only** -- rejected: nothing stops a folder from reaching into any other, and
  the cycles this split had to break (engine ↔ overlays, chat ↔ speech, core ↔ chat) had grown unnoticed.
- **A DI framework (Hilt, a Swift container)** -- rejected: one implementation per seam, and the hand wiring is
  shorter than the framework's setup.
- **Separate shell and settings modules** -- rejected for now: only the app would depend on them.

## Consequences

On iOS every symbol the app uses from a package target must be `public`, and a public struct needs an explicit
public init (the memberwise one stays internal) and an explicit `Sendable` where a static value needs it. Kotlin is
public by default, so Android pays none of this. Moving a Swift file changes its SwiftLint baseline key, so the
baseline is re-recorded with every move.
