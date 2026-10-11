import SwiftUI

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
    nonisolated static func easeIn(_ t: Double, _ start: Double, _ dur: Double) -> Double {
        let p = lin(t, start, dur)
        return p * p * p
    }
    /// Damped spring 0 -> 1 with a ~1.15 overshoot, settled by the end of the segment.
    nonisolated static func spring(_ t: Double, _ start: Double, _ dur: Double) -> Double {
        let p = lin(t, start, dur)
        if p >= 1 { return 1 }
        return 1 - exp(-5.4 * p) * cos(9 * p)
    }
    /// Heartbeat bump 1 -> 1.12 -> 1 over 250 ms starting at `start`.
    nonisolated static func beat(_ t: Double, _ start: Double) -> Double {
        1 + 0.12 * sin(.pi * lin(t, start, 250))
    }
}

#if DEBUG
extension SplashMath {
    static func demo() {
        assert(lin(50, 100, 100) == 0 && lin(250, 100, 100) == 1 && lin(150, 100, 100) == 0.5)
        assert(easeOut(100, 100, 300) == 0 && easeOut(400, 100, 300) == 1 && easeOut(250, 100, 300) > 0.5)
        assert(easeIn(250, 100, 300) < 0.5 && easeIn(400, 100, 300) == 1)
        assert(spring(150, 150, 450) == 0 && spring(600, 150, 450) == 1)
        assert((0...450).map { spring(150 + Double($0), 150, 450) }.max()! > 1.1)
        assert(beat(0, 0) == 1 && beat(250, 0) < 1.0001 && abs(beat(125, 0) - 1.12) < 1e-9)
    }
}
#endif

/// Cold-launch splash: the app icon's "live" mark animates in, pulses, then zooms through to reveal the app.
/// Overlays ContentView (already running underneath), swallows touches, and calls onDone when finished.
struct SplashView: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private typealias M = SplashMath

    var body: some View {
        // Reduce motion: static mark, hold 600, fade 250. Otherwise the full 1950 ms choreography.
        let still = reduceMotion
        let total: Double = still ? 850 : 1950
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start) * 1000
            let alpha = still ? 1 - M.lin(t, 600, 250) : 1 - M.lin(t, 1650, 300)
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, t: t, still: still)
            }
            .opacity(alpha)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .milliseconds(Int(total)))
            onDone()
        }
    }

    // MARK: drawing

    private nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, still: Bool) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let u = 0.62 * min(size.width, size.height) / 55
        let mt = still ? 1100 : t   // reduce motion freezes the mark at its finished state

        // Background: native launch colour, crossfading into the gradient over 0-350.
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .color(Color(red: 0x1D / 255, green: 0x0A / 255, blue: 0x5D / 255)))
        ctx.drawLayer { l in
            l.opacity = M.lin(mt, 0, 350)
            l.fill(Path(full), with: .linearGradient(
                Gradient(colors: [Self.hex(0x340E9E), Self.hex(0x06051C)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        }

        // Zoom through the mark: 1 -> 9 around the screen centre, ease-in.
        let zoom = still ? 1 : 1 + 8 * M.easeIn(t, 1500, 450)
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -c.x, y: -c.y)

        // Violet glow: fades in while scaling 0.6 -> 1.
        let vIn = M.easeOut(mt, 0, 500)
        Self.glow(&ctx, c, radius: 42 * u * (0.6 + 0.4 * vIn), color: Self.hex(0x6D3BFF), peak: 0.65 * vIn)

        // Dot: spring pop at 150 (+ heartbeat on each pulse ring start), red glow fades in with it.
        let pop = M.spring(mt, 150, 450)
        Self.glow(&ctx, c, radius: 16 * u, color: Self.hex(0xFF1F5A), peak: 0.6 * M.lin(mt, 150, 300))

        // Arcs draw outward from their midpoint: sweep 0 -> 42 deg, alpha 0 -> 1.
        let inner = M.easeOut(mt, 350, 300)
        let outer = M.easeOut(mt, 550, 300)
        let white = Color.white
        let cyanToPink = Gradient(colors: [Self.hex(0x3DE8FF), Self.hex(0xC84BFF)])
        let outerShade = GraphicsContext.Shading.linearGradient(
            cyanToPink, startPoint: CGPoint(x: c.x, y: c.y - 25.5 * u), endPoint: CGPoint(x: c.x, y: c.y + 25.5 * u))
        ctx.drawLayer { l in
            l.opacity = inner
            for mid in [0.0, 180.0] { Self.arc(&l, c, 13 * u, mid, 42 * inner, 5 * u, .color(white)) }
        }
        ctx.drawLayer { l in
            l.opacity = outer
            for mid in [0.0, 180.0] { Self.arc(&l, c, 23 * u, mid, 42 * outer, 5 * u, outerShade) }
        }

        // Broadcast pulse: two rings, thin outlines of the outer-arc gradient.
        if !still {
            let maxR = 0.75 * (size.width * size.width + size.height * size.height).squareRoot()
            for s in [900.0, 1150.0] where t >= s {
                let e = M.easeOut(t, s, 700)
                let r = 8 * u + (maxR - 8 * u) * e
                ctx.drawLayer { l in
                    l.opacity = 0.7 * (1 - e)
                    l.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                             with: outerShade, lineWidth: 1.2 * u)
                }
            }
        }

        // Dot + highlight.
        var scale = pop
        if !still { scale *= max(M.beat(t, 900), M.beat(t, 1150)) }
        ctx.drawLayer { l in
            l.translateBy(x: c.x, y: c.y)
            l.scaleBy(x: scale, y: scale)
            l.translateBy(x: -c.x, y: -c.y)
            let r = 7.5 * u
            l.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .linearGradient(Gradient(colors: [Self.hex(0xFF7A3D), Self.hex(0xFF1F5A)]),
                                         startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
            let h = 2.4 * u
            l.fill(Path(ellipseIn: CGRect(x: c.x - 2.6 * u - h, y: c.y - 2.6 * u - h, width: 2 * h, height: 2 * h)),
                   with: .color(.white.opacity(0.35)))
        }

        // Wordmark: fades in, rises 6u -> 0, letter spacing 0.35em -> 0.08em; fades out 1500-1650.
        let w = M.easeOut(mt, 700, 400)
        let wAlpha = w * (still ? 1 : 1 - M.lin(t, 1500, 150))
        if wAlpha > 0 {
            let fontSize = 9 * u
            let text = Text("MetaStream")
                .font(.system(size: fontSize, weight: .semibold))
                .kerning(fontSize * (0.35 - 0.27 * w))
                .foregroundColor(.white)
            ctx.drawLayer { l in
                l.opacity = wAlpha
                l.draw(l.resolve(text), at: CGPoint(x: c.x, y: c.y + 40 * u + 6 * u * (1 - w)), anchor: .center)
            }
        }
    }

    /// Radial glow: peak alpha at the centre, 0.5 -> 0.16/0.65 of it, 0 at the edge.
    private nonisolated static func glow(_ ctx: inout GraphicsContext, _ c: CGPoint, radius: Double, color: Color, peak: Double) {
        guard peak > 0, radius > 0 else { return }
        let g = Gradient(stops: [
            .init(color: color.opacity(peak), location: 0),
            .init(color: color.opacity(peak * 0.16 / 0.65), location: 0.5),
            .init(color: color.opacity(0), location: 1),
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius)),
                 with: .radialGradient(g, center: c, startRadius: 0, endRadius: radius))
    }

    /// Round-capped arc symmetric about `mid` degrees. Built as a polyline so the winding direction can't go wrong.
    private nonisolated static func arc(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: Double, _ mid: Double, _ sweep: Double,
                     _ width: Double, _ shading: GraphicsContext.Shading) {
        guard sweep > 0.05 else { return }
        var p = Path()
        let steps = 24
        for i in 0...steps {
            let a = (mid - sweep + 2 * sweep * Double(i) / Double(steps)) * .pi / 180
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private nonisolated static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
