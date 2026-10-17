// Scene overlays on the stream: when they can be drawn, and keeping the mixer's Screen in line with the chosen scene.
import AVFoundation
import Foundation

extension Streamer {

    /// Overlays are drawn by the mixer's Screen, which only sees the phone camera, camera-off black frames and the
    /// H.264 transcode of the glasses. Glasses HEVC passthrough never reaches the mixer, so it can't be drawn on
    /// (the HUD pill says so).
    var overlaysUsable: Bool { source == "phone" || cameraOff || hot.transcoder != nil }

    /// A scene is picked and the current source can show it: this keeps the mixer in offscreen mode (see syncBlurEffect).
    var overlaysWanted: Bool { overlaysUsable && OverlayStore.shared.activeScene != nil }

    /// Builds, swaps or clears the scene on the mixer's Screen. Idempotent (the compositor compares scene, canvas,
    /// mixer and imported files), so the 1 s tick can call it freely. Call it with the render loop off or the canvas
    /// size unchanged: syncBlurEffect runs it before turning offscreen mode on.
    func syncOverlays() async {
        let store = OverlayStore.shared
        let fade = pendingSceneFade
        pendingSceneFade = false
        await overlays.apply(scene: overlaysUsable ? store.activeScene : nil, pack: store.pack, canvas: blurCanvasSize, mixer: mixer, fade: fade)
    }

    /// The one way to change scene (HUD, settings, rotation, editor): selects it, switches the camera if the scene names
    /// one that is available, and fades overlays when the store's transition is "fade". "" (or an unknown name) clears.
    /// A manual pick of a scene outside the rotation list stops auto-rotate. A manual pick also ends any scene role
    /// (Starting / BRB / Ending) with no return to the old scene: the streamer's choice always wins.
    func selectScene(_ name: String) {
        let store = OverlayStore.shared
        applyScene(name)
        clearRole()
        if store.rotateOn, !store.rotateScenes.contains(name) {
            store.rotateOn = false
            updateSceneRotation()
        }
    }

    /// Scene change with the store's transition: a stinger covers it when overlays are usable, otherwise it is a cut.
    func applyScene(_ name: String) {
        let store = OverlayStore.shared
        if stingerTarget != nil { stingerTarget = name; return }   // a stinger is mid-flight: it cuts to the latest pick
        guard store.transition == "stinger", overlaysWanted, name != store.scene else {
            switchScene(name)
            return
        }
        if let kind = StingerKind(rawValue: store.stingerKind) {   // built-in: drawn live, cut where it fully covers
            stingerTarget = name
            let style = StingerStyle.load()
            Task {
                let began = Date()
                await overlays.playStinger(kind, style: style, canvas: blurCanvasSize, mixer: mixer)
                await prepareScene(name)   // built while the stinger plays in; the cut then only swaps layers
                try? await Task.sleep(for: .seconds(max(0, kind.cutSeconds(style) - Date().timeIntervalSince(began))))
                switchScene(stingerTarget ?? name)
                stingerTarget = nil
                try? await Task.sleep(for: .seconds(kind.seconds(style) - kind.cutSeconds(style) + 0.15))   // a beat past the end, so it logs and clears itself
                await overlays.removeStinger()
            }
            return
        }
        guard let url = store.stingerURL else {
            switchScene(name)
            return
        }
        stingerTarget = name
        Task {
            let secs = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard secs > 0, secs.isFinite else {
                switchScene(stingerTarget ?? name)
                stingerTarget = nil
                return
            }
            let began = Date()
            await overlays.playStinger(url, canvas: blurCanvasSize, mixer: mixer)
            SoundMix.shared.playStinger(url)
            await prepareScene(name)
            try? await Task.sleep(for: .seconds(max(0, secs * store.stingerCut - Date().timeIntervalSince(began))))
            switchScene(stingerTarget ?? name)
            stingerTarget = nil
            try? await Task.sleep(for: .seconds(secs * (1 - store.stingerCut)))
            await overlays.removeStinger()
        }
    }

    /// Builds the scene a stinger is heading to, so the cut is one swap. Nothing to build when overlays are off.
    private func prepareScene(_ name: String) async {
        let store = OverlayStore.shared
        guard overlaysUsable, let target = store.scenes.first(where: { $0.name == name }) else { return }
        await overlays.prepare(scene: target, pack: store.pack, canvas: blurCanvasSize, mixer: mixer)
    }

    private func switchScene(_ name: String) {
        let store = OverlayStore.shared
        let target = store.scenes.first { $0.name == name }
        if (target?.name ?? "") != store.scene {
            pendingSceneFade = store.transition == "fade"
            store.select(target?.name ?? "")
        }
        // "external" only with a camera plugged in, "glasses" only in a build that can talk to them; anything else is
        // left alone rather than switching to a dead feed.
        guard let cam = target?.camera, cam != manualSource else { return }
        switch cam {
        case "external": guard externalCameraName != nil else { return }
        case "glasses": guard Streamer.glassesEnabled else { return }
        case "back", "front", "auto": break
        default: return
        }
        setSource(cam)
    }

    /// Starts/stops the rotation loop to match the store's rotateOn / rotateScenes / rotateSeconds. Call after changing them.
    func updateSceneRotation() {
        sceneRotationTask?.cancel()
        sceneRotationTask = nil
        guard roleActive == nil, OverlayStore.shared.rotateOn, rotationScenes().count >= 2 else { return }
        sceneRotationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(5, OverlayStore.shared.rotateSeconds)))
                guard !Task.isCancelled, let self else { return }
                guard OverlayStore.shared.rotateOn, self.rotateToNextScene() else {
                    self.sceneRotationTask = nil
                    return
                }
            }
        }
    }

    /// Rotation names that still exist, in the user's order.
    private func rotationScenes() -> [String] {
        let have = Set(OverlayStore.shared.scenes.map(\.name))
        return OverlayStore.shared.rotateScenes.filter { have.contains($0) }
    }

    /// False when fewer than two valid scenes remain (the loop ends).
    private func rotateToNextScene() -> Bool {
        let names = rotationScenes()
        guard names.count >= 2 else { return false }
        let i = names.firstIndex(of: OverlayStore.shared.scene).map { ($0 + 1) % names.count } ?? 0
        applyScene(names[i])
        return true
    }
}
