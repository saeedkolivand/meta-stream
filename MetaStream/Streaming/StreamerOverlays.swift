// OBS scene overlays on the stream: when they can be drawn, and keeping the mixer's Screen in line with the chosen scene.
import Foundation

extension Streamer {

    /// Overlays are drawn by the mixer's Screen, which only sees the phone camera, camera-off black frames and the
    /// H.264 transcode of the glasses. Glasses HEVC passthrough never reaches the mixer, so it can't be drawn on
    /// (the HUD pill says so).
    var overlaysUsable: Bool { source == "phone" || cameraOff || hot.transcoder != nil }

    /// A scene is picked and the current source can show it: this keeps the mixer in offscreen mode (see syncBlurEffect).
    var overlaysWanted: Bool { overlaysUsable && OverlayStore.shared.activeScene != nil }

    /// Builds, swaps or clears the scene on the mixer's Screen. Idempotent (the compositor compares scene, canvas,
    /// mixer and imported files), so the 1 s tick can call it freely. Call it with the render loop off or the canvas
    /// size unchanged: syncBlurEffect runs it before turning offscreen mode on.
    func syncOverlays() async {
        let store = OverlayStore.shared
        await overlays.apply(scene: overlaysUsable ? store.activeScene : nil, pack: store.pack, canvas: blurCanvasSize, mixer: mixer)
    }
}
