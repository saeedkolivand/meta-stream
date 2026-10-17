// Builds the active OBS scene as HaishinKit screen objects on a mixer's Screen, and tears it down again.
// Only frames that go through the mixer's Screen (offscreen mode) show them: the phone camera and the H.264
// transcode path. Glasses HEVC passthrough never reaches the mixer, so it can't be drawn on.
import AVFoundation
import HaishinKit
import UIKit

/// What an in-app widget builder hands back: its screen object (already sized/placed) and the task keeping it fresh.
struct WidgetBuild { let object: ScreenObject; let task: Task<Void, Never>? }

@MainActor
final class OverlayCompositor {
    /// Live data for widgets (chat, emotes, streamer, platforms); filled by ContentView.
    let context = WidgetContext()

    private static let maxSlides = 30

    private var key = ""
    private var generation = 0       // bumped per apply(); a build that finds it changed abandons itself
    private var mixer: MediaMixer?   // the mixer `objects` are on, kept so teardown removes them from the right Screen
    private var objects: [ScreenObject] = []
    private var feeds: [BrowserFeed] = []
    private var tasks: [Task<Void, Never>] = []
    private var stills: [(object: ImageScreenObject, piece: OverlayPiece)] = []   // full-opacity bitmaps, for fades

    private var stinger: ScreenObject?   // the stinger (clip or drawn) on screen, kept above the scene
    private var stingerMixer: MediaMixer?
    private var stingerTask: Task<Void, Never>?   // redraws a built-in stinger's frames
    private var prepared: Built?   // the next scene, built off-screen while a stinger plays in (see prepare)

    /// A scene's screen objects and what keeps them alive, built but not necessarily on screen yet.
    @MainActor private struct Built {
        var key: String
        var objects: [ScreenObject] = []
        var feeds: [BrowserFeed] = []
        var tasks: [Task<Void, Never>] = []
        var stills: [(object: ImageScreenObject, piece: OverlayPiece)] = []
        var clips: [(object: AssetScreenObject, url: URL, loop: Bool)] = []   // audio starts when shown, not when built
        var summary = ""
        var failed = 0

        func discard() {
            tasks.forEach { $0.cancel() }
            feeds.forEach { $0.close() }
        }
    }

    private static let fadeSteps: [CGFloat] = [0.33, 0.66, 1]

    private func sceneKey(_ scene: OverlayScene?, _ canvas: CGSize, _ mixer: MediaMixer) -> String {
        scene.map { "\($0.name)|\(Int(canvas.width))x\(Int(canvas.height))|\(ObjectIdentifier(mixer).hashValue)|\(OverlayStore.shared.revision)" } ?? ""
    }

    /// Idempotent: does nothing while scene, canvas, mixer and the store's files are unchanged. A nil scene clears the screen.
    /// With `fade`, stills on screen step down to nothing before the new scene's stills step up; dynamic widgets just pop.
    /// A scene prepare()d for this exact key goes up in one swap instead of being built now.
    /// ponytail: a camera switch is a cut (mixer attach); only overlays fade, in 3 steps 60 ms apart.
    func apply(scene: OverlayScene?, pack: OverlayPack?, canvas: CGSize, mixer: MediaMixer, fade: Bool = false) async {
        let want = sceneKey(scene, canvas, mixer)
        guard want != key else { return }
        key = want
        generation += 1
        let gen = generation
        if let p = prepared, p.key == want, !fade {
            prepared = nil
            await swapIn(p, mixer: mixer)
            return
        }
        prepared?.discard()
        prepared = nil
        let doFade = fade && !stills.isEmpty
        if doFade {
            for a in [0.66, 0.33, 0] as [CGFloat] {
                for st in stills { await OverlayScreen.setImage(st.object, OverlayRaster.withAlpha(st.piece.bitmap, a)) }
                try? await Task.sleep(for: .milliseconds(60))
                if gen != generation { return }
            }
        }
        await teardown()
        guard let scene, let pack, canvas.width > 0, canvas.height > 0, gen == generation else { return }
        let b = await build(scene, pack, canvas: canvas, key: want, fadeIn: doFade)
        guard gen == generation else { b.discard(); return }   // superseded while building: drop it all
        self.mixer = mixer
        objects = b.objects
        feeds = b.feeds
        tasks = b.tasks
        stills = b.stills
        await OverlayScreen.add(b.objects, to: mixer)
        if let s = stinger { await OverlayScreen.raise(s, on: mixer) }
        startClips(b, rewind: false)
        if doFade {
            for a in Self.fadeSteps.dropFirst() {
                try? await Task.sleep(for: .milliseconds(60))
                if gen != generation { return }
                for st in b.stills { await OverlayScreen.setImage(st.object, OverlayRaster.withAlpha(st.piece.bitmap, a)) }
            }
        }
        built(b)
    }

    /// Builds `scene` off-screen (bitmaps, widgets, feeds) so the apply() that follows only swaps layers: the Screen
    /// re-lays out once, under the stinger, instead of while the scene is built piece by piece.
    func prepare(scene: OverlayScene?, pack: OverlayPack?, canvas: CGSize, mixer: MediaMixer) async {
        prepared?.discard()
        prepared = nil
        let want = sceneKey(scene, canvas, mixer)
        guard let scene, let pack, canvas.width > 0, canvas.height > 0, want != key else { return }
        let b = await build(scene, pack, canvas: canvas, key: want, fadeIn: false)
        guard b.key != key, prepared == nil else { b.discard(); return }   // applied (or prepared again) meanwhile
        prepared = b
    }

    /// Old scene off, prepared scene on, in one Screen step.
    private func swapIn(_ b: Built, mixer: MediaMixer) async {
        SoundMix.shared.stopClips()
        tasks.forEach { $0.cancel() }
        feeds.forEach { $0.close() }
        let old = objects, oldMixer = self.mixer
        self.mixer = mixer
        objects = b.objects
        feeds = b.feeds
        tasks = b.tasks
        stills = b.stills
        await OverlayScreen.swap(remove: old, from: oldMixer, add: b.objects, to: mixer, top: stinger)
        startClips(b, rewind: true)
        built(b, note: " (prebuilt)")
    }

    /// Video layers' audio into the mix; a prebuilt clip also restarts its picture, which began reading when built.
    private func startClips(_ b: Built, rewind: Bool) {
        for c in b.clips {
            if rewind {
                let (o, url) = (c.object, c.url)
                Task { await OverlayScreen.rewind(o, url) }
            }
            SoundMix.shared.playClip(c.url, loop: c.loop)
        }
    }

    private func built(_ b: Built, note: String = "") {
        // No key window yet (app still launching) means browser layers couldn't attach: build again on the next sync.
        if b.failed > 0, !BrowserFeed.hostAvailable { key = "" }
        applog("overlay", "scene built: \(b.summary) failed=\(b.failed)\(note)")
    }

    private func build(_ scene: OverlayScene, _ pack: OverlayPack, canvas: CGSize, key: String, fadeIn: Bool) async -> Built {
        let fit = overlayFit(canvasW: pack.canvasW, canvasH: pack.canvasH, outW: canvas.width, outH: canvas.height)
        var b = Built(key: key)
        var counts: [String: Int] = [:]   // layer type -> built, for the log
        for l in scene.layers where l.visible {
            switch l.type {
            case .image, .text, .color:
                if let w = await dynamicBuild(l, fit, canvas) {
                    b.objects.append(w.object)
                    if let t = w.task { b.tasks.append(t) }
                } else {
                    guard let p = still(l, fit, canvas) else { b.failed += 1; continue }
                    let o = await OverlayScreen.makeImage(p.rect, fadeIn ? OverlayRaster.withAlpha(p.bitmap, Self.fadeSteps[0]) : p.bitmap)
                    b.objects.append(o)
                    b.stills.append((o, p))
                }
            case .chat, .alerts, .events, .qr:
                guard let w = await widget(l, canvas) else { b.failed += 1; continue }
                b.objects.append(w.object)
                if let t = w.task { b.tasks.append(t) }
            case .slideshow:
                guard let (o, task) = await slideshow(l, fit, canvas) else { b.failed += 1; continue }
                b.objects.append(o)
                b.tasks.append(task)
            case .media:
                guard let url = OverlayStore.shared.local(l.data["file"] ?? ""),
                      let (o, task) = await media(l, fit, canvas) else { b.failed += 1; continue }
                b.objects.append(o)
                if let task { b.tasks.append(task) }
                b.clips.append((o, url, l.data["loop"] == "true"))
            case .browser:
                guard let (o, feed) = await browser(l, fit, canvas) else { b.failed += 1; continue }
                b.objects.append(o)
                b.feeds.append(feed)
            }
            counts[l.type.rawValue, default: 0] += 1
        }
        if !b.feeds.isEmpty { b.tasks.append(snapshotLoop(b.feeds)) }
        b.summary = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return b
    }

    /// Plays the stinger clip once over the whole canvas, above every layer (apply() keeps it on top while a scene is
    /// rebuilt underneath). Its audio is the caller's job. ponytail: a stinger with alpha (HEVC with alpha) only
    /// composites if AssetScreenObject already handles it; nothing here special-cases it.
    func playStinger(_ url: URL, canvas: CGSize, mixer: MediaMixer) async {
        await removeStinger()
        let o = await OverlayScreen.makeMedia(CGRect(origin: .zero, size: canvas), url)
        stinger = o
        stingerMixer = mixer
        await OverlayScreen.add([o], to: mixer)
    }

    /// Puts a built-in stinger over the whole canvas. It draws itself per video frame; layout only re-runs when
    /// invalidated, so this pokes it at 60 Hz (cheap: no drawing here) until removeStinger().
    func playStinger(_ kind: StingerKind, style: StingerStyle, canvas: CGSize, mixer: MediaMixer) async {
        await removeStinger()
        let o = await OverlayScreen.makeStinger(CGRect(origin: .zero, size: canvas), kind, style)
        stinger = o
        stingerMixer = mixer
        await OverlayScreen.add([o], to: mixer)
        stingerTask = Task { @ScreenActor in
            while !Task.isCancelled {
                o.invalidateLayout()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func removeStinger() async {
        stingerTask?.cancel()
        stingerTask = nil
        guard let o = stinger, let m = stingerMixer else { return }
        stinger = nil
        stingerMixer = nil
        await OverlayScreen.remove([o], from: m)
    }

    private func teardown() async {
        SoundMix.shared.stopClips()
        tasks.forEach { $0.cancel() }
        tasks = []
        feeds.forEach { $0.close() }
        feeds = []
        let old = objects
        objects = []
        stills = []
        if let mixer, !old.isEmpty { await OverlayScreen.remove(old, from: mixer) }
    }

    // MARK: layer builders

    /// Output rect: in-app widgets place relative to the frame (`widgetRect`), OBS layers through the OBS transform + letterbox fit.
    private func box(_ l: OverlayLayer, _ natural: CGSize, _ fit: Fit, _ canvas: CGSize) -> CGRect {
        guard let layout = l.layout else { return fit.apply(overlayPlace(l, natural.width, natural.height)) }
        return widgetRect(layout, natural: natural, canvas: canvas)
    }

    /// Chat / alerts / event list / QR: always frame-relative; a layer without a layout gets the default one.
    private func widget(_ l: OverlayLayer, _ canvas: CGSize) async -> WidgetBuild? {
        let natural = OverlayStore.shared.naturalSize(l) ?? CGSize(width: 400, height: 200)
        let rect = widgetRect(l.layout ?? WidgetLayout(), natural: natural, canvas: canvas)
        switch l.type {
        case .chat: return await chatWidget(l, box: rect, canvas: canvas)
        case .alerts: return await alertWidget(l, box: rect, canvas: canvas)
        case .events: return await eventListWidget(l, box: rect, canvas: canvas)
        case .qr: return await qrWidget(l, box: rect, canvas: canvas)
        default: return nil
        }
    }

    /// Text with {tokens} and animated GIFs are redrawn over time instead of being a one-off still; nil falls back to the still.
    private func dynamicBuild(_ l: OverlayLayer, _ fit: Fit, _ canvas: CGSize) async -> WidgetBuild? {
        switch l.type {
        case .text:
            guard (l.data["text"] ?? "").contains("{") else { return nil }
            return await liveTextWidget(l, canvas: canvas)
        case .image:
            guard let natural = OverlayStore.shared.naturalSize(l) else { return nil }
            return await gifWidget(l, box: box(l, natural, fit, canvas), canvas: canvas)
        default:
            return nil
        }
    }

    /// Image, text or color layer as a ready bitmap at its output rect.
    private func still(_ l: OverlayLayer, _ fit: Fit, _ canvas: CGSize) -> OverlayPiece? {
        switch l.type {
        case .image:
            guard let url = OverlayStore.shared.local(l.data["file"] ?? ""), let img = OverlayRaster.load(url) else { return nil }
            let rect = box(l, OverlayRaster.croppedSize(img, l.crop), fit, canvas)
            return OverlayRaster.render(rect, canvas: canvas) { OverlayRaster.drawImage(img, crop: l.crop, in: $0) }
        case .text:
            if l.layout != nil {   // in-app text: sized for a 1080 short side, with its own shadow/backdrop
                let t = TextWidgetStyle(l.data)
                guard !t.text.allSatisfy(\.isWhitespace), let natural = OverlayStore.shared.naturalSize(l) else { return nil }
                return OverlayRaster.render(box(l, natural, fit, canvas), canvas: canvas) { OverlayRaster.drawWidgetText(t, natural: natural, in: $0) }
            }
            let text = l.data["text"] ?? ""
            guard !text.allSatisfy(\.isWhitespace) else { return nil }
            let px = CGFloat(Double(l.data["size"] ?? "") ?? 36) * fit.scale
            let attrs = OverlayRaster.textAttributes(face: l.data["face"] ?? "", bold: l.data["bold"] == "true", px: px,
                                                     argb: UInt32(l.data["color"] ?? "") ?? 0xFFFF_FFFF)
            let natural = OverlayRaster.textSize(text, attrs)
            // The text is measured at output scale, so its canvas size is pixels / scale.
            let rect = fit.apply(overlayPlace(l, natural.width / fit.scale, natural.height / fit.scale))
            return OverlayRaster.render(rect, canvas: canvas) { OverlayRaster.drawText(text, attrs, natural: natural, in: $0) }
        default:
            let w = CGFloat(Double(l.data["width"] ?? "") ?? 1920)
            let h = CGFloat(Double(l.data["height"] ?? "") ?? 1080)
            let argb = UInt32(l.data["color"] ?? "") ?? 0xFFFF_FFFF
            return OverlayRaster.render(box(l, CGSize(width: w, height: h), fit, canvas), canvas: canvas) { OverlayRaster.fill(argb: argb, in: $0) }
        }
    }

    // ponytail: slides are re-decoded on each change (every >= 1 s) instead of kept as 30 canvas-size bitmaps.
    private func slideshow(_ l: OverlayLayer, _ fit: Fit, _ canvas: CGSize) async -> (ScreenObject, Task<Void, Never>)? {
        let urls = l.files.prefix(Self.maxSlides).compactMap { OverlayStore.shared.local($0) }
        guard let first = urls.first.flatMap(OverlayRaster.load) else { return nil }
        let rect = box(l, first.size, fit, canvas)
        let zero = [0, 0, 0, 0]
        guard let p = OverlayRaster.render(rect, canvas: canvas, draw: { OverlayRaster.drawImage(first, crop: zero, in: $0) }) else { return nil }
        let o = await OverlayScreen.makeImage(p.rect, p.bitmap)
        let delay = max(1000, Int(l.data["time"] ?? "") ?? 8000)
        let task = Task { [urls] in
            guard urls.count > 1 else { return }
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(delay))
                i = (i + 1) % urls.count
                guard !Task.isCancelled, let img = OverlayRaster.load(urls[i]),
                      let next = OverlayRaster.render(rect, canvas: canvas, draw: { OverlayRaster.drawImage(img, crop: zero, in: $0) }) else { continue }
                await OverlayScreen.setImage(o, next.bitmap)
            }
        }
        let object: ScreenObject = o
        return (object, task)
    }

    /// Muted clip; the task re-starts it when it ends if the OBS source loops.
    private func media(_ l: OverlayLayer, _ fit: Fit, _ canvas: CGSize) async -> (AssetScreenObject, Task<Void, Never>?)? {
        guard let url = OverlayStore.shared.local(l.data["file"] ?? ""), let size = await OverlayRaster.mediaSize(url),
              let rect = OverlayRaster.visible(box(l, size, fit, canvas), in: canvas) else { return nil }
        let clip = await OverlayScreen.makeMedia(rect, url)   // video only: its audio starts when the scene goes up
        guard l.data["loop"] == "true" else { return (clip, nil) }
        let loop: Task<Void, Never> = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await OverlayScreen.restart(clip, url)
            }
        }
        return (clip, loop)
    }

    private func browser(_ l: OverlayLayer, _ fit: Fit, _ canvas: CGSize) async -> (ScreenObject, BrowserFeed)? {
        let w = CGFloat(Double(l.data["width"] ?? "") ?? 800)
        let h = CGFloat(Double(l.data["height"] ?? "") ?? 600)
        let frame = box(l, CGSize(width: w, height: h), fit, canvas)
        guard let rect = OverlayRaster.visible(frame, in: canvas) else { return nil }
        let o = await OverlayScreen.makeImage(rect, nil)   // empty until the first snapshot lands
        guard let feed = BrowserFeed(layer: l, box: frame, canvas: canvas, target: o) else { return nil }
        let object: ScreenObject = o
        return (object, feed)
    }

    // ponytail: one serial snapshot loop for every browser source in the scene, ~10 fps at best (100 ms pause between
    // rounds, so slower with several sources). Each frame is a WebKit snapshot (GPU readback) + a redraw + HaishinKit's
    // CPU vImage blit, and that is the heat/CPU ceiling; it backs off to 4 fps from thermal .serious. Upgrade path: skip
    // frames whose snapshot hasn't changed, or let pages that only animate occasionally run at 2 fps.
    private func snapshotLoop(_ feeds: [BrowserFeed]) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                for f in feeds { await f.pump() }
                let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
                try? await Task.sleep(for: .milliseconds(hot ? 250 : 100))
            }
        }
    }
}
