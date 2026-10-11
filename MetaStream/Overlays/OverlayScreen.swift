// HaishinKit screen objects for overlay layers. ScreenObject and Screen live on HaishinKit's ScreenActor, so
// everything that touches them is @ScreenActor and takes/returns only Sendable values (the objects themselves are
// implicitly Sendable: they are global-actor isolated classes).
import AVFoundation
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

    @ScreenActor static func setImage(_ o: ImageScreenObject, _ bitmap: OverlayBitmap) {
        o.cgImage = bitmap.image
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

    /// Z-order is add order: later layers draw on top (the camera frame is the Screen's own first child).
    @ScreenActor static func add(_ objects: [ScreenObject], to mixer: MediaMixer) {
        for o in objects { try? mixer.screen.addChild(o) }
    }

    @ScreenActor static func remove(_ objects: [ScreenObject], from mixer: MediaMixer) {
        for o in objects {
            if let m = o as? AssetScreenObject { m.cancelReading() }
            mixer.screen.removeChild(o)
        }
    }
}
