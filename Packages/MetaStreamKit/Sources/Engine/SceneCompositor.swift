// What the engine needs from the scene layer (Android: streaming/SceneCompositor.kt). Overlays' SceneDirector
// implements it and App.swift sets Streamer.compositor, so the engine never depends on the overlays.
import Foundation

@MainActor
public protocol SceneCompositor: AnyObject {
    /// A scene is picked and the current source can show it: keeps the mixer in offscreen mode (see syncBlurEffect).
    var wanted: Bool { get }
    /// A scene is picked, whatever the source (going live decides the mixer path before the source settles).
    var hasScene: Bool { get }
    /// Builds, swaps or clears the scene on the mixer's Screen. Idempotent, so the 1 s tick can call it freely.
    func sync() async
    /// The first connect of a session: a Starting role scene goes up.
    func sessionStarted()
    /// Live ended: a Starting countdown or BRB still running goes back to the scene before it.
    func sessionEnded()
    /// Health tick: BRB scene in or out by the uplink state.
    func checkBRB()
    /// The Stop button: with an Ending scene, hold it before stopping; a second tap stops now.
    func requestStop()
}

extension Streamer {
    /// Overlays are drawn by the mixer's Screen, which only sees the phone camera, camera-off black frames and the
    /// H.264 transcode of the glasses. Glasses HEVC passthrough never reaches the mixer, so it can't be drawn on
    /// (the HUD pill says so).
    public var overlaysUsable: Bool { source == "phone" || source == "screen" || cameraOff || hot.transcoder != nil }

    public var overlaysWanted: Bool { compositor?.wanted ?? false }

    public func syncOverlays() async { await compositor?.sync() }

    /// The Stop button (Go Live, OBS remote): the scene layer may hold an Ending scene first.
    public func requestStop() {
        if let compositor { compositor.requestStop() } else { stopLive() }
    }
}
