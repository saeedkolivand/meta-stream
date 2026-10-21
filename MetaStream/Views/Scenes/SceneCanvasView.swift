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
    /// Zoom and pan of the whole canvas (empty-canvas pinch / drag); `base` is its value when the current gesture began.
    @State private var zoom = CanvasZoom()
    @State private var base = CanvasZoom()
    @State private var began = false

    private let snapDistance: CGFloat = 12
    /// Floating toolbar over the selected widget (set with `selectionBar`); its size is fixed so it can be placed.
    private var bar: (() -> AnyView)?
    static let barSize = CGSize(width: 236, height: 48)

    /// Adds a toolbar that floats above the selected widget (below it when there is no room above).
    func selectionBar<Bar: View>(@ViewBuilder _ make: @escaping () -> Bar) -> SceneCanvasView {
        var copy = self
        copy.bar = { AnyView(make()) }
        return copy
    }

    private func barOffset(_ rect: CGRect, in size: CGSize) -> CGSize {
        let width = Self.barSize.width, height = Self.barSize.height
        let above = rect.minY - height - 6
        let top = above >= 0 ? above : min(rect.maxY + 6, size.height - height)
        return CGSize(width: min(max(rect.midX - width / 2, 0), max(size.width - width, 0)), height: max(top, 0))
    }

    init(layers: [OverlayLayer], canvas: CGSize, selected: Binding<Int?>, emotes: Emotes, commit: @escaping (Int, OverlayLayer) -> Void) {
        self.layers = layers
        self.canvas = canvas
        self._selected = selected
        self.emotes = emotes
        self.commit = commit
    }

    var body: some View {
        GeometryReader { geo in
            let ratio = geo.size.width / max(canvas.width, 1)
            ZStack(alignment: .topLeading) {
                content(geo.size, ratio: ratio)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .scaleEffect(zoom.scale, anchor: .topLeading)
                    .offset(zoom.pan)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .gesture(gesture(ratio: ratio, size: geo.size))
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                        if hitTest(zoom.toView(tap.location), ratio: ratio) == nil { resetZoom() }
                    })
                // Outside the gesture's view, so its buttons get taps instead of starting a drag.
                if active == nil, let sel = selected, layers.indices.contains(sel), layers[sel].visible {
                    floatingBar(zoom.toScreen(live(sel, ratio: ratio).rect), in: geo.size)
                }
                zoomBadge
            }
            .onChange(of: geo.size) { zoom = CanvasZoom() }
        }
        .aspectRatio(canvas.width / max(canvas.height, 1), contentMode: .fit)
        .accessibilityLabel("Scene canvas")
    }

    /// The canvas at 1x, in view points; the zoom is applied on top of this.
    private func content(_ size: CGSize, ratio: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            background(size)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ZStack(alignment: .topLeading) {
                    ForEach(layers.indices, id: \.self) { idx in
                        if layers[idx].visible { layerView(idx, ratio: ratio) }
                    }
                }
            }
            if let sel = selected, layers.indices.contains(sel), layers[sel].visible { outline(live(sel, ratio: ratio).rect) }
            if let act = active, layers.indices.contains(act) { guides(live(act, ratio: ratio), size: size) }
        }
    }

    private func resetZoom() { withAnimation(.snappy) { zoom = CanvasZoom() } }

    @ViewBuilder private var zoomBadge: some View {
        if zoom.isZoomed {
            Button(action: resetZoom) {
                Text(String(format: "%.1f×", zoom.scale)).font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Zoom \(String(format: "%.1f", zoom.scale)) times, reset to fit")
        }
    }

    @ViewBuilder private func floatingBar(_ rect: CGRect, in size: CGSize) -> some View {
        if let bar {
            bar().frame(width: Self.barSize.width, height: Self.barSize.height).offset(barOffset(rect, in: size))
        }
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

    @ViewBuilder private func layerView(_ idx: Int, ratio: CGFloat) -> some View {
        let rect = live(idx, ratio: ratio).rect
        let shown = effective(layers[idx])
        LayerPreview(layer: shown, natural: natural(shown), size: rect.size, emotes: emotes, chat: chat.recent)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// Strokes and handles keep their screen size at any zoom.
    private func outline(_ r: CGRect) -> some View {
        let inv = 1 / zoom.scale
        return ZStack(alignment: .topLeading) {
            Rectangle().stroke(Color.accentColor, lineWidth: 1.5 * inv)
            ForEach(0..<4, id: \.self) { c in
                Circle().fill(Color.accentColor).frame(width: 8 * inv, height: 8 * inv)
                    .offset(x: (c % 2 == 0 ? 0 : r.width) - 4 * inv, y: (c < 2 ? 0 : r.height) - 4 * inv)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .offset(x: r.minX, y: r.minY)
        .allowsHitTesting(false)
    }

    private func guides(_ l: (rect: CGRect, gx: [CGFloat], gy: [CGFloat]), size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(l.gx, id: \.self) { x in Rectangle().fill(.yellow).frame(width: 1 / zoom.scale, height: size.height).offset(x: x) }
            ForEach(l.gy, id: \.self) { y in Rectangle().fill(.yellow).frame(width: size.width, height: 1 / zoom.scale).offset(y: y) }
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
    private func live(_ idx: Int, ratio: CGFloat) -> (rect: CGRect, gx: [CGFloat], gy: [CGFloat]) {
        let box = baseRect(layers[idx])
        var rect = CGRect(x: box.minX * ratio, y: box.minY * ratio, width: box.width * ratio, height: box.height * ratio)
        guard idx == active else { return (rect, [], []) }
        let mul = multiplier(layers[idx]).m
        let size = CGSize(width: rect.width * mul, height: rect.height * mul)
        rect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            .offsetBy(dx: drag.width / zoom.scale, dy: drag.height / zoom.scale)   // finger points -> view points
        return snap(rect, ratio: ratio)
    }

    /// Edges and centre against canvas edges, the safe inset and the centre lines, nearest within snapDistance.
    private func snap(_ rect: CGRect, ratio: CGFloat) -> (rect: CGRect, gx: [CGFloat], gy: [CGFloat]) {
        let wide = canvas.width * ratio, high = canvas.height * ratio
        let reach = snapDistance / zoom.scale   // a constant pull in screen points
        func axis(_ edges: [CGFloat], _ targets: [CGFloat]) -> (delta: CGFloat, guide: [CGFloat]) {
            var best: (d: CGFloat, t: CGFloat)?
            for edge in edges {
                for target in targets where abs(target - edge) <= reach && abs(target - edge) < abs(best?.d ?? .infinity) {
                    best = (target - edge, target)
                }
            }
            guard let box = best else { return (delta: 0, guide: []) }
            return (delta: box.d, guide: [box.t])
        }
        let sx = axis([rect.minX, rect.midX, rect.maxX], [0, wide * 0.025, wide / 2, wide * 0.975, wide])
        let sy = axis([rect.minY, rect.midY, rect.maxY], [0, high * 0.04, high / 2, high * 0.96, high])
        return (rect.offsetBy(dx: sx.delta, dy: sy.delta), sx.guide, sy.guide)
    }

    // MARK: gestures

    /// A touch that starts on a widget moves / resizes it; one that starts on empty canvas zooms and pans the view.
    /// Locations are in the untransformed container, so `zoom.toView` maps them into canvas space.
    private func gesture(ratio: CGFloat, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0).simultaneously(with: MagnifyGesture())
            .onChanged { v in
                if !began, let start = v.first?.startLocation {
                    began = true
                    base = zoom
                    active = hitTest(zoom.toView(start), ratio: ratio)
                    if active != nil { selected = active }
                }
                guard began else { return }
                drag = v.first?.translation ?? .zero
                pinch = v.second?.magnification ?? 1
                guard let hit = active, layers.indices.contains(hit) else {
                    zoom = base.applying(magnification: pinch, translation: drag, origin: v.first?.startLocation ?? .zero, in: size)
                    return
                }
                let key = live(hit, ratio: ratio).gx.description + live(hit, ratio: ratio).gy.description
                if key != snapKey, key != "[][]" { hapticTap() }
                snapKey = key
            }
            .onEnded { _ in finish(ratio: ratio) }
    }

    /// Topmost visible layer under the point; the selected one wins ties so overlapping widgets stay grabbable.
    private func hitTest(_ point: CGPoint, ratio: CGFloat) -> Int? {
        func hit(_ idx: Int) -> Bool {
            let box = baseRect(layers[idx])
            let rect = CGRect(x: box.minX * ratio, y: box.minY * ratio, width: box.width * ratio, height: box.height * ratio)
            return rect.insetBy(dx: -8 / zoom.scale, dy: -8 / zoom.scale).contains(point)
        }
        if let sel = selected, layers.indices.contains(sel), layers[sel].visible, hit(sel) { return sel }
        return layers.indices.reversed().first { layers[$0].visible && hit($0) }
    }

    private func finish(ratio: CGFloat) {
        let moved = hypot(drag.width, drag.height) > 3 || abs(pinch - 1) > 0.01
        defer { active = nil; began = false; drag = .zero; pinch = 1; snapKey = "" }
        // A tap on empty canvas deselects; a pan or zoom keeps the selection.
        if active == nil, began, !moved { selected = nil }
        guard let idx = active, layers.indices.contains(idx), moved else { return }
        let lay = layers[idx]
        let rect = live(idx, ratio: ratio).rect
        let out = CGRect(x: rect.minX / ratio, y: rect.minY / ratio, width: rect.width / ratio, height: rect.height / ratio)
        let (mul, scale) = multiplier(lay)
        var result = lay
        if lay.layout != nil {
            result.layout = widgetLayout(for: out, natural: natural(effective(lay)), canvas: canvas, scale: scale)
        } else if let fitted = fit() {
            // ponytail: OBS layers move by the rect's centre and scale about their own anchor; exact for centred
            // anchors, a few px off for corner-anchored ones. Imports are a legacy path; widgets are exact.
            let box = baseRect(lay)
            result.x += (out.midX - box.midX) / fitted.scale
            result.y += (out.midY - box.midY) / fitted.scale
            if lay.boundsType != 0 { result.bw *= mul; result.bh *= mul } else { result.sx *= mul; result.sy *= mul }
        }
        commit(idx, result)
    }
}
