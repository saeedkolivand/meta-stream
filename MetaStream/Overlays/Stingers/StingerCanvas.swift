// What the stinger art draws with: Core Image recipes, which the GPU renderer evaluates on the GPU when it composites
// the frame. Coordinates are the canvas's with a top-left origin (like the boards); StingerKind.ciFrame flips the
// finished picture once. Only the name text and the route's stroke touch the CPU, each drawn once and then cached.
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class StingerCanvas {
    let size: CGSize
    private var texts: [String: CGImage] = [:]
    private var strokes: [String: CIImage] = [:]
    var symbols: [String: CGImage] = [:]   // SF Symbols rendered once (see AlertIslandGPU.swift)

    init(size: CGSize) { self.size = size }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }
    var unit: CGFloat { min(size.width, size.height) / 1080 }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var halfDiagonal: CGFloat { (size.width * size.width + size.height * size.height).squareRoot() / 2 }

    static func ciColor(_ argb: UInt32, alpha: CGFloat = 1) -> CIColor {
        CIColor(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255 * alpha,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) ?? .clear
    }

    // MARK: shapes (top-left coordinates)

    func fill(_ r: CGRect, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        guard alpha > 0.001, r.width > 0, r.height > 0 else { return .empty() }
        return CIImage(color: Self.ciColor(argb, alpha: alpha)).cropped(to: r)
    }

    /// A filled circle with a 1.5 px soft edge (anti-aliasing).
    func disc(_ c: CGPoint, _ r: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        guard r > 0.25, alpha > 0.001 else { return .empty() }
        let f = CIFilter.radialGradient()
        f.center = c
        f.radius0 = Float(max(0, r - 0.75))
        f.radius1 = Float(r + 0.75)
        f.color0 = Self.ciColor(argb, alpha: alpha)
        f.color1 = Self.ciColor(argb, alpha: 0)
        return (f.outputImage ?? .empty()).cropped(to: CGRect(x: c.x - r - 1, y: c.y - r - 1, width: 2 * r + 2, height: 2 * r + 2))
    }

    /// A ring between two radii (`inner` 0 = a disc).
    func ring(_ c: CGPoint, inner: CGFloat, outer: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        guard outer > inner else { return .empty() }
        let d = disc(c, outer, argb, alpha: alpha)
        return inner > 0.25 ? minus(d, disc(c, inner, 0xFFFF_FFFF)) : d
    }

    func roundedRect(_ r: CGRect, radius: CGFloat, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        guard alpha > 0.001, r.width > 0, r.height > 0 else { return .empty() }
        let f = CIFilter.roundedRectangleGenerator()
        f.extent = r
        f.radius = Float(min(radius, min(r.width, r.height) / 2))
        f.color = Self.ciColor(argb, alpha: alpha)
        return f.outputImage ?? .empty()
    }

    /// Unbounded linear gradient; `clip` it to a shape.
    func linear(_ from: CGPoint, _ to: CGPoint, _ a: UInt32, _ b: UInt32, alphaA: CGFloat = 1, alphaB: CGFloat = 1) -> CIImage {
        let f = CIFilter.linearGradient()
        f.point0 = from
        f.point1 = to
        f.color0 = Self.ciColor(a, alpha: alphaA)
        f.color1 = Self.ciColor(b, alpha: alphaB)
        return f.outputImage ?? .empty()
    }

    /// Unbounded radial gradient from `a` at r0 to `b` at r1 (and beyond: `b` keeps going).
    func radial(_ c: CGPoint, _ r0: CGFloat, _ r1: CGFloat, _ a: UInt32, _ b: UInt32, alphaA: CGFloat = 1, alphaB: CGFloat = 1) -> CIImage {
        let f = CIFilter.radialGradient()
        f.center = c
        f.radius0 = Float(max(0, r0))
        f.radius1 = Float(max(r0 + 0.5, r1))
        f.color0 = Self.ciColor(a, alpha: alphaA)
        f.color1 = Self.ciColor(b, alpha: alphaB)
        return f.outputImage ?? .empty()
    }

    // MARK: combining

    /// `img` with `hole` cut out (where hole is opaque, img disappears).
    func minus(_ img: CIImage, _ hole: CIImage) -> CIImage {
        img.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: hole])
    }

    /// `img` only where `shape` is opaque.
    func clip(_ img: CIImage, to shape: CIImage) -> CIImage {
        img.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: shape])
    }

    /// CSS opacity on a whole group.
    func opacity(_ img: CIImage, _ a: Double) -> CIImage {
        if a >= 0.999 { return img }
        if a <= 0.001 { return .empty() }
        return img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))])
    }

    func blur(_ img: CIImage, _ sigma: CGFloat) -> CIImage { sigma < 0.3 ? img : img.applyingGaussianBlur(sigma: Double(sigma)) }

    /// Scale and rotate (degrees, clockwise on screen) about `point`.
    func transform(_ img: CIImage, about point: CGPoint, scale: CGFloat = 1, rotate degrees: CGFloat = 0) -> CIImage {
        let t = CGAffineTransform(translationX: point.x, y: point.y)
            .rotated(by: degrees * .pi / 180)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -point.x, y: -point.y)
        return img.transformed(by: t)
    }

    func screen(_ img: CIImage, over base: CIImage) -> CIImage {
        img.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: base])
    }

    /// Layers bottom to top.
    func stack(_ layers: [CIImage]) -> CIImage { layers.reduce(CIImage.empty()) { $1.composited(over: $0) } }

    /// The SVG "goo" filter: blur the shapes, then a steep alpha threshold (alpha x 36 - 14), filled with `argb`.
    /// Done at a quarter size, which also keeps the big blur cheap.
    func goo(_ shapes: CIImage, sigma: CGFloat, _ argb: UInt32) -> CIImage {
        let k: CGFloat = 0.25
        let small = blur(shapes.transformed(by: CGAffineTransform(scaleX: k, y: k)), sigma * k)
        let mask = small.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 36),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: -14),
        ]).applyingFilter("CIColorClamp").transformed(by: CGAffineTransform(scaleX: 1 / k, y: 1 / k))
        return clip(fill(bounds, argb), to: mask)
    }

    // MARK: text (drawn once per look, then moved and faded on the GPU)

    /// `text` centred on `at`. `tracking` is in em (it changes the layout, so each distinct value is its own render).
    /// `face` is a WidgetFonts face id ("" = system).
    func text(_ text: String, at: CGPoint, size: CGFloat, weight: UIFont.Weight = .semibold, color argb: UInt32,
              alpha: CGFloat = 1, tracking: CGFloat = -0.02, scale: CGFloat = 1, face: String = "") -> CIImage {
        guard !text.isEmpty, alpha > 0.001, size > 0 else { return .empty() }
        let key = "\(text)|\(Int(size * 2))|\(weight.rawValue)|\(argb)|\(Int((tracking * 200).rounded()))|\(face)"
        let image: CGImage
        if let cached = texts[key] {
            image = cached
        } else {
            let font = WidgetFonts.uiFont(face: face, size: size, weight: weight)
            let str = NSAttributedString(string: text, attributes: [
                .font: font, .kern: tracking * size, .foregroundColor: UIColor(cgColor: StingerArt.color(argb)),
            ])
            let b = str.size()
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            fmt.opaque = false
            guard b.width > 0, let cg = UIGraphicsImageRenderer(size: CGSize(width: ceil(b.width), height: ceil(b.height)), format: fmt)
                .image(actions: { _ in str.draw(at: .zero) }).cgImage else { return .empty() }
            if texts.count > 64 { texts.removeAll() }
            texts[key] = cg
            image = cg
        }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // Into top-left space (the frame is flipped once at the end), centred, kerning's trailing gap split.
        let placed = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))
            .transformed(by: CGAffineTransform(translationX: at.x - w / 2 + tracking * size / 2, y: at.y - h / 2))
        return opacity(scale == 1 ? placed : transform(placed, about: at, scale: scale), Double(alpha))
    }

    // MARK: drawn-on strokes

    /// A polyline stroked once on the CPU with its progress (0...1 along its length) coded in the red channel, so
    /// `reveal` can draw any prefix of it on the GPU. Cached per shape.
    func progressStroke(_ points: [CGPoint], width: CGFloat) -> CIImage {
        let key = "\(points.count)|\(points.first.map { "\($0)" } ?? "")|\(points.last.map { "\($0)" } ?? "")|\(width)"
        if let s = strokes[key] { return s }
        guard points.count > 1 else { return .empty() }
        var cum: [CGFloat] = [0]
        for i in 1..<points.count { cum.append(cum[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)) }
        let total = max(cum.last ?? 1, 0.001)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let cg = UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            let c = r.cgContext
            c.setLineWidth(width)
            c.setLineCap(.round)
            for i in 1..<points.count {
                c.setStrokeColor(UIColor(red: cum[i] / total, green: 0, blue: 0, alpha: 1).cgColor)
                c.move(to: points[i - 1])
                c.addLine(to: points[i])
                c.strokePath()
            }
        }.cgImage
        let s = cg.map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)) } ?? .empty()
        strokes[key] = s
        return s
    }

    /// The first `fraction` of a progressStroke, in `argb`.
    func reveal(_ stroke: CIImage, upTo fraction: Double, _ argb: UInt32, alpha: CGFloat = 1) -> CIImage {
        guard fraction > 0.0005, alpha > 0.001 else { return .empty() }
        let k: CGFloat = 400   // edge sharpness along the path
        let col = Self.ciColor(argb)
        let shown = stroke.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: -k, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: col.red, y: col.green, z: col.blue, w: k * CGFloat(fraction) + 1),
        ]).applyingFilter("CIColorClamp")
        return opacity(clip(shown, to: stroke), Double(alpha * col.alpha))
    }
}
