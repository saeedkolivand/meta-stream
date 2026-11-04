// Scene direction (Android: overlay SceneRoles + Overlays as SceneCompositor): which scene is on the stream, how it
// changes (cut, fade or stinger), auto-rotate, and the roles: scenes the app switches to on its own. Starting
// (countdown after going live), BRB (while the link is too weak) and Ending (held briefly after Stop). Role switches go
// through applyScene, not selectScene, so they don't cancel themselves; any manual selectScene ends the role (see
// clearRole). The engine only sees the SceneCompositor protocol; App.swift wires streamer.compositor to this.
import AVFoundation
import CoreLogging
import Engine
import Foundation

@MainActor
public final class SceneDirector: SceneCompositor {
    public static let shared = SceneDirector()

    public weak var streamer: Streamer?
    /// Role changes, for the app bot's chat notice (App.swift; Android: SceneRoles.onRole).
    public var onRole: (_ role: String, _ on: Bool) -> Void = { _, _ in }

    public let overlays = OverlayCompositor()           // scene layers on the mixer's Screen
    private var sceneRotationTask: Task<Void, Never>?    // auto-rotate loop, see updateSceneRotation()
    private var pendingSceneFade = false                 // set by a scene change, consumed by the next sync
    public private(set) var roleActive: String?                 // the role whose scene is up, nil = none
    private var roleBack: String?                        // scene to return to when the role ends
    private var roleTask: Task<Void, Never>?             // Starting countdown / Ending hold
    public private(set) var countdownEnd: Date?                 // Starting countdown, for {countdown}
    private var weakTicks = 0, goodTicks = 0             // consecutive seconds of weak / healthy throughput
    private var weakNoticed = false                      // weak link announced in chat without a BRB scene
    private var stingerTarget: String?                   // scene the running stinger will cut to

    private var startCountdownSeconds: Int { UserDefaults.standard.object(forKey: "startCountdown") as? Int ?? 60 }
    private var endingHoldSeconds: Int { UserDefaults.standard.object(forKey: "endingHold") as? Int ?? 10 }

    private init() {}

    // MARK: SceneCompositor

    public var wanted: Bool { (streamer?.overlaysUsable ?? false) && hasScene }

    public var hasScene: Bool { OverlayStore.shared.activeScene != nil }

    /// Builds, swaps or clears the scene on the mixer's Screen. Idempotent (the compositor compares scene, canvas,
    /// mixer and imported files). Call it with the render loop off or the canvas size unchanged: syncBlurEffect runs it
    /// before turning offscreen mode on.
    public func sync() async {
        guard let s = streamer else { return }
        let store = OverlayStore.shared
        let fade = pendingSceneFade
        pendingSceneFade = false
        await overlays.apply(scene: s.overlaysUsable ? store.activeScene : nil, pack: store.pack, canvas: s.blurCanvasSize, mixer: s.mixer, fade: fade)
    }

    public func sessionStarted() { startRole() }

    public func sessionEnded() { roleEnd() }

    // MARK: Scenes

    /// The one way to change scene (HUD, settings, rotation, editor): selects it, switches the camera if the scene names
    /// one that is available, and fades overlays when the store's transition is "fade". "" (or an unknown name) clears.
    /// A manual pick of a scene outside the rotation list stops auto-rotate. A manual pick also ends any scene role
    /// (Starting / BRB / Ending) with no return to the old scene: the streamer's choice always wins.
    public func selectScene(_ name: String) {
        let store = OverlayStore.shared
        applyScene(name)
        clearRole()
        if store.rotateOn, !store.rotateScenes.contains(name) {
            store.rotateOn = false
            updateSceneRotation()
        }
    }

    /// Scene change with the store's transition: a stinger covers it when overlays are usable, otherwise it is a cut.
    public func applyScene(_ name: String) {
        guard let s = streamer else { return }
        let store = OverlayStore.shared
        if stingerTarget != nil { stingerTarget = name; return }   // a stinger is mid-flight: it cuts to the latest pick
        guard store.transition == "stinger", wanted, name != store.scene else {
            switchScene(name)
            return
        }
        if let kind = StingerKind(rawValue: store.stingerKind) {   // built-in: drawn live, cut where it fully covers
            stingerTarget = name
            let style = StingerStyle.load()
            Task {
                let began = Date()
                await overlays.playStinger(kind, style: style, canvas: s.blurCanvasSize, mixer: s.mixer)
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
            await overlays.playStinger(url, canvas: s.blurCanvasSize, mixer: s.mixer)
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
        guard let s = streamer, s.overlaysUsable, let target = store.scenes.first(where: { $0.name == name }) else { return }
        await overlays.prepare(scene: target, pack: store.pack, canvas: s.blurCanvasSize, mixer: s.mixer)
    }

    private func switchScene(_ name: String) {
        guard let s = streamer else { return }
        let store = OverlayStore.shared
        let target = store.scenes.first { $0.name == name }
        if (target?.name ?? "") != store.scene {
            pendingSceneFade = store.transition == "fade"
            store.select(target?.name ?? "")
            // Now, not on the next 1 s tick: under a stinger the swap has to land while the frame is covered.
            Task { await s.syncBlurEffect() }
        }
        // "external" only with a camera plugged in, "glasses" only in a build that can talk to them; anything else is
        // left alone rather than switching to a dead feed.
        guard let cam = target?.camera, cam != s.manualSource else { return }
        switch cam {
        case "external": guard s.externalCameraName != nil else { return }
        case "glasses": guard Streamer.glassesEnabled else { return }
        case "back", "front", "auto": break
        default: return
        }
        s.setSource(cam)
    }

    /// Starts/stops the rotation loop to match the store's rotateOn / rotateScenes / rotateSeconds. Call after changing them.
    public func updateSceneRotation() {
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

    // MARK: Roles

    /// Logs the role change and tells the app bot (its chat notice).
    private func sceneRole(_ role: String, on: Bool) {
        applog("overlay", "role \(role) \(on ? "on" : "off") -> \(OverlayStore.shared.scene)")
        onRole(role, on)
    }

    /// {countdown}: remaining Starting time as m:ss, empty when no countdown runs.
    public var countdownText: String {
        guard let end = countdownEnd else { return "" }
        return Streamer.fmtClock(max(0, end.timeIntervalSinceNow.rounded(.up)))
    }

    /// Selects the role's scene (remembering where to come back to). False when no scene has that role.
    @discardableResult private func roleSelect(_ role: String) -> Bool {
        let store = OverlayStore.shared
        guard let scene = store.scenes.first(where: { $0.role == role }) else { return false }
        if let old = roleActive, old != role { sceneRole(old, on: false) }
        if roleActive == nil {
            roleBack = store.scene
            sceneRotationTask?.cancel()   // paused for the duration; roleEnd / clearRole resume it
            sceneRotationTask = nil
        }
        roleActive = role
        countdownEnd = nil
        applyScene(scene.name)
        sceneRole(role, on: true)
        return true
    }

    /// Role over: back to the scene from before it, rotation resumes.
    public func roleEnd() {
        guard let role = roleActive else { return }
        let back = roleBack ?? ""
        clearRole(log: false)
        applyScene(back)
        sceneRole(role, on: false)
    }

    /// Role over without a return (manual pick, or a cancelled Ending hold). No-op when no role is up.
    public func clearRole(log: Bool = true) {
        guard let role = roleActive else { return }
        roleActive = nil; roleBack = nil; countdownEnd = nil; streamer?.endingIn = nil
        roleTask?.cancel(); roleTask = nil
        weakTicks = 0; goodTicks = 0
        updateSceneRotation()
        if log { sceneRole(role, on: false) }
    }

    /// First connect of a session: show the Starting scene for the countdown, then go back.
    private func startRole() {
        let secs = startCountdownSeconds
        guard secs > 0, roleSelect("starting") else { return }
        countdownEnd = Date().addingTimeInterval(TimeInterval(secs))
        roleTask = Task {
            try? await Task.sleep(for: .seconds(secs))
            if !Task.isCancelled { roleEnd() }
        }
    }

    /// Called from the 1 s tick. A dropped link or over 2 s of video stuck in the uplink queue for 5 s puts the BRB
    /// scene up; connected with under 0.5 s queued for 10 s takes it down. With no BRB scene the stream stays as it is
    /// and only the app bot's chat notice goes out (weakNoticed pairs its "back" line).
    public func checkBRB() {
        guard let s = streamer, s.live, roleActive == nil || roleActive == "brb" else {
            weakTicks = 0; goodTicks = 0; weakNoticed = false; return
        }
        // Backlog, not throughput: a still BRB card encodes far below target, so "sent >= 70% of target" would never
        // come true and BRB would stick. Seconds of video waiting in the uplink queue reads the link the same either way.
        let backlog = Double(s.hot.queueBytesOut * 8) / Double(max(s.currentBitrateKbps, 500) * 1000)
        let weak = s.downSince != nil || backlog > 2
        let good = s.downSince == nil && backlog < 0.5
        weakTicks = weak ? weakTicks + 1 : 0
        goodTicks = good ? goodTicks + 1 : 0
        if roleActive == nil, !weakNoticed, weakTicks >= 5 {
            if !roleSelect("brb") { weakNoticed = true; sceneRole("brb", on: true) }
        } else if goodTicks >= 10, roleActive == "brb" {
            roleEnd()
        } else if goodTicks >= 10, weakNoticed {
            weakNoticed = false; sceneRole("brb", on: false)
        }
    }

    /// The Stop button: with an Ending scene, hold it for the Ending hold before stopping; a second tap stops now.
    public func requestStop() {
        guard let s = streamer else { return }
        let hold = endingHoldSeconds
        if roleActive == "ending" { s.stopLive(); return }
        roleTask?.cancel()
        guard s.live, hold > 0, roleSelect("ending") else { s.stopLive(); return }
        s.endingIn = hold
        roleTask = Task {
            for left in stride(from: hold, to: 0, by: -1) {
                s.endingIn = left
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            s.stopLive()
        }
    }
}
