// The Now playing widget drawn on the GPU: NowPlayingView's eight designs as Core Image recipes on a StingerCanvas, like
// AlertIslandGPU's IslandArt. Every frame is a pure function of (track, art, pose, clock, now); the designs draw in the
// natural points of NowPlayingWidgetStyle.natural (the 1080 scale) and `ratio` scales them to canvas pixels once.
// Cards and text widgets live in NowPlayingArtCards.swift / NowPlayingArtText.swift as extensions of NPDraw.
import CoreImage
import Synchronization
import UIKit

/// The album art travels inside a scene's Sendable closure. A CGImage is immutable once made, so sharing it across
/// threads is safe; the box only tells the compiler so.
struct NPArtBox: @unchecked Sendable { let image: CGImage }

/// One styled piece of text. `tracking` is in em, like StingerCanvas.text.
struct NPRun {
    var text: String
    var size: CGFloat
    var weight: UIFont.Weight = .bold
    var color: UInt32 = 0xFFFF_FFFF
    var tracking: CGFloat = 0
}

/// What one frame shows: the song, its cover, the pose, and the clocks (`clock` drives endless motion, `now` the progress).
struct NPInput {
    let style: NowPlayingWidgetStyle
    let track: NowPlayingTrack
    let art: CGImage?
    let pose: NowPlayingPose
    let clock: Double
    let now: Date
}

enum NowPlayingArt {
    /// One frame of the widget. `box` = where the widget's natural area sits in the canvas (top-left coordinates).
    static func frame(_ input: NPInput, pen: StingerCanvas, box: CGRect) -> CIImage {
        let scale = box.width / max(1, input.style.natural.width)
        guard scale > 0, input.pose.alpha > 0.001 else { return .empty() }
        let draw = NPDraw(pen: pen, ratio: scale, origin: box.origin, input: input)
        let image: CIImage
        switch input.style.design {
        case .slab: image = draw.slab()
        case .island: image = draw.island()
        case .disc: image = draw.disc()
        case .ticker: image = draw.ticker()
        case .text: image = draw.text()
        case .twoLine: image = draw.twoLine()
        case .cover: image = draw.cornerCover()
        case .popup: image = draw.popup()
        }
        return pen.opacity(image, Double(input.pose.alpha))
    }
}

/// Three bottom-anchored equaliser bars (NowPlayingMotion.eq's `period`, per-bar `step`, `low`).
struct NPBars {
    var left: CGFloat
    var bottom: CGFloat
    var width: CGFloat
    var height: CGFloat
    var gap: CGFloat
    var radius: CGFloat
    var period: Double
    var step: Double
    var low: CGFloat
}

/// Everything one frame of any design reads, plus the drawing helpers (natural points in, canvas pixels out).
struct NPDraw {
    let pen: StingerCanvas
    let ratio: CGFloat
    let origin: CGPoint
    let input: NPInput

    var style: NowPlayingWidgetStyle { input.style }
    var track: NowPlayingTrack { input.track }
    var art: CGImage? { input.art }
    var pose: NowPlayingPose { input.pose }
    var clock: Double { input.clock }
    var now: Date { input.now }

    static let card: UInt32 = 0xFF14_1518
    static let island: UInt32 = 0xFF11_1214
    static let grey: UInt32 = 0xFFA9_ADB5
    static let dim: UInt32 = 0xFF6F_747D
    static let trackBar: UInt32 = 0xFF2C_2F35
    static let box: UInt32 = 0x3310_1014   // the text widgets' 20% near-black box
    static let white: UInt32 = 0xFFFF_FFFF

    var accent: UInt32 { style.accentColor }
    var progress: Double { min(1, max(0, track.progress(now))) }
    var elapsed: String { Self.mmss(track.elapsedMs(now)) }
    var total: String { Self.mmss(track.durationMs) }
    /// "Title · Artist"; just the title for a track without artists.
    var line: String { track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)" }

    static func mmss(_ ms: Int) -> String {
        let secs = max(0, ms) / 1000
        return "\(secs / 60):" + String(format: "%02d", secs % 60)
    }

    /// Digits all alike, so a time's width (and the bar beside it) does not move as it counts (SwiftUI's monospacedDigit).
    static func tabular(_ text: String) -> String { String(text.map { $0.isNumber ? "0" : $0 }) }

    // MARK: geometry (natural -> canvas)

    func point(_ spot: CGPoint) -> CGPoint { CGPoint(x: origin.x + spot.x * ratio, y: origin.y + spot.y * ratio) }

    func canvasRect(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * ratio, y: origin.y + rect.minY * ratio, width: rect.width * ratio, height: rect.height * ratio)
    }

    func fill(_ rect: CGRect, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage { pen.fill(canvasRect(rect), argb, alpha: alpha) }

    func pill(_ rect: CGRect, _ radius: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        pen.roundedRect(canvasRect(rect), radius: radius * ratio, argb, alpha: alpha)
    }

    // MARK: text

    private func attributed(_ run: NPRun, _ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: WidgetFonts.uiFont(face: style.face, size: run.size * ratio, weight: run.weight),
            .kern: run.tracking * run.size * ratio
        ])
    }

    /// Measured run sizes (canvas px), so a moving design doesn't re-lay its text out on the CPU every frame.
    /// ponytail: cleared wholesale past 256 entries; an LRU if songs with many long titles ever thrash it.
    private static let measured = Mutex<[String: CGSize]>([:])

    /// Natural size of a run. An empty run is zero wide but keeps a line's height.
    func measure(_ run: NPRun) -> CGSize {
        let key = "\(run.text)|\(style.face)|\(run.size * ratio)|\(run.weight.rawValue)|\(run.tracking)"
        let px = Self.measured.withLock { $0[key] } ?? {
            let width = run.text.isEmpty ? 0 : ceil(attributed(run, run.text).size().width)
            let found = CGSize(width: width, height: ceil(attributed(run, run.text.isEmpty ? "Ag" : run.text).size().height))
            Self.measured.withLock { cache in
                if cache.count > 256 { cache.removeAll() }
                cache[key] = found
            }
            return found
        }()
        return CGSize(width: px.width / ratio, height: px.height / ratio)
    }

    /// `run` with its left edge at `left`, centred vertically on `midY`. Persian/Arabic keeps right-to-left inside the run
    /// (NSAttributedString lays the glyphs out); the run itself stays left-anchored, so the card never mirrors.
    func text(_ run: NPRun, left: CGFloat, midY: CGFloat) -> CIImage {
        guard !run.text.isEmpty else { return .empty() }
        let size = measure(run)
        let spot = point(CGPoint(x: left + size.width / 2, y: midY))
        return pen.text(run.text, at: CGPoint(x: spot.x - run.tracking * run.size * ratio / 2, y: spot.y), size: run.size * ratio,
                        weight: run.weight, color: run.color, tracking: run.tracking, face: style.face)
    }

    /// `run` cut with an ellipsis to fit `width` (SwiftUI's lineLimit(1) truncation).
    func fit(_ run: NPRun, width: CGFloat) -> NPRun {
        let full = measure(run).width
        guard full > width, width > 0 else { return run }
        var count = max(1, Int(Double(run.text.count) * Double(width / full)) - 1)
        var out = run
        out.text = String(run.text.prefix(count)) + "…"
        while count > 1, measure(out).width > width {
            count -= 1
            out.text = String(run.text.prefix(count)) + "…"
        }
        return out
    }

    /// Runs on one line, the last one cut to what is left of `maxWidth`. Returns what was laid out and its width.
    func layout(_ parts: [NPRun], maxWidth: CGFloat) -> (runs: [NPRun], width: CGFloat) {
        var out: [NPRun] = []
        var used: CGFloat = 0
        for (index, part) in parts.enumerated() {
            let run = index == parts.count - 1 ? fit(part, width: maxWidth - used) : part
            out.append(run)
            used += measure(run).width
        }
        return (out, min(used, maxWidth))
    }

    func row(_ runs: [NPRun], left: CGFloat, midY: CGFloat) -> CIImage {
        var x = left
        var layers: [CIImage] = []
        for run in runs {
            layers.append(text(run, left: x, midY: midY))
            x += measure(run).width
        }
        return pen.stack(layers)
    }

    // MARK: pose, cover, shadow

    /// One animated element of the pose: scale (with the flip), spin about `pivot`, then offset and fade.
    func lane(_ image: CIImage, _ lane: NowPlayingLane, pivot: CGPoint) -> CIImage {
        guard lane != NowPlayingLane() else { return image }
        guard lane.alpha > 0.001 else { return .empty() }
        let at = point(pivot)
        let move = CGAffineTransform(translationX: at.x, y: at.y)
            .rotated(by: CGFloat(lane.rot) * .pi / 180)
            .scaledBy(x: max(0.001, lane.scale * lane.scaleX), y: max(0.001, lane.scale))
            .translatedBy(x: -at.x, y: -at.y)
            .concatenating(CGAffineTransform(translationX: lane.dx * ratio, y: lane.dy * ratio))
        return pen.opacity(image.transformed(by: move), Double(lane.alpha))
    }

    /// The album art aspect-filled into a `size` square at (`x`, `y`) and clipped to a rounded rect (radius size/2 = a
    /// circle, 0 = square); until it has downloaded, an accent-tinted square with the music.note symbol.
    func cover(x: CGFloat, y: CGFloat, size: CGFloat, radius: CGFloat) -> CIImage {
        let square = canvasRect(CGRect(x: x, y: y, width: size, height: size))
        let picture: CIImage
        if let art {
            let wide = CGFloat(art.width), high = CGFloat(art.height), zoom = square.width / max(1, min(wide, high))
            picture = CIImage(cgImage: art)
                .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: high))   // into top-left space
                .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
                .transformed(by: CGAffineTransform(translationX: square.midX - wide * zoom / 2, y: square.midY - high * zoom / 2))
                .cropped(to: square)
        } else {
            let mid = CGPoint(x: square.midX, y: square.midY)
            let note = pen.symbol("music.note", pointSize: square.width * 0.45, color: 0xD9FF_FFFF, at: mid)
            picture = pen.stack([pen.fill(square, accent, alpha: 0.35), note])
        }
        guard radius > 0 else { return picture }
        return pen.clip(picture, to: pen.roundedRect(square, radius: radius * ratio, Self.white))
    }

    /// The text widgets' drop shadow (offset 0,2, blur 4, black 80%): a black-tinted blurred copy under the content.
    func shadowed(_ layer: CIImage) -> CIImage {
        guard !layer.extent.isEmpty else { return layer }
        let tint = layer.transformed(by: CGAffineTransform(translationX: 0, y: 2 * ratio)).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.8)
        ])
        return pen.stack([pen.blur(tint, 2 * ratio), layer])
    }

    func bars(_ spec: NPBars) -> [CIImage] {
        (0..<3).map { index in
            let level = NowPlayingMotion.eq(clock, period: spec.period, offset: spec.step * Double(index), low: spec.low)
            let rect = CGRect(x: spec.left + CGFloat(index) * (spec.width + spec.gap), y: spec.bottom - spec.height * level,
                              width: spec.width, height: spec.height * level)
            return spec.radius > 0 ? pill(rect, spec.radius, accent) : fill(rect, accent)
        }
    }
}
