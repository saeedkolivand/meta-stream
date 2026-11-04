import AVFoundation
import CoreLogging
import UIKit

/// Clean program feed on a USB-C display. Hot.enqueue feeds `layer` from the same taps as the on-device preview
/// (LayerSink / glasses frames), so no second mixer output is needed and mixer rewires can't orphan it.
// ponytail: unsynchronised weak static; the frame thread may read a layer one frame after disconnect, which is harmless.
enum ExternalDisplay {
    nonisolated(unsafe) static weak var layer: AVSampleBufferDisplayLayer?
}

/// A view whose layer is the display layer the engine enqueues preview frames into (the in-app preview and the
/// external display both use it).
final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}
