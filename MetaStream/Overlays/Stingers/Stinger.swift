// Built-in stingers, drawn live: one full-canvas image per frame, so speed, colours and the name follow the settings
// with no video file. Each kind's art reproduces its design board (the "Scene Templates" canvas) frame for frame:
// `q` is the position in the board's 6 s loop (0...1), so a keyframe at 40% is q 0.40 and a CSS delay of 0.02 x dur
// shifts q by 0.02. Adding a stinger = one case here + one StingerArt function.
import CoreGraphics
import CoreImage
import Foundation
import UIKit

struct StingerStyle: Codable, Equatable, Sendable {
    var speed = 1.0                    // 0.4...2, multiplies the board's tempo
    var accent: UInt32 = 0xFF53_FC18   // ARGB, like the widget styles
    var ink: UInt32 = 0xFF0B_0B0C      // the panel colour that covers the frame
    var showName = true
    var name = ""                      // empty = no name drawn
    var tone = "warm"                  // film burn: "warm" | "cool" | "accent"
    var tally: UInt32 = 0xFFE8_101E    // lens: the tally light

    private static let key = "stingerStyle"

    static func load() -> StingerStyle {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(StingerStyle.self, from: $0) } ?? StingerStyle()
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

enum StingerKind: String, CaseIterable, Sendable {
    case lens, aperture, route, viewfinder, liquid, ripple, tunnel, burn

    var title: String {
        switch self {
        case .lens: "Lens"
        case .aperture: "Aperture"
        case .route: "Route & pin"
        case .viewfinder: "Viewfinder"
        case .liquid: "Liquid"
        case .ripple: "Ripple"
        case .tunnel: "Tunnel"
        case .burn: "Film burn"
        }
    }

    /// Loop positions on the board: first moving frame, fully covered (the scene switches here), last frame.
    var span: (start: Double, cut: Double, end: Double) {
        switch self {
        case .lens: (0.245, 0.46, 0.65)
        case .aperture: (0.25, 0.45, 0.67)
        case .route: (0.24, 0.50, 0.64)
        case .viewfinder: (0.25, 0.46, 0.66)
        case .liquid: (0.23, 0.50, 0.77)
        case .ripple: (0.25, 0.49, 0.77)
        case .tunnel: (0.25, 0.51, 0.82)
        case .burn: (0.25, 0.484, 0.72)
        }
    }

    static let loopSeconds = 6.0

    private func speed(_ s: StingerStyle) -> Double { min(max(s.speed, 0.2), 4) }
    func seconds(_ s: StingerStyle) -> Double { (span.end - span.start) * Self.loopSeconds / speed(s) }
    func cutSeconds(_ s: StingerStyle) -> Double { (span.cut - span.start) * Self.loopSeconds / speed(s) }

    /// One frame `t` seconds in, into a top-left-origin context of `size` (UIKit drawing is pushed for text).
    func draw(_ c: CGContext, size: CGSize, t: Double, style: StingerStyle) {
        let q = span.start + t * speed(style) / Self.loopSeconds
        switch self {
        case .lens: StingerArt.lens(c, size, q, style)
        case .aperture: StingerArt.aperture(c, size, q, style)
        case .route: StingerArt.route(c, size, q, style)
        case .viewfinder: StingerArt.viewfinder(c, size, q, style)
        case .liquid: StingerArt.liquid(c, size, q, style)
        case .ripple: StingerArt.ripple(c, size, q, style)
        case .tunnel: StingerArt.tunnel(c, size, q, style)
        case .burn: StingerArt.burn(c, size, q, style)
        }
    }

    /// A full-resolution frame as one bitmap (tests; the stream uses `ciFrame`).
    func frame(size: CGSize, t: Double, style: StingerStyle) -> OverlayBitmap? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0, let c = Self.context(w, h) else { return nil }
        UIGraphicsPushContext(c)
        draw(c, size: CGSize(width: w, height: h), t: t, style: style)
        UIGraphicsPopContext()
        return c.makeImage().map { OverlayBitmap(image: $0) }
    }

    /// The stream's frame, for the GPU renderer. Shapes draw at `shapeScale` of the canvas and are scaled up on the GPU
    /// (big flat fills lose nothing, and the CPU fills a quarter of the pixels); the name draws full size on its own
    /// layer (it is the only thing UIKit draws, into the pushed context) so the text stays sharp.
    func ciFrame(size: CGSize, t: Double, style: StingerStyle, shapeScale: CGFloat = 0.5) -> CIImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        let sw = max(1, Int((CGFloat(w) * shapeScale).rounded())), sh = max(1, Int((CGFloat(h) * shapeScale).rounded()))
        guard w > 0, h > 0, let shapes = Self.context(sw, sh) else { return nil }
        shapes.scaleBy(x: CGFloat(sw) / CGFloat(w), y: CGFloat(sh) / CGFloat(h))   // the art keeps drawing in canvas units
        let text = style.showName && !style.name.isEmpty ? Self.context(w, h) : nil
        UIGraphicsPushContext(text ?? shapes)
        draw(shapes, size: CGSize(width: w, height: h), t: t, style: style)
        UIGraphicsPopContext()
        guard let art = shapes.makeImage() else { return nil }
        var image = CIImage(cgImage: art).transformed(by: CGAffineTransform(scaleX: CGFloat(w) / CGFloat(sw), y: CGFloat(h) / CGFloat(sh)))
        if let label = text?.makeImage() { image = CIImage(cgImage: label).composited(over: image) }
        return image.cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// 8-bit sRGB BGRA premultiplied (what UIGraphicsImageRenderer gives OverlayRaster), origin top-left like UIKit.
    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: 1, y: -1)
        return c
    }
}

/// The art. Each function lives in StingerArt+*.swift and draws one frame for loop position `q`.
/// Geometry: the boards are 1920x1080. Things laid out around the centre scale by `unit(size)` (short side / 1080);
/// anything that must cover the whole frame sizes from `halfDiagonal(size)` so portrait canvases are covered too.
enum StingerArt {
    static func unit(_ size: CGSize) -> CGFloat { min(size.width, size.height) / 1080 }
    static func center(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    static func halfDiagonal(_ size: CGSize) -> CGFloat { (size.width * size.width + size.height * size.height).squareRoot() / 2 }

    static func color(_ argb: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255 * alpha)
    }

    /// CSS color-mix(in srgb, argb, white f).
    static func mixWhite(_ argb: UInt32, _ f: Double) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 { UInt32((Double((argb >> s) & 0xFF) * (1 - f) + 255 * f).rounded()) << s }
        return (argb & 0xFF00_0000) | ch(16) | ch(8) | ch(0)
    }

    /// Text colour on `ink`: near-black on light panels, off-white on dark ones (the boards' --fg).
    static func fg(on ink: UInt32) -> UInt32 {
        let lum = 0.299 * Double((ink >> 16) & 0xFF) + 0.587 * Double((ink >> 8) & 0xFF) + 0.114 * Double(ink & 0xFF)
        return lum > 150 ? 0xFF0B_0B0C : 0xFFF2_F1EC
    }

    /// Draws `text` centred on `at` (UIKit coordinates; the caller's context is pushed). `tracking` is in em.
    static func name(_ text: String, at: CGPoint, size: CGFloat, weight: UIFont.Weight = .semibold, color argb: UInt32,
                     alpha: CGFloat = 1, tracking: CGFloat = -0.02, scale: CGFloat = 1) {
        guard !text.isEmpty, alpha > 0.001 else { return }
        let font = WidgetFonts.uiFont(face: "", size: size * scale, weight: weight)
        let str = NSAttributedString(string: text, attributes: [
            .font: font, .kern: tracking * size * scale,
            .foregroundColor: UIColor(cgColor: color(argb, alpha: alpha)),
        ])
        let b = str.size()
        // Kerning trails the last glyph too; shift by half of it to stay optically centred (as the splash does).
        str.draw(at: CGPoint(x: at.x - b.width / 2 + tracking * size * scale / 2, y: at.y - b.height / 2))
    }
}

/// A CSS cubic-bezier timing function.
struct Curve: Sendable {
    let x1: Double, y1: Double, x2: Double, y2: Double

    static let linear = Curve(x1: 0, y1: 0, x2: 1, y2: 1)
    static let ease = Curve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeInOut = Curve(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    init(x1: Double, y1: Double, x2: Double, y2: Double) { (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2) }
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.init(x1: x1, y1: y1, x2: x2, y2: y2) }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {   // bisection: x(t) is monotonic for 0 <= x1, x2 <= 1
            t = (lo + hi) / 2
            if bez(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return bez(t, y1, y2)
    }

    /// CSS keyframes: the value at `q` for stops [(position, value)] sorted by position, each segment eased by this
    /// curve (CSS applies the timing function per keyframe segment). Before the first stop it holds the first value.
    func track(_ q: Double, _ stops: [(Double, Double)]) -> Double {
        guard let first = stops.first else { return 0 }
        if q <= first.0 { return first.1 }
        for (a, b) in zip(stops, stops.dropFirst()) where q <= b.0 {
            return b.0 <= a.0 ? b.1 : a.1 + (b.1 - a.1) * self((q - a.0) / (b.0 - a.0))
        }
        return stops.last!.1
    }
}
