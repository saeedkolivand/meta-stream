// Native Now playing widget (Spotify): polls SpotifyNowPlaying while it is on a scene (retain / release) and plays the
// design's transition on each song change. Drawn on the GPU (NowPlayingArt): the player only decides WHAT to show and
// hands the widget a GPUScene. A transition, and the always-moving designs (island, disc, ticker), are moving scenes
// whose pose is computed from t inside the renderer (video frame rate, no main-thread work); the static designs are
// still scenes, re-shown only when the elapsed second, the progress bar's pixel width or the cover changes.
import HaishinKit
import QuartzCore
import UIKit

extension OverlayCompositor {
    func nowPlayingWidget(_ layer: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = NowPlayingWidgetStyle(layer.data)
        let screen = await OverlayScreen.makeGPU(rect)
        // The box inside the widget's (visible) rect, in the rect's top-left coordinates.
        let local = CGRect(x: box.minX - rect.minX, y: box.minY - rect.minY, width: box.width, height: box.height)
        let task = Task { await NowPlayingPlayer.run(style, on: screen, box: box, local: local) }
        let object: ScreenObject = screen
        return WidgetBuild(object: object, task: task)
    }
}

@MainActor
enum NowPlayingPlayer {
    private struct Snap {
        var track: NowPlayingTrack
        var art: UIImage?
    }

    /// What a scene's closure keeps of a Snap: Sendable copies only (the cover as an immutable CGImage in a box).
    private struct Shot: Sendable {
        let track: NowPlayingTrack
        let art: NPArtBox?

        init(_ snap: Snap) {
            track = snap.track
            art = snap.art?.cgImage.map(NPArtBox.init)
        }
    }

    private enum Phase { case enter, change, exit }

    /// Longest a new song is held back waiting for its cover, so the transition lands with the picture in place.
    private static let artWait = 1.2

    static func run(_ style: NowPlayingWidgetStyle, on screen: GPUWidgetScreenObject, box: CGRect, local: CGRect) async {
        let spotify = SpotifyNowPlaying.shared
        spotify.retain()
        defer { spotify.release() }
        let state = State(style: style, screen: screen, box: box, local: local)
        while !Task.isCancelled {
            let now = Date()
            state.react(to: spotify, now)
            state.closePopupIfDue(now)
            // A transition runs on the GPU by itself: this loop only watches for its end (or a new song) every 50 ms.
            let running = await state.transitionStep(now)
            let pause = running ? 50 : await state.drawSettled(now)
            try? await Task.sleep(for: WidgetRaster.pause(pause))
        }
    }

    /// What the player remembers between passes, and the steps of one pass.
    @MainActor private final class State {
        let style: NowPlayingWidgetStyle
        let screen: GPUWidgetScreenObject
        let box: CGRect
        let local: CGRect
        let design: NowPlayingDesign
        var current: Snap?        // the song on screen; nil = nothing shown
        var outgoing: Snap?       // the song leaving during a change or an exit
        var phase: Phase?
        var startedAt = Date()    // when the running transition started
        var openedAt = Date()     // pop-up: when it started opening
        var hidden = false        // pop-up: closed after its hold; stays so until the next song
        var blank = true          // the widget shows nothing
        var sceneDirty = false    // a transition began and its moving scene is not shown yet
        var waiting: Date?        // when a new song first showed up without a cover
        var lastSig = ""

        init(style: NowPlayingWidgetStyle, screen: GPUWidgetScreenObject, box: CGRect, local: CGRect) {
            self.style = style
            self.screen = screen
            self.box = box
            self.local = local
            design = style.design
        }

        /// A scene of this widget: `frame(t)` says which song at which pose. Still scenes freeze `now` (and ignore t).
        func scene(moving: Bool, age: Double = 0, _ frame: @escaping @Sendable (Double) -> (Shot?, NowPlayingPose)) -> GPUScene {
            let style = style, local = local, began = Date().addingTimeInterval(-age)
            return GPUScene(draw: { canvas, time in
                let (shot, pose) = frame(time)
                guard let shot else { return .empty() }
                let now = moving ? began.addingTimeInterval(time) : began
                let input = NPInput(style: style, track: shot.track, art: shot.art?.image, pose: pose,
                                    clock: now.timeIntervalSinceReferenceDate, now: now)
                return NowPlayingArt.frame(input, pen: canvas, box: local)
            }, moving: moving, epoch: CACurrentMediaTime() - age)
        }

        func show(_ next: GPUScene?) async {
            blank = next == nil
            await OverlayScreen.show(screen, next)
        }

        func clear() async {
            guard !blank else { return }
            await show(nil)
        }

        /// What the music did since the last pass.
        func react(to spotify: SpotifyNowPlaying, _ now: Date) {
            guard let live = spotify.track else { songGone(now); return }
            if live.id == current?.track.id {
                waiting = nil
                current?.track = live   // newest poll, so elapsed time and progress stay in step with Spotify
                if current?.art == nil, let art = spotify.art { current?.art = art }
            } else {
                newSong(live, spotify, now)
            }
        }

        func newSong(_ live: NowPlayingTrack, _ spotify: SpotifyNowPlaying, _ now: Date) {
            waiting = waiting ?? now
            guard spotify.art != nil || now.timeIntervalSince(waiting ?? now) > NowPlayingPlayer.artWait else { return }
            waiting = nil
            let shown = current != nil && !hidden
            // ponytail: a change arriving mid-transition restarts from the card as it is; no blending of poses.
            if shown { outgoing = current }
            phase = shown ? .change : .enter
            current = Snap(track: live, art: spotify.art)
            startedAt = now; lastSig = ""; hidden = false; sceneDirty = true
            openedAt = now.addingTimeInterval(shown ? NowPlayingMotion.timing(design).switchAt : 0)
            applog("overlay", "now playing widget: \(shown ? "change" : "enter") (\(design.rawValue)) \(live.title)")
        }

        func songGone(_ now: Date) {
            waiting = nil
            guard current != nil else { return }
            if !hidden {
                outgoing = current; phase = .exit; startedAt = now; lastSig = ""; sceneDirty = true
                applog("overlay", "now playing widget: exit (\(design.rawValue))")
            }
            current = nil; hidden = false
        }

        /// Pop-up: close it once it has been open for its hold time.
        func closePopupIfDue(_ now: Date) {
            guard design == .popup, phase == nil, !hidden, current != nil,
                  NowPlayingMotion.popupExitDue(openFor: now.timeIntervalSince(openedAt), hold: style.popupSeconds) else { return }
            outgoing = current; phase = .exit; startedAt = now; hidden = true; sceneDirty = true
            applog("overlay", "now playing widget: pop-up closes after \(style.popupSeconds) s")
        }

        /// Starts the moving scene of a new transition; true while one is running, false once there is none (or it just ended).
        func transitionStep(_ now: Date) async -> Bool {
            guard let running = phase else { return false }
            let elapsed = now.timeIntervalSince(startedAt)
            if elapsed < total(running) {
                if sceneDirty {
                    sceneDirty = false
                    await show(transitionScene(running, age: elapsed))
                }
                return true
            }
            phase = nil; outgoing = nil; lastSig = ""
            if running == .exit { await clear() }   // the exit's last frame is fully faded: blank the widget
            return false
        }

        func total(_ running: Phase) -> Double {
            switch running {
            case .enter: NowPlayingMotion.enterTotal(design)
            case .change: NowPlayingMotion.total(design)
            case .exit: NowPlayingMotion.exitTotal(design)
            }
        }

        /// The whole transition as one moving scene: the pose comes from t, which the renderer advances every video frame.
        func transitionScene(_ running: Phase, age: Double) -> GPUScene {
            let design = design, now = current.map(Shot.init), before = outgoing.map(Shot.init)
            return scene(moving: true, age: age) { time in
                switch running {
                case .enter: return (now, NowPlayingMotion.enter(design, t: time))
                case .change:
                    let pose = NowPlayingMotion.change(design, t: time)
                    return (pose.useNew ? now : before, pose)
                case .exit: return (before, NowPlayingMotion.exit(design, t: time))
                }
            }
        }

        /// Settled: nothing is moving, so show a new scene only when something visible changed. Returns the pause in ms.
        func drawSettled(_ now: Date) async -> Int {
            guard let song = current, !hidden else {
                await clear()
                return 250
            }
            let sig: String
            if design.isContinuous {
                // The scene advances elapsed time and progress itself; a fresh poll (`at`) or the cover arriving re-bases it.
                sig = "\(song.track.id)|\(song.art != nil)|\(song.track.at.timeIntervalSince1970)"
            } else {
                sig = "\(song.track.id)|\(song.art != nil)|\(design.showsTime ? song.track.elapsedMs(now) / 1000 : 0)"
                    + "|\(Int(song.track.progress(now) * design.barShare * box.width))"
            }
            if sig != lastSig {
                lastSig = sig
                let shot = Shot(song)
                await show(scene(moving: design.isContinuous) { _ in (shot, .settled) })
            }
            return 250
        }
    }
}
