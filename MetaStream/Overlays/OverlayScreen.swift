// HaishinKit screen objects for overlay layers. ScreenObject and Screen live on HaishinKit's ScreenActor, so
// everything that touches them is @ScreenActor and takes/returns only Sendable values (the objects themselves are
// implicitly Sendable: they are global-actor isolated classes).
import AVFoundation
import CoreImage
import HaishinKit
import UIKit

enum OverlayScreen {
    /// ScreenObject lays itself out against its parent (the Screen root, origin top-left): size + top-left alignment
    /// + a margin inset reproduces `rect` exactly. Same recipe as Streamer.layoutOverlay.
    @ScreenActor private static func layout(_ o: ScreenObject, _ rect: CGRect) {
        o.size = rect.size
        o.horizontalAlignment = .left
        o.verticalAlignment = .top
        o.layoutMargin = UIEdgeInsets(top: rect.minY, left: rect.minX, bottom: 0, right: 0)
        o.invalidateLayout()
    }

    /// A still (image, text, color, browser snapshot). `bitmap` may be nil for a browser whose first snapshot isn't in yet.
    @ScreenActor static func makeImage(_ rect: CGRect, _ bitmap: OverlayBitmap?) -> ImageScreenObject {
        let o = ImageScreenObject()
        layout(o, rect)
        o.cgImage = bitmap?.image
        return o
    }

    /// nil blanks the object (an alert between alerts, a faded-out still).
    @ScreenActor static func setImage(_ o: ImageScreenObject, _ bitmap: OverlayBitmap?) {
        o.cgImage = bitmap?.image
    }

    /// Re-lays an object out at a new rect (live text whose width follows its content).
    @ScreenActor static func move(_ o: ImageScreenObject, to rect: CGRect) {
        layout(o, rect)
    }

    /// Plays a local clip (muted: AssetScreenObject reads video only). Reads from the start; see `restart` for looping.
    @ScreenActor static func makeMedia(_ rect: CGRect, _ url: URL) -> AssetScreenObject {
        let o = AssetScreenObject()
        layout(o, rect)
        o.videoGravity = .resizeAspectFill   // the rect already has the clip's aspect; keeps the bounds exactly as laid out
        try? o.startReading(AVURLAsset(url: url))
        return o
    }

    /// AssetScreenObject stops at the end of the clip; reading again from the start is how a loop is made.
    @ScreenActor static func restart(_ o: AssetScreenObject, _ url: URL) {
        if !o.isReading { try? o.startReading(AVURLAsset(url: url)) }
    }

    /// A built-in stinger over `rect` (the whole canvas).
    @ScreenActor static func makeStinger(_ rect: CGRect, _ kind: StingerKind, _ style: StingerStyle) -> StingerScreenObject {
        let o = StingerScreenObject(kind: kind, style: style)
        layout(o, rect)
        return o
    }

    /// Z-order is add order: later layers draw on top (the camera frame is the Screen's own first child).
    /// Overlays composite on the GPU (Core Image on Metal): the CPU renderer converts and alpha-blends every overlay on
    /// the CPU each frame. Switched before the first overlay goes on; HaishinKit's camera object re-lays out every frame.
    @ScreenActor static func add(_ objects: [ScreenObject], to mixer: MediaMixer) {
        if !mixer.screen.isGPURendererEnabled { mixer.screen.isGPURendererEnabled = true }
        for o in objects { try? mixer.screen.addChild(o) }
    }

    /// Moves an object to the top of the z-order again (a rebuilt scene is added after the stinger and would cover it).
    @ScreenActor static func raise(_ o: ScreenObject, on mixer: MediaMixer) {
        mixer.screen.removeChild(o)
        try? mixer.screen.addChild(o)
    }

    /// Old scene off, new scene on, stinger back on top, in one actor hop: each add/remove makes the Screen re-lay out
    /// every child, so doing it all at once costs one re-layout frame.
    @ScreenActor static func swap(remove old: [ScreenObject], from oldMixer: MediaMixer?, add new: [ScreenObject],
                                  to mixer: MediaMixer, top: ScreenObject?) {
        if let oldMixer { remove(old, from: oldMixer) }
        add(new, to: mixer)
        if let top { raise(top, on: mixer) }
    }

    /// Plays a clip from the start again (a prebuilt clip began reading when it was built, not when it went up).
    @ScreenActor static func rewind(_ o: AssetScreenObject, _ url: URL) {
        try? o.startReading(AVURLAsset(url: url))
    }

    @ScreenActor static func remove(_ objects: [ScreenObject], from mixer: MediaMixer) {
        for o in objects {
            if let m = o as? AssetScreenObject { m.cancelReading() }
            mixer.screen.removeChild(o)
        }
    }
}

/// A built-in stinger as a screen object. It draws the frame for each video frame's own timestamp, so it moves in step
/// with the video instead of racing it. GPU renderer only (the CPU renderer asks for a CGImage, which this never makes).
final class StingerScreenObject: ScreenObject {
    private let kind: StingerKind
    private let style: StingerStyle
    private var start: CMTime?
    private var canvas: StingerCanvas?   // its text and stroke caches live as long as the stinger
    // perf: frames drawn, draw time, and the longest gap between video frames, logged once when it ends
    private var frames = 0
    private var drawTotal = 0.0, drawMax = 0.0, gapMax = 0.0
    private var last = 0.0
    private var logged = false

    init(kind: StingerKind, style: StingerStyle) {
        self.kind = kind
        self.style = style
        super.init()
    }

    override func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        let now = renderer.presentationTimeStamp
        let first = start ?? now
        start = first
        let t = (now - first).seconds
        // An empty image (not nil) once it's over: nil would leave the renderer's last frame on screen.
        guard t.isFinite, t >= 0, t <= kind.seconds(style) else {
            if !logged, frames > 0 {
                logged = true
                applog("perf", "stinger \(kind.rawValue): \(frames) frames in \(String(format: "%.2f", last)) s "
                       + "(\(String(format: "%.0f", Double(frames) / max(last, 0.01))) fps), draw avg \(String(format: "%.1f", drawTotal / Double(frames))) ms "
                       + "max \(String(format: "%.1f", drawMax)) ms, longest gap \(String(format: "%.0f", gapMax * 1000)) ms, "
                       + "canvas \(Int(bounds.width))x\(Int(bounds.height)), renderer \(type(of: renderer))")
            }
            return CIImage.empty()
        }
        let began = CACurrentMediaTime()
        let k = canvas?.size == bounds.size ? canvas! : StingerCanvas(size: bounds.size)
        canvas = k
        let image = kind.ciFrame(k, t: t, style: style)
        let ms = (CACurrentMediaTime() - began) * 1000
        frames += 1
        drawTotal += ms
        drawMax = max(drawMax, ms)
        if frames > 1 { gapMax = max(gapMax, t - last) }
        last = t
        return image
    }
}
