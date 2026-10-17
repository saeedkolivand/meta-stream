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

    /// The frame `t` seconds in, as a Core Image recipe in top-left canvas coordinates (see StingerCanvas).
    func art(_ k: StingerCanvas, t: Double, style: StingerStyle) -> CIImage {
        let q = span.start + t * speed(style) / Self.loopSeconds
        switch self {
        case .lens: return StingerArt.lens(k, q, style)
        case .aperture: return StingerArt.aperture(k, q, style)
        case .route: return StingerArt.route(k, q, style)
        case .viewfinder: return StingerArt.viewfinder(k, q, style)
        case .liquid: return StingerArt.liquid(k, q, style)
        case .ripple: return StingerArt.ripple(k, q, style)
        case .tunnel: return StingerArt.tunnel(k, q, style)
        case .burn: return StingerArt.burn(k, q, style)
        }
    }

    /// The stream's frame: the art flipped into Core Image's bottom-left space and cut to the canvas. The GPU renderer
    /// evaluates it on the GPU while compositing; nothing here touches pixels.
    func ciFrame(_ k: StingerCanvas, t: Double, style: StingerStyle) -> CIImage {
        art(k, t: t, style: style)
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: k.size.height))
            .cropped(to: k.bounds)
    }

    /// A frame rendered to an 8-bit sRGB BGRA bitmap (the settings preview, tests).
    func frame(_ k: StingerCanvas, t: Double, style: StingerStyle, context: CIContext) -> CGImage? {
        context.createCGImage(ciFrame(k, t: t, style: style), from: k.bounds, format: .BGRA8,
                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}

/// The art. Each function lives in StingerArt+*.swift and returns one frame for loop position `q`, built from
/// StingerCanvas recipes. Geometry: the boards are 1920x1080. Things laid out around the centre scale by `k.unit`
/// (short side / 1080); anything that must cover the whole frame sizes from `k.halfDiagonal` so portrait is covered too.
enum StingerArt {
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
