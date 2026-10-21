// Native Now playing widget (Spotify): polls SpotifyNowPlaying while it is on a scene (retain / release) and plays the
// design's transition on each song change. Frame pacing: 33 ms while a transition runs; otherwise the always-moving
// designs (island, disc, ticker) redraw every 66 ms and the static ones only when the elapsed second, the progress bar's
// pixel width or the cover changes.
import HaishinKit
import SwiftUI
import UIKit

extension OverlayCompositor {
    func nowPlayingWidget(_ layer: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = NowPlayingWidgetStyle(layer.data)
        let screen = await OverlayScreen.makeImage(rect, nil)
        let task = Task { await NowPlayingPlayer.run(style, on: screen, box: box, canvas: canvas) }
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

    private enum Phase { case enter, change, exit }

    /// Longest a new song is held back waiting for its cover, so the transition lands with the picture in place.
    private static let artWait = 1.2

    static func run(_ style: NowPlayingWidgetStyle, on screen: ImageScreenObject, box: CGRect, canvas: CGSize) async {
        let spotify = SpotifyNowPlaying.shared
        spotify.retain()
        defer { spotify.release() }
        let state = State(style: style, screen: screen, box: box, canvas: canvas)
        while !Task.isCancelled {
            let now = Date()
            state.react(to: spotify, now)
            state.closePopupIfDue(now)
            // A transition is running: one frame, then straight back for the next.
            if await state.transitionFrame(now) {
                try? await Task.sleep(for: WidgetRaster.pause(33))
                continue
            }
            await state.drawSettled(now)
        }
    }

    /// What the player remembers between passes, and the steps of one pass.
    @MainActor private final class State {
        let style: NowPlayingWidgetStyle
        let screen: ImageScreenObject
        let box: CGRect
        let canvas: CGSize
        let design: NowPlayingDesign
        let natural: CGSize
        var current: Snap?        // the song on screen; nil = nothing shown
        var outgoing: Snap?       // the song leaving during a change or an exit
        var phase: Phase?
        var startedAt = Date()    // when the running transition started
        var openedAt = Date()     // pop-up: when it started opening
        var hidden = false        // pop-up: closed after its hold; stays so until the next song
        var blank = true          // the bitmap is cleared
        var waiting: Date?        // when a new song first showed up without a cover
        var lastSig = ""

        init(style: NowPlayingWidgetStyle, screen: ImageScreenObject, box: CGRect, canvas: CGSize) {
            self.style = style
            self.screen = screen
            self.box = box
            self.canvas = canvas
            design = style.design
            natural = style.natural
        }

        func draw(_ snap: Snap, _ pose: NowPlayingPose, _ now: Date) async {
            let view = NowPlayingView(style: style, track: snap.track, art: snap.art, pose: pose,
                                      clock: now.timeIntervalSinceReferenceDate, now: now)
            let piece = WidgetRaster.piece(view, natural: natural, box: box, canvas: canvas)
            await OverlayScreen.setImage(screen, piece?.bitmap)
            blank = false
        }

        func clear() async {
            guard !blank else { return }
            blank = true
            await OverlayScreen.setImage(screen, nil)
        }

        /// What the music did since the last pass.
        func react(to spotify: SpotifyNowPlaying, _ now: Date) {
            guard let live = spotify.track else { songGone(now); return }
            if live.id == current?.id {
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
            startedAt = now; lastSig = ""; hidden = false
            openedAt = now.addingTimeInterval(shown ? NowPlayingMotion.timing(design).switchAt : 0)
            applog("overlay", "now playing widget: \(shown ? "change" : "enter") (\(design.rawValue)) \(live.title)")
        }

        func songGone(_ now: Date) {
            waiting = nil
            guard current != nil else { return }
            if !hidden {
                outgoing = current; phase = .exit; startedAt = now; lastSig = ""
                applog("overlay", "now playing widget: exit (\(design.rawValue))")
            }
            current = nil; hidden = false
        }

        /// Pop-up: close it once it has been open for its hold time.
        func closePopupIfDue(_ now: Date) {
            guard design == .popup, phase == nil, !hidden, current != nil,
                  NowPlayingMotion.popupExitDue(openFor: now.timeIntervalSince(openedAt), hold: style.popupSeconds) else { return }
            outgoing = current; phase = .exit; startedAt = now; hidden = true
            applog("overlay", "now playing widget: pop-up closes after \(style.popupSeconds) s")
        }

        /// Draws one frame of the running transition and returns true; false once there is none (or it just ended).
        func transitionFrame(_ now: Date) async -> Bool {
            guard let running = phase else { return false }
            let elapsed = now.timeIntervalSince(startedAt)
            if elapsed < total(running) {
                await drawFrame(running, elapsed, now)
                return true
            }
            phase = nil; outgoing = nil; lastSig = ""
            if running == .exit { await clear() }   // the exit's last frame is fully faded: blank the bitmap
            return false
        }

        func total(_ running: Phase) -> Double {
            switch running {
            case .enter: NowPlayingMotion.enterTotal(design)
            case .change: NowPlayingMotion.total(design)
            case .exit: NowPlayingMotion.exitTotal(design)
            }
        }

        func drawFrame(_ running: Phase, _ elapsed: Double, _ now: Date) async {
            switch running {
            case .enter:
                if let song = current { await draw(song, NowPlayingMotion.enter(design, t: elapsed), now) }
            case .change:
                let pose = NowPlayingMotion.change(design, t: elapsed)
                if let song = pose.useNew ? current : outgoing { await draw(song, pose, now) }
            case .exit:
                if let song = outgoing { await draw(song, NowPlayingMotion.exit(design, t: elapsed), now) }
            }
        }

        /// Settled: nothing is moving, so redraw only when something visible changed.
        func drawSettled(_ now: Date) async {
            guard let song = current, !hidden else {
                await clear()
                try? await Task.sleep(for: WidgetRaster.pause(250))
                return
            }
            if design.isContinuous {
                await draw(song, .settled, now)
                try? await Task.sleep(for: WidgetRaster.pause(66))
                return
            }
            let sig = "\(song.track.id)|\(song.art != nil)|\(design.showsTime ? song.track.elapsedMs(now) / 1000 : 0)"
                + "|\(Int(song.track.progress(now) * design.barShare * box.width))"
            if sig != lastSig {
                lastSig = sig
                await draw(song, .settled, now)
            }
            try? await Task.sleep(for: WidgetRaster.pause(250))
        }
    }
}
