import SwiftUI

/// The scene editor's canvas: the output frame at its real aspect, every visible layer drawn where the compositor will
/// put it, direct manipulation with snapping. Gestures only touch local state; the store is written once, when the
/// finger lifts (a store write rebuilds the on-stream scene, so never per frame).
struct SceneCanvasView: View {
    let layers: [OverlayLayer]
    let canvas: CGSize
    @Binding var selected: Int?
    @ObservedObject var emotes: Emotes
    /// Called once per finished gesture with the layer's new value.
    let commit: (Int, OverlayLayer) -> Void

    @ObservedObject private var store = OverlayStore.shared
    @EnvironmentObject private var streamer: Streamer
    @EnvironmentObject private var chat: ChatFeed
    @State private var active: Int?
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var snapKey = ""

    private let snapDistance: CGFloat = 12

    init(layers: [OverlayLayer], canvas: CGSize, selected: Binding<Int?>, emotes: Emotes, commit: @escaping (Int, OverlayLayer) -> Void) {
        self.layers = layers
        self.canvas = canvas
        self._selected = selected
        self.emotes = emotes
        self.commit = commit
    }

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / max(canvas.width, 1)
            ZStack(alignment: .topLeading) {
                background(geo.size)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ZStack(alignment: .topLeading) {
                        ForEach(layers.indices, id: \.self) { i in
                            if layers[i].visible { layerView(i, k: k) }
                        }
                    }
                }
                if let s = selected, layers.indices.contains(s), layers[s].visible { outline(live(s, k: k).rect) }
                if active != nil, let a = active, layers.indices.contains(a) { guides(live(a, k: k), size: geo.size) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(gesture(k: k))
        }
        .aspectRatio(canvas.width / max(canvas.height, 1), contentMode: .fit)
        .accessibilityLabel("Scene canvas")
    }

    // MARK: drawing

    private func background(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
            Path { p in
                for f: CGFloat in [1.0 / 3, 2.0 / 3] {
                    p.move(to: CGPoint(x: size.width * f, y: 0)); p.addLine(to: CGPoint(x: size.width * f, y: size.height))
                    p.move(to: CGPoint(x: 0, y: size.height * f)); p.addLine(to: CGPoint(x: size.width, y: size.height * f))
                }
            }
            .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder private func layerView(_ i: Int, k: CGFloat) -> some View {
        let r = live(i, k: k).rect
        let e = effective(layers[i])
        LayerPreview(layer: e, natural: natural(e), size: r.size, emotes: emotes, chat: chat.recent)
            .offset(x: r.minX, y: r.minY)
    }

    private func outline(_ r: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().stroke(Color.accentColor, lineWidth: 1.5)
            ForEach(0..<4, id: \.self) { c in
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    .offset(x: (c % 2 == 0 ? 0 : r.width) - 4, y: (c < 2 ? 0 : r.height) - 4)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .offset(x: r.minX, y: r.minY)
        .allowsHitTesting(false)
    }

    private func guides(_ l: (rect: CGRect, gx: [CGFloat], gy: [CGFloat]), size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(l.gx, id: \.self) { x in Rectangle().fill(.yellow).frame(width: 1, height: size.height).offset(x: x) }
            ForEach(l.gy, id: \.self) { y in Rectangle().fill(.yellow).frame(width: size.width, height: 1).offset(y: y) }
        }
        .allowsHitTesting(false)
    }

    // MARK: geometry (output px unless a name says view)

    private func fit() -> Fit? {
        store.pack.map { overlayFit(canvasW: $0.canvasW, canvasH: $0.canvasH, outW: canvas.width, outH: canvas.height) }
    }

    /// The layer as the compositor sees it: {tokens} resolved, so the box matches what's drawn.
    private func effective(_ l: OverlayLayer) -> OverlayLayer {
        guard l.type == .text, let t = l.data["text"], t.contains("{") else { return l }
        var c = l
        c.data["text"] = WidgetVariables.resolve(t, streamer.overlays.context)
        return c
    }

    private func natural(_ l: OverlayLayer) -> CGSize { store.naturalSize(l) ?? CGSize(width: 400, height: 200) }

    private func baseRect(_ l: OverlayLayer) -> CGRect {
        let e = effective(l)
        let n = natural(e)
        if let lay = l.layout { return widgetRect(lay, natural: n, canvas: canvas) }
        guard let f = fit() else { return .zero }
        return f.apply(overlayPlace(e, n.width, n.height))
    }

    /// Pinch multiplier actually applied (layout scale is clamped), and the layout scale it yields.
    private func multiplier(_ l: OverlayLayer) -> (m: CGFloat, scale: CGFloat) {
        guard let s = l.layout?.scale, s > 0 else {
            let m = min(max(pinch, 0.1), 8)
            return (m, m)
        }
        let n = min(max(s * pinch, 0.05), 4)
        return (n / s, n)
    }

    /// View-pt rect of layer `i` including the in-flight drag/pinch, snapped, plus the guide lines that snapped.
    private func live(_ i: Int, k: CGFloat) -> (rect: CGRect, gx: [CGFloat], gy: [CGFloat]) {
        let b = baseRect(layers[i])
        var r = CGRect(x: b.minX * k, y: b.minY * k, width: b.width * k, height: b.height * k)
        guard i == active else { return (r, [], []) }
        let m = multiplier(layers[i]).m
        r = CGRect(x: r.midX - r.width * m / 2, y: r.midY - r.height * m / 2, width: r.width * m, height: r.height * m)
            .offsetBy(dx: drag.width, dy: drag.height)
        return snap(r, k: k)
    }

    /// Edges and centre against canvas edges, the safe inset and the centre lines, nearest within snapDistance.
    private func snap(_ r: CGRect, k: CGFloat) -> (rect: CGRect, gx: [CGFloat], gy: [CGFloat]) {
        let w = canvas.width * k, h = canvas.height * k
        func axis(_ edges: [CGFloat], _ targets: [CGFloat]) -> (delta: CGFloat, guide: [CGFloat]) {
            var best: (d: CGFloat, t: CGFloat)?
            for e in edges { for t in targets where abs(t - e) <= snapDistance && abs(t - e) < abs(best?.d ?? .infinity) { best = (t - e, t) } }
            guard let b = best else { return (delta: 0, guide: []) }
            return (delta: b.d, guide: [b.t])
        }
        let sx = axis([r.minX, r.midX, r.maxX], [0, w * 0.025, w / 2, w * 0.975, w])
        let sy = axis([r.minY, r.midY, r.maxY], [0, h * 0.04, h / 2, h * 0.96, h])
        return (r.offsetBy(dx: sx.delta, dy: sy.delta), sx.guide, sy.guide)
    }

    // MARK: gestures

    private func gesture(k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).simultaneously(with: MagnifyGesture())
            .onChanged { v in
                if active == nil, let start = v.first?.startLocation {
                    let hit = hitTest(start, k: k)
                    selected = hit
                    active = hit
                }
                guard active != nil else { return }
                drag = v.first?.translation ?? .zero
                pinch = v.second?.magnification ?? 1
                if let a = active, layers.indices.contains(a) {
                    let key = live(a, k: k).gx.description + live(a, k: k).gy.description
                    if key != snapKey, key != "[][]" { hapticTap() }
                    snapKey = key
                }
            }
            .onEnded { _ in finish(k: k) }
    }

    /// Topmost visible layer under the point; the selected one wins ties so overlapping widgets stay grabbable.
    private func hitTest(_ p: CGPoint, k: CGFloat) -> Int? {
        func hit(_ i: Int) -> Bool {
            let b = baseRect(layers[i])
            return CGRect(x: b.minX * k, y: b.minY * k, width: b.width * k, height: b.height * k).insetBy(dx: -8, dy: -8).contains(p)
        }
        if let s = selected, layers.indices.contains(s), layers[s].visible, hit(s) { return s }
        return layers.indices.reversed().first { layers[$0].visible && hit($0) }
    }

    private func finish(k: CGFloat) {
        defer { active = nil; drag = .zero; pinch = 1; snapKey = "" }
        guard let i = active, layers.indices.contains(i), hypot(drag.width, drag.height) > 3 || abs(pinch - 1) > 0.01 else { return }
        let l = layers[i]
        let r = live(i, k: k).rect
        let out = CGRect(x: r.minX / k, y: r.minY / k, width: r.width / k, height: r.height / k)
        let (m, scale) = multiplier(l)
        var n = l
        if l.layout != nil {
            n.layout = widgetLayout(for: out, natural: natural(effective(l)), canvas: canvas, scale: scale)
        } else if let f = fit() {
            // ponytail: OBS layers move by the rect's centre and scale about their own anchor; exact for centred
            // anchors, a few px off for corner-anchored ones. Imports are a legacy path; widgets are exact.
            let b = baseRect(l)
            n.x += (out.midX - b.midX) / f.scale
            n.y += (out.midY - b.midY) / f.scale
            if l.boundsType != 0 { n.bw *= m; n.bh *= m } else { n.sx *= m; n.sy *= m }
        }
        commit(i, n)
    }
}
