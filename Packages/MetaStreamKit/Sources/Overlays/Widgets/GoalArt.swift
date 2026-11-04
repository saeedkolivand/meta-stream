// The on-stream Goal widget drawn on the GPU: every Goal design (GoalView's bar, GoalDesigns*.swift's eight others) as a Core
// Image recipe on a StingerCanvas. Each frame is a pure function of (GoalInput, canvas, box), so the widget task only hands the
// GPU object a Sendable GoalInput; the reaction t (GoalInput.prog) comes from the scene clock. Designs are laid out in the
// SwiftUI designs' own points (`unit` px per point) and translated into the widget box once. Text is rasterised once per look
// (StingerCanvas.text caches it, Persian stays right-to-left inside its run); everything that moves is GPU work.
// ponytail: digits are proportional (SwiftUI's monospacedDigit not mirrored) and the brightness bumps are white overlays.
import CoreImage
import Synchronization
import UIKit

/// What one frame shows. For the bar design `to` is the progress and `afterText` the total.
struct GoalInput: Sendable {
    var style: GoalWidgetStyle
    var title = ""
    var beforeText = ""
    var afterText = ""
    var targetText = ""
    var deltaText = ""
    var otherText = ""
    var from = 0.0
    var to = 0.0
    var prog = 1.0        // the donation reaction, 0...1 (1 = settled)
    var pins: [String] = []
    var celebrating = false
}

/// One styled piece of text; sizes and tracking in design points.
struct GoalRun {
    var text: String
    var size: CGFloat
    var weight: UIFont.Weight = .bold
    var face = "Manrope"
    var color: UInt32 = 0xFFFF_FFFF
    var alpha: CGFloat = 1
    var tracking: CGFloat = 0
    var mid = false           // y is the line's centre, not its baseline

    func with(_ other: String) -> GoalRun { var copy = self; copy.text = other; return copy }
    func fading(_ value: CGFloat) -> GoalRun { var copy = self; copy.alpha = value; return copy }
    func colored(_ argb: UInt32) -> GoalRun { var copy = self; copy.color = argb; return copy }
    func tracked(_ points: CGFloat) -> GoalRun { var copy = self; copy.tracking = points; return copy }
    func centred() -> GoalRun { var copy = self; copy.mid = true; return copy }
}

struct GoalSize: Sendable { var width: CGFloat, height: CGFloat, asc: CGFloat }

/// A drawn design with its size in design points.
struct GoalPiece {
    var image: CIImage
    var size: CGSize
}

enum GoalSide { case lead, trail, center }

/// Old text leaving (up by `drop`, fading) while the new one comes in (from `rise` below), like GoalSwap / GoalRoll.
struct GoalFlip {
    var before: String
    var after: String
    var progress: Double
    var rise: CGFloat = 8
    var drop: CGFloat = 0
    var minWidth: CGFloat = 0
}

enum GoalArt {
    /// One frame. `box` = the widget's natural area inside the canvas (top-left coordinates, px).
    static func frame(_ input: GoalInput, pen: StingerCanvas, box: CGRect) -> CIImage {
        let style = input.style
        let natural = style.natural
        let ratio = box.width / max(1, natural.width)
        let bar = style.design == "bar"
        let unit = bar ? ratio : ratio * GoalDesignView.scale
        let draw = GoalDraw(pen: pen, unit: unit, input: input)
        let piece = draw.design()
        let room = CGSize(width: natural.width * ratio / unit, height: natural.height * ratio / unit)
        let slack = room.width - piece.size.width
        let left: CGFloat
        switch style.design {
        case "spark": left = slack
        case "island": left = slack / 2
        default: left = 0
        }
        let top = bar ? 0 : (room.height - piece.size.height) / 2
        return piece.image.transformed(by: CGAffineTransform(translationX: box.minX + left * unit, y: box.minY + top * unit))
    }

    /// A still or moving scene for `input`; a moving one plays the reaction over `seconds` (then holds its last frame).
    static func scene(_ input: GoalInput, box: CGRect, seconds: Double? = nil) -> GoalScene {
        GoalScene(still: seconds == nil, draw: { pen, time in
            var now = input
            if let seconds { now.prog = min(1, max(0, time / seconds)) }
            return frame(now, pen: pen, box: box)
        })
    }
}

/// A scene for GoalPlayer; `still` = no per-frame redraw needed.
struct GoalScene {
    var still: Bool
    var draw: @Sendable (StingerCanvas, Double) -> CIImage
    var gpu: GPUScene { GPUScene(draw: draw, moving: !still) }
}

/// The drawing helpers (design points in, canvas pixels out) and the dispatch over `style.design`.
struct GoalDraw {
    let pen: StingerCanvas
    let unit: CGFloat
    let input: GoalInput

    static let white: UInt32 = 0xFFFF_FFFF
    static let ink: UInt32 = 0xFF12_1318
    static let steel: UInt32 = 0xFFD7_D8DE
    static let dim: UInt32 = 0xFFA9_ABB5

    var style: GoalWidgetStyle { input.style }
    var prog: Double { input.prog }
    var accent: UInt32 { style.barColor }

    func design() -> GoalPiece {
        switch style.design {
        case "liquid": liquid()
        case "road": road()
        case "segments": segments()
        case "hairline": hairline()
        case "island": island()
        case "miniring": miniRing()
        case "dots": dots()
        case "spark": spark()
        default: bar()
        }
    }

    /// The reaction's fill level for designs that ease it with `ease`.
    func level(_ ease: Double) -> Double { min(1, max(0, input.from + (input.to - input.from) * ease)) }

    // MARK: geometry

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
    func scaled(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX * unit, y: rect.minY * unit, width: rect.width * unit, height: rect.height * unit) }
    func area(_ x: CGFloat, _ y: CGFloat, _ wide: CGFloat, _ high: CGFloat) -> CGRect { CGRect(x: x, y: y, width: wide, height: high) }

    func moved(_ img: CIImage, x: CGFloat, y: CGFloat) -> CIImage {
        img.transformed(by: CGAffineTransform(translationX: x * unit, y: y * unit))
    }

    // MARK: shapes (rects, centres and radii in points)

    func fill(_ rect: CGRect, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage { pen.fill(scaled(rect), argb, alpha: alpha) }

    func pill(_ rect: CGRect, _ radius: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        pen.roundedRect(scaled(rect), radius: radius * unit, argb, alpha: alpha)
    }

    func capsule(_ rect: CGRect, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage { pill(rect, min(rect.width, rect.height) / 2, argb, alpha: alpha) }

    func disc(_ centre: CGPoint, _ radius: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        pen.disc(pt(centre.x, centre.y), radius * unit, argb, alpha: alpha)
    }

    /// A circle outline `width` thick, its outer edge at `radius`.
    func outline(_ centre: CGPoint, _ radius: CGFloat, width: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        pen.ring(pt(centre.x, centre.y), inner: (radius - width) * unit, outer: radius * unit, argb, alpha: alpha)
    }

    /// A capsule outline drawn inside `rect` (SwiftUI strokeBorder).
    func capsuleBorder(_ rect: CGRect, width: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        pen.minus(capsule(rect, argb, alpha: alpha), capsule(rect.insetBy(dx: width, dy: width), Self.white))
    }

    func clipped(_ img: CIImage, to rect: CGRect) -> CIImage { pen.clip(img, to: fill(rect, Self.white)) }

    /// `shape` (any colour) repainted in `argb`.
    func tinted(_ shape: CIImage, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        let col = StingerCanvas.ciColor(argb)
        return shape.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha * col.alpha),
            "inputBiasVector": CIVector(x: col.red, y: col.green, z: col.blue, w: 0)
        ])
    }

    /// SwiftUI .shadow(color:radius:): the silhouette in `argb`, blurred by radius / 2.
    func glow(_ shape: CIImage, _ argb: UInt32, radius: CGFloat, alpha: Double = 1) -> CIImage {
        guard radius > 0.1, alpha > 0.001, !shape.extent.isEmpty else { return .empty() }
        return pen.opacity(pen.blur(tinted(shape, argb), radius * unit / 2), alpha)
    }

    /// The text widgets' drop shadow (black, `alpha`, down by `dy`, blur radius 3) under `layer`.
    func shadowed(_ layer: CIImage, alpha: Double, dy: CGFloat) -> CIImage {
        guard !layer.extent.isEmpty else { return layer }
        return pen.stack([moved(glow(layer, 0xFF00_0000, radius: 3, alpha: alpha), x: 0, y: dy), layer])
    }

    // MARK: text

    private static let measured = Mutex<[String: GoalSize]>([:])

    /// Width, line height and ascender of a run, in points (cached: moving designs don't re-lay text out every frame).
    func metrics(_ run: GoalRun) -> GoalSize {
        let px = run.size * unit
        let key = "\(run.text)|\(run.face)|\(px)|\(run.weight.rawValue)|\(run.tracking)"
        let cached = Self.measured.withLock { $0[key] }
        if let cached { return GoalSize(width: cached.width / unit, height: cached.height / unit, asc: cached.asc / unit) }
        let font = WidgetFonts.uiFont(face: run.face, size: px, weight: run.weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: run.tracking * unit]
        let width = run.text.isEmpty ? 0 : ceil(NSAttributedString(string: run.text, attributes: attrs).size().width)
        let high = ceil(NSAttributedString(string: run.text.isEmpty ? "Ag" : run.text, attributes: attrs).size().height)
        let found = GoalSize(width: width, height: high, asc: font.ascender)
        Self.measured.withLock { cache in
            if cache.count > 256 { cache.removeAll() }
            cache[key] = found
        }
        return GoalSize(width: width / unit, height: high / unit, asc: font.ascender / unit)
    }

    /// `run` cut with an ellipsis to fit `width` points (SwiftUI's lineLimit(1)).
    func fit(_ run: GoalRun, width: CGFloat) -> GoalRun {
        let full = metrics(run).width
        guard full > width, width > 0 else { return run }
        var count = max(1, Int(Double(run.text.count) * Double(width / full)) - 1)
        var out = run.with(String(run.text.prefix(count)) + "…")
        while count > 1, metrics(out).width > width {
            count -= 1
            out = run.with(String(run.text.prefix(count)) + "…")
        }
        return out
    }

    /// `run` anchored at `x` (its left, right or centre edge) on baseline `y` (or centred on `y` when run.mid).
    /// The run itself is laid out by NSAttributedString, so Persian reads right-to-left while the box stays left-anchored.
    func text(_ run: GoalRun, x: CGFloat, y: CGFloat, side: GoalSide = .lead) -> CIImage {
        guard !run.text.isEmpty, run.alpha > 0.001 else { return .empty() }
        let size = metrics(run)
        let left: CGFloat
        switch side {
        case .lead: left = x
        case .trail: left = x - size.width
        case .center: left = x - size.width / 2
        }
        let midY = run.mid ? y : y - size.asc + size.height / 2
        let spot = pt(left + size.width / 2, midY)
        let gap = run.tracking * unit / 2   // StingerCanvas.text adds half the kerning back when centring
        return pen.text(run.text, at: CGPoint(x: spot.x - gap, y: spot.y), size: run.size * unit, weight: run.weight,
                        color: run.color, alpha: run.alpha, tracking: run.tracking / run.size, face: run.face)
    }

    func flipWidth(_ spec: GoalFlip, _ run: GoalRun) -> CGFloat {
        max(spec.minWidth, metrics(run.with(spec.before)).width, metrics(run.with(spec.after)).width)
    }

    /// The two texts of `spec` on the same anchor: the old one fades out upwards, the new one fades in.
    func flip(_ spec: GoalFlip, _ run: GoalRun, x: CGFloat, y: CGFloat, side: GoalSide) -> CIImage {
        let past = text(run.with(spec.before).fading(run.alpha * CGFloat(1 - spec.progress)), x: x,
                        y: y + spec.drop * CGFloat(spec.progress), side: side)
        let next = text(run.with(spec.after).fading(run.alpha * CGFloat(spec.progress)), x: x,
                        y: y + spec.rise * CGFloat(1 - spec.progress), side: side)
        return pen.stack([past, next])
    }

    // MARK: cached rasters and arcs

    /// A progress arc on a circle of `radius` points, `fraction` of the way round clockwise from 12 o'clock, centred on `centre`.
    func arc(_ radius: CGFloat, width: CGFloat, fraction: Double, at centre: CGPoint, _ argb: UInt32) -> CIImage {
        moved(pen.glArc(radius: radius * unit, width: width * unit, fraction: fraction, color: argb), x: centre.x, y: centre.y)
    }

    /// Track + progress arc of the boards' ring (a `diameter` frame, 3.5 stroke at 26) centred on `centre`.
    func ring(_ diameter: CGFloat, _ progress: Double, at centre: CGPoint) -> CIImage {
        let scale = diameter / 26
        let radius = 10 * scale, width = 3.5 * scale
        let track = outline(centre, radius + width / 2, width: width, style.trackColor)
        return pen.stack([track, arc(radius, width: width, fraction: min(1, max(0, progress)), at: centre, accent)])
    }
}

extension StingerCanvas {
    /// A raster drawn once per look (kept in the symbols cache) and returned upright in top-left space at (0, 0).
    func glShape(_ key: String, size: CGSize, draw: (CGContext) -> Void) -> CIImage {
        let image: CGImage
        if let hit = symbols[key] {
            image = hit
        } else {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            fmt.opaque = false
            let box = CGSize(width: ceil(size.width), height: ceil(size.height))
            let drawn = UIGraphicsImageRenderer(size: box, format: fmt).image(actions: { draw($0.cgContext) })
            guard box.width > 0, box.height > 0, let cg = drawn.cgImage else { return .empty() }
            symbols[key] = cg
            image = cg
        }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(image.height)))
    }

    /// An arc of a circle (px radius and width) from 12 o'clock clockwise, centred on the origin. The stroke is rasterised
    /// once (progressStroke) at a fixed spot; showing more or less of it is a GPU mask, so a growing ring costs no CPU.
    func glArc(radius: CGFloat, width: CGFloat, fraction: Double, color argb: UInt32) -> CIImage {
        let mid = radius + width
        let points = (0...96).map { step -> CGPoint in
            let ang = Double(step) / 96 * 2 * .pi
            return CGPoint(x: mid + radius * CGFloat(sin(ang)), y: mid - radius * CGFloat(cos(ang)))
        }
        return reveal(progressStroke(points, width: width), upTo: fraction, argb)
            .transformed(by: CGAffineTransform(translationX: -mid, y: -mid))
    }
}
