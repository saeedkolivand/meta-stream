import SwiftUI
import UIKit

/// Pure timing math for the splash (ms timeline). No state, so it is trivially checkable -- see Self.demo().
enum SplashMath {
    /// Linear 0...1 progress of a segment [start, start+dur] at time t.
    nonisolated static func lin(_ t: Double, _ start: Double, _ dur: Double) -> Double {
        min(max((t - start) / dur, 0), 1)
    }
    nonisolated static func easeOut(_ t: Double, _ start: Double, _ dur: Double) -> Double {
        let p = 1 - lin(t, start, dur)
        return 1 - p * p * p
    }
    nonisolated static func inOut(_ t: Double, _ start: Double, _ dur: Double) -> Double {
        let p = lin(t, start, dur)
        if p < 0.5 { return 4 * p * p * p }
        let q = -2 * p + 2
        return 1 - q * q * q / 2
    }
    nonisolated static func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
}

#if DEBUG
extension SplashMath {
    static func demo() {
        assert(lin(50, 100, 100) == 0 && lin(250, 100, 100) == 1 && lin(150, 100, 100) == 0.5)
        assert(easeOut(100, 100, 300) == 0 && easeOut(400, 100, 300) == 1 && easeOut(250, 100, 300) > 0.5)
        assert(inOut(100, 100, 300) == 0 && inOut(400, 100, 300) == 1 && abs(inOut(250, 100, 300) - 0.5) < 1e-9)
        assert(inOut(150, 100, 300) < 0.1 && inOut(350, 100, 300) > 0.9)
        assert(mix(2, 4, 0.5) == 3)
    }
}
#endif

/// Cold-launch splash "lens reveal": a titanium-rimmed lens with a red tally light assembles on graphite, then its
/// glass clears and the rim opens to fill the screen with the live app. Overlays ContentView (already running
/// underneath), swallows touches, and calls onDone when finished. Geometry mirrors design/make_icon.py.
struct SplashView: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private typealias M = SplashMath

    var body: some View {
        // Reduce motion: finished lens, hold 600, fade 250, no haptic. Otherwise the 1750 ms choreography.
        let still = reduceMotion
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start) * 1000
            let alpha = still ? 1 - M.lin(t, 600, 250) : 1
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, t: still ? 999 : t)
            }
            .opacity(alpha)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
        .task {
            if still {
                try? await Task.sleep(for: .milliseconds(850))
            } else {
                try? await Task.sleep(for: .milliseconds(1000))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(for: .milliseconds(750))
            }
            onDone()
        }
    }

    // MARK: drawing

    private nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let m = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let diag = (size.width * size.width + size.height * size.height).squareRoot()
        let fade = 1 - M.lin(t, 1000, 200)   // glass, hairline, reflection leave the lens

        // Rim geometry: fixed until 1200, then the window opens to fill the screen.
        let open = M.inOut(t, 1200, 550)
        let rimR = M.mix(0.199 * m, 0.75 * diag + 0.05 * m, open)
        let rimW = M.mix(0.022 * m, 0.035 * m, open)
        let holeR = rimR - rimW / 2

        backdrop(&ctx, size: size, c: c, holeR: holeR, t: t, innerAlpha: fade)

        // Glass: radial dark disc, hairline element ring, soft crescent reflection.
        let glassR = 0.188 * m
        let glassA = M.lin(t, 200, 300) * fade
        if glassA > 0 {
            let glass = disc(c, glassR)
            let glassFill = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [hex(0x16181E), hex(0x020203)]), center: c, startRadius: 0, endRadius: glassR)
            ctx.drawLayer { l in
                l.opacity = glassA
                l.fill(glass, with: glassFill)
            }
            let hairA = 0.07 * M.lin(t, 500, 300) * fade
            ctx.stroke(disc(c, 0.1285 * m), with: .color(.white.opacity(hairA)), lineWidth: 0.0025 * m)
            let reflA = 0.16 * M.lin(t, 600, 300) * fade
            if reflA > 0 { reflection(&ctx, c: c, m: m, clip: glass, alpha: reflA) }
        }

        tally(&ctx, c: c, m: m, t: t)
        wordmark(&ctx, c: c, m: m, t: t)

        // Titanium rim, lit from the top-left; draws itself clockwise from 12 o'clock, then grows with the reveal.
        let rimA = 1 - M.lin(t, 1580, 170)
        let trim = M.inOut(t, 200, 600)
        if rimA > 0, trim > 0 {
            let lit = CGPoint(x: c.x - 0.15 * m, y: c.y - 0.15 * m)
            let shade = CGPoint(x: c.x + 0.15 * m, y: c.y + 0.15 * m)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [hex(0xC8C8CE), hex(0x3A3A3E)]), startPoint: lit, endPoint: shade)
            var ring = Path()
            let steps = 240
            for i in 0...steps {
                let a = -Double.pi / 2 + 2 * Double.pi * trim * Double(i) / Double(steps)
                let pt = CGPoint(x: c.x + rimR * cos(a), y: c.y + rimR * sin(a))
                if i == 0 { ring.move(to: pt) } else { ring.addLine(to: pt) }
            }
            ctx.drawLayer { l in
                l.opacity = rimA
                l.stroke(ring, with: shading, style: StrokeStyle(lineWidth: rimW, lineJoin: .round))
            }
        }
    }

    /// Background gradient (solid launch colour first), always outside the rim's inner edge. Inside it only while the
    /// glass is still up, so the live app shows through the opening afterwards.
    private nonisolated static func backdrop(_ ctx: inout GraphicsContext, size: CGSize, c: CGPoint,
                                             holeR: Double, t: Double, innerAlpha: Double) {
        let full = Path(CGRect(origin: .zero, size: size))
        var outside = full
        outside.addEllipse(in: CGRect(x: c.x - holeR, y: c.y - holeR, width: 2 * holeR, height: 2 * holeR))
        let grad = M.lin(t, 0, 300)
        let top = CGPoint(x: c.x, y: 0)
        let bottom = CGPoint(x: c.x, y: size.height)
        if t < 1000 {
            paint(&ctx, full, alpha: 1, grad: grad, eo: false, top: top, bottom: bottom)
        } else {
            paint(&ctx, outside, alpha: 1, grad: grad, eo: true, top: top, bottom: bottom)
            if innerAlpha > 0 {
                paint(&ctx, disc(c, holeR), alpha: innerAlpha, grad: grad, eo: false, top: top, bottom: bottom)
            }
        }
    }

    private nonisolated static func paint(_ ctx: inout GraphicsContext, _ path: Path, alpha: Double, grad: Double,
                                          eo: Bool, top: CGPoint, bottom: CGPoint) {
        let style = FillStyle(eoFill: eo)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [hex(0x1C1C1F), hex(0x0A0A0C)]), startPoint: top, endPoint: bottom)
        ctx.drawLayer { l in
            l.opacity = alpha
            l.fill(path, with: .color(hex(0x121214)), style: style)
        }
        ctx.drawLayer { l in
            l.opacity = alpha * grad
            l.fill(path, with: shading, style: style)
        }
    }

    /// Crescent between two offset circles, clipped to the glass and softly blurred.
    private nonisolated static func reflection(_ ctx: inout GraphicsContext, c: CGPoint, m: Double,
                                               clip: Path, alpha: Double) {
        let r = 0.169 * m
        let a = CGPoint(x: c.x - 0.019 * m, y: c.y - 0.019 * m)
        let b = CGPoint(x: c.x, y: c.y + 0.0125 * m)
        var crescent = disc(a, r)
        crescent.addEllipse(in: CGRect(x: b.x - r, y: b.y - r, width: 2 * r, height: 2 * r))
        ctx.drawLayer { outer in
            outer.clip(to: clip)
            outer.drawLayer { l in
                l.opacity = alpha
                l.addFilter(.blur(radius: 0.006 * m))
                l.fill(crescent, with: .color(.white), style: FillStyle(eoFill: true))
            }
        }
    }

    /// Red tally light: bloom, warm vertical gradient, soft glassy highlight. Powers on smoothly 100-550.
    private nonisolated static func tally(_ ctx: inout GraphicsContext, c: CGPoint, m: Double, t: Double) {
        let dotR = 0.0389 * m
        let out = 1 - M.lin(t, 1000, 150)
        let dotA = M.easeOut(t, 100, 450) * out
        guard dotA > 0 else { return }
        let rise = 0.9 * M.easeOut(t, 100, 250)
        let settle = 0.25 * M.inOut(t, 350, 250)
        let bloomA = (rise - settle) * out
        let bloomRadius = dotR * M.mix(1.4, 2.2, M.easeOut(t, 100, 500))
        let bloomColor = hex(0xFF2814)
        let bloom = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [bloomColor.opacity(bloomA), bloomColor.opacity(0)]),
            center: c, startRadius: 0, endRadius: bloomRadius)
        ctx.fill(disc(c, bloomRadius), with: bloom)

        let dot = disc(c, dotR)
        let body = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [hex(0xFF5A3C), hex(0xE8101E)]),
            startPoint: CGPoint(x: c.x, y: c.y - dotR), endPoint: CGPoint(x: c.x, y: c.y + dotR))
        let hiR = 0.72 * dotR
        let hiC = CGPoint(x: c.x, y: c.y - 0.32 * dotR)
        ctx.drawLayer { l in
            l.opacity = dotA
            l.fill(dot, with: body)
            l.clip(to: dot)
            l.drawLayer { h in
                h.addFilter(.blur(radius: 0.12 * dotR))
                h.fill(disc(hiC, hiR), with: .color(.white.opacity(0.28)))
            }
        }
    }

    /// "MetaStream": rises 0.015m -> 0 while tracking tightens 0.32em -> 0.20em; fades out 1000-1150.
    private nonisolated static func wordmark(_ ctx: inout GraphicsContext, c: CGPoint, m: Double, t: Double) {
        let e = M.easeOut(t, 650, 350)
        let alpha = 0.92 * e * (1 - M.lin(t, 1000, 150))
        guard alpha > 0 else { return }
        let fontSize = 0.048 * m
        let spacing = fontSize * M.mix(0.32, 0.20, e)
        let text = Text("MetaStream")
            .font(.system(size: fontSize, weight: .regular))
            .kerning(spacing)
            .foregroundStyle(Color.white)
        let y = c.y + 0.34 * m + 0.015 * m * (1 - e)
        ctx.drawLayer { l in
            l.opacity = alpha
            // Kerning also trails the last glyph; shift by half of it to keep the word optically centred.
            l.draw(l.resolve(text), at: CGPoint(x: c.x + spacing / 2, y: y), anchor: .center)
        }
    }

    private nonisolated static func disc(_ c: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    private nonisolated static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
