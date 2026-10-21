// A widget drawn on the GPU: each frame is Core Image recipes on a StingerCanvas, which the GPU renderer evaluates when
// it composites the video frame. Text and SF Symbols touch the CPU once per look (StingerCanvas caches them); moving,
// fading, wiping and recolouring them is GPU work. The widget's own task (MainActor) decides WHAT to show and hands the
// object a Sendable GPUScene; the object only draws it, in widget-local top-left coordinates like the stingers.
import CoreImage
import HaishinKit
import QuartzCore
import UIKit

/// One look of a widget. `draw` must be pure: the same scene and time give the same picture.
struct GPUScene: Sendable {
    /// Draws the widget into its box (top-left origin, canvas = the widget's bounds). `t` = seconds since `epoch`.
    var draw: @Sendable (StingerCanvas, _ t: Double) -> CIImage
    /// While true the object redraws every frame (a transition, a spinning disc); false = only when the scene changes.
    var moving = false
    var epoch: Double = CACurrentMediaTime()
}

final class GPUWidgetScreenObject: ScreenObject {
    private var scene: GPUScene?
    private var canvas: StingerCanvas?
    private var ticker: Task<Void, Never>?

    /// nil blanks the widget. A moving scene keeps the object redrawing at 60 Hz until a still one (or nil) replaces it.
    func show(_ next: GPUScene?) {
        scene = next
        invalidateLayout()
        if next?.moving == true {
            guard ticker == nil else { return }
            // Layout only re-runs when invalidated, so poke it while moving (cheap: no drawing here), as the stingers do.
            ticker = Task { @ScreenActor [weak self] in
                while !Task.isCancelled, let self, self.scene?.moving == true {
                    self.invalidateLayout()
                    try? await Task.sleep(for: .milliseconds(16))
                }
                self?.ticker = nil
            }
        } else {
            ticker?.cancel()
            ticker = nil
        }
    }

    override func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        // An empty image (not nil) when blank: nil would leave the renderer's last frame on screen.
        guard let scene, bounds.width >= 1, bounds.height >= 1 else { return CIImage.empty() }
        let paper: StingerCanvas
        if let kept = canvas, kept.size == bounds.size { paper = kept } else { paper = StingerCanvas(size: bounds.size) }
        canvas = paper
        // Top-left art flipped once into Core Image's bottom-left space and cut to the box, like the stingers.
        return scene.draw(paper, CACurrentMediaTime() - scene.epoch)
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: paper.size.height))
            .cropped(to: paper.bounds)
    }
}

extension OverlayScreen {
    /// A GPU-drawn widget over `rect`, blank until its first `show`.
    @ScreenActor static func makeGPU(_ rect: CGRect) -> GPUWidgetScreenObject {
        let widget = GPUWidgetScreenObject()
        widget.size = rect.size
        widget.horizontalAlignment = .left
        widget.verticalAlignment = .top
        widget.layoutMargin = UIEdgeInsets(top: rect.minY, left: rect.minX, bottom: 0, right: 0)
        widget.invalidateLayout()
        return widget
    }

    @ScreenActor static func show(_ widget: GPUWidgetScreenObject, _ scene: GPUScene?) { widget.show(scene) }

    /// Re-lays a GPU widget out at a new rect (a text widget whose width follows its content).
    @ScreenActor static func move(_ widget: GPUWidgetScreenObject, to rect: CGRect) {
        widget.size = rect.size
        widget.layoutMargin = UIEdgeInsets(top: rect.minY, left: rect.minX, bottom: 0, right: 0)
        widget.invalidateLayout()
    }
}
