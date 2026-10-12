// Animated GIF layer: every frame is decoded once and scaled to the output box, then the task just swaps bitmaps
// on the frame delays. No per-frame decoding while live.
import ImageIO
import UIKit

extension OverlayCompositor {
    // ponytail: frames live in memory as output-size bitmaps, capped at 120 frames and ~96 MB total (long or big GIFs
    // keep every Nth frame, so they play a little choppier). Upgrade path: decode lazily from CGImageSource, a few ahead.
    private static let maxGifFrames = 120
    private static let gifBudget = 96_000_000

    func gifWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard l.type == .image, let url = OverlayStore.shared.local(l.data["file"] ?? ""),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 1,
              let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let count = CGImageSourceGetCount(src)
        let affordable = max(2, Self.gifBudget / max(1, Int(rect.width * rect.height) * 4))
        let step = Int((Double(count) / Double(min(Self.maxGifFrames, affordable))).rounded(.up))
        var frames: [(bitmap: OverlayBitmap, ms: Int)] = []
        var i = 0
        while i < count {
            var ms = 0
            for j in i..<min(i + step, count) { ms += Self.delayMs(src, j) }   // skipped frames lend their time to the kept one
            if let cg = CGImageSourceCreateImageAtIndex(src, i, nil),
               let p = OverlayRaster.render(box, canvas: canvas, draw: { OverlayRaster.drawImage(UIImage(cgImage: cg), crop: l.crop, in: $0) }) {
                frames.append((p.bitmap, ms))
            }
            i += step
        }
        guard frames.count > 1 else { return nil }
        let o = await OverlayScreen.makeImage(rect, frames[0].bitmap)
        let task = Task { [frames] in
            var n = 0
            while !Task.isCancelled {
                n = (n + 1) % frames.count
                try? await Task.sleep(for: WidgetRaster.pause(frames[n == 0 ? frames.count - 1 : n - 1].ms))
                guard !Task.isCancelled else { return }
                await OverlayScreen.setImage(o, frames[n].bitmap)
            }
        }
        let object: ScreenObject = o
        return WidgetBuild(object: object, task: task)
    }

    /// Browsers treat anything under ~50 ms as 100 ms; clamping to 50 ms keeps encode load sane at the cost of fast GIFs.
    private static func delayMs(_ src: CGImageSource, _ i: Int) -> Int {
        let gif = (CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let s = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return max(50, Int(s * 1000))
    }
}
