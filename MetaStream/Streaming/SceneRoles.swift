// Scene roles: scenes the app switches to on its own. Starting (countdown after going live), BRB (while the link is
// too weak) and Ending (held briefly after Stop). Role switches go through applyScene, not selectScene, so they don't
// cancel themselves; any manual selectScene ends the role (see clearRole).
import Foundation

extension Streamer {

    private var startCountdownSeconds: Int { UserDefaults.standard.object(forKey: "startCountdown") as? Int ?? 60 }
    private var endingHoldSeconds: Int { UserDefaults.standard.object(forKey: "endingHold") as? Int ?? 10 }

    /// Hook for role changes: logs, and the app bot posts its chat notice.
    func sceneRole(_ role: String, on: Bool) {
        applog("overlay", "role \(role) \(on ? "on" : "off") -> \(OverlayStore.shared.scene)")
        AppBot.shared.role(role, on: on)
    }

    /// {countdown}: remaining Starting time as m:ss, empty when no countdown runs.
    var countdownText: String {
        guard let end = countdownEnd else { return "" }
        return Self.fmtClock(max(0, end.timeIntervalSinceNow.rounded(.up)))
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
    func roleEnd() {
        guard let role = roleActive else { return }
        let back = roleBack ?? ""
        clearRole(log: false)
        applyScene(back)
        sceneRole(role, on: false)
    }

    /// Role over without a return (manual pick, or a cancelled Ending hold). No-op when no role is up.
    func clearRole(log: Bool = true) {
        guard let role = roleActive else { return }
        roleActive = nil; roleBack = nil; countdownEnd = nil; endingIn = nil
        roleTask?.cancel(); roleTask = nil
        weakTicks = 0; goodTicks = 0
        updateSceneRotation()
        if log { sceneRole(role, on: false) }
    }

    // MARK: Starting

    /// First connect of a session: show the Starting scene for the countdown, then go back.
    func startRole() {
        let secs = startCountdownSeconds
        guard secs > 0, roleSelect("starting") else { return }
        countdownEnd = Date().addingTimeInterval(TimeInterval(secs))
        roleTask = Task {
            try? await Task.sleep(for: .seconds(secs))
            if !Task.isCancelled { roleEnd() }
        }
    }

    // MARK: BRB

    /// Called from the 1 s tick. A dropped link or over 2 s of video stuck in the uplink queue for 5 s puts the BRB
    /// scene up; connected with under 0.5 s queued for 10 s takes it down.
    func checkBRB() {
        guard live, roleActive == nil || roleActive == "brb" else { weakTicks = 0; goodTicks = 0; return }
        // Backlog, not throughput: a still BRB card encodes far below target, so "sent >= 70% of target" would never
        // come true and BRB would stick. Seconds of video waiting in the uplink queue reads the link the same either way.
        let backlog = Double(hot.queueBytesOut * 8) / Double(max(currentBitrateKbps, 500) * 1000)
        let weak = downSince != nil || backlog > 2
        let good = downSince == nil && backlog < 0.5
        weakTicks = weak ? weakTicks + 1 : 0
        goodTicks = good ? goodTicks + 1 : 0
        if roleActive == nil, weakTicks >= 5 {
            roleSelect("brb")
        } else if roleActive == "brb", goodTicks >= 10 {
            roleEnd()
        }
    }

    // MARK: Ending

    /// The Stop button: with an Ending scene, hold it for the Ending hold before stopping; a second tap stops now.
    func requestStop() {
        let hold = endingHoldSeconds
        if roleActive == "ending" { stopLive(); return }
        roleTask?.cancel()
        guard live, hold > 0, roleSelect("ending") else { stopLive(); return }
        endingIn = hold
        roleTask = Task {
            for left in stride(from: hold, to: 0, by: -1) {
                endingIn = left
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            stopLive()
        }
    }
}
