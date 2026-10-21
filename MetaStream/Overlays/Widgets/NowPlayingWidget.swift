// Native Now playing widget (Spotify): polls SpotifyNowPlaying while it is on a scene (retain / release) and plays the
// design's transition on each song change. Frame pacing: 33 ms while a transition runs; otherwise the always-moving
// designs (island, disc, ticker) redraw every 66 ms and the static ones only when the elapsed second, the progress bar's
// pixel width or the cover changes.
import HaishinKit
import SwiftUI
import UIKit

extension OverlayCompositor {
    func nowPlayingWidget(_ l: OverlayLayer, box: CGRect, canvas: CGSize) async -> WidgetBuild? {
        guard let rect = OverlayRaster.visible(box, in: canvas) else { return nil }
        let style = NowPlayingWidgetStyle(l.data)
        let o = await OverlayScreen.makeImage(rect, nil)
        let task = Task { await NowPlayingPlayer.run(style, on: o, box: box, canvas: canvas) }
        let object: ScreenObject = o
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

    static func run(_ style: NowPlayingWidgetStyle, on o: ImageScreenObject, box: CGRect, canvas: CGSize) async {
        let sp = SpotifyNowPlaying.shared
        sp.retain()
        defer { sp.release() }
        let d = style.design
        let natural = style.natural
        var current: Snap?        // the song on screen; nil = nothing shown
        var outgoing: Snap?       // the song leaving during a change or an exit
        var phase: Phase?
        var t0 = Date()           // when the running transition started
        var openedAt = Date()     // pop-up: when it started opening
        var hidden = false        // pop-up: closed after its hold; stays so until the next song
        var blank = true          // the bitmap is cleared
        var waiting: Date?        // when a new song first showed up without a cover
        var lastSig = ""

        func draw(_ snap: Snap, _ pose: NowPlayingPose, _ now: Date) async {
            let view = NowPlayingView(style: style, track: snap.track, art: snap.art, pose: pose,
                                      clock: now.timeIntervalSinceReferenceDate, now: now)
            let piece = WidgetRaster.piece(view, natural: natural, box: box, canvas: canvas)
            await OverlayScreen.setImage(o, piece?.bitmap)
            blank = false
        }
        func clear() async {
            guard !blank else { return }
            blank = true
            await OverlayScreen.setImage(o, nil)
        }

        while !Task.isCancelled {
            let now = Date()

            // What the music did since the last pass.
            if let live = sp.track {
                if live.id == current?.id {
                    waiting = nil
                    current?.track = live   // newest poll, so elapsed time and progress stay in step with Spotify
                    if current?.art == nil, let art = sp.art { current?.art = art }
                } else {
                    waiting = waiting ?? now
                    if sp.art != nil || now.timeIntervalSince(waiting ?? now) > artWait {
                        waiting = nil
                        let shown = current != nil && !hidden
                        // ponytail: a change arriving mid-transition restarts from the card as it is; no blending of poses.
                        if shown { outgoing = current }
                        phase = shown ? .change : .enter
                        current = Snap(track: live, art: sp.art)
                        t0 = now; lastSig = ""; hidden = false
                        openedAt = now.addingTimeInterval(shown ? NowPlayingMotion.timing(d).switchAt : 0)
                        applog("overlay", "now playing widget: \(shown ? "change" : "enter") (\(d.rawValue)) \(live.title)")
                    }
                }
            } else {
                waiting = nil
                if current != nil {
                    if !hidden {
                        outgoing = current; phase = .exit; t0 = now; lastSig = ""
                        applog("overlay", "now playing widget: exit (\(d.rawValue))")
                    }
                    current = nil; hidden = false
                }
            }

            // Pop-up: close it once it has been open for its hold time.
            if d == .popup, phase == nil, !hidden, current != nil,
               NowPlayingMotion.popupExitDue(openFor: now.timeIntervalSince(openedAt), hold: style.popupSeconds) {
                outgoing = current; phase = .exit; t0 = now; hidden = true
                applog("overlay", "now playing widget: pop-up closes after \(style.popupSeconds) s")
            }

            // A transition is running: one frame, then straight back for the next.
            if let ph = phase {
                let t = now.timeIntervalSince(t0)
                let total = switch ph {
                case .enter: NowPlayingMotion.enterTotal(d)
                case .change: NowPlayingMotion.total(d)
                case .exit: NowPlayingMotion.exitTotal(d)
                }
                if t < total {
                    switch ph {
                    case .enter:
                        if let c = current { await draw(c, NowPlayingMotion.enter(d, t: t), now) }
                    case .change:
                        let pose = NowPlayingMotion.change(d, t: t)
                        if let s = pose.useNew ? current : outgoing { await draw(s, pose, now) }
                    case .exit:
                        if let s = outgoing { await draw(s, NowPlayingMotion.exit(d, t: t), now) }
                    }
                    try? await Task.sleep(for: WidgetRaster.pause(33))
                    continue
                }
                phase = nil; outgoing = nil; lastSig = ""
                if ph == .exit { await clear() }   // the exit's last frame is fully faded: blank the bitmap
            }

            // Settled.
            guard let c = current, !hidden else {
                await clear()
                try? await Task.sleep(for: WidgetRaster.pause(250))
                continue
            }
            if d.isContinuous {
                await draw(c, .settled, now)
                try? await Task.sleep(for: WidgetRaster.pause(66))
            } else {
                let sig = "\(c.track.id)|\(c.art != nil)|\(d.showsTime ? c.track.elapsedMs(now) / 1000 : 0)"
                    + "|\(Int(c.track.progress(now) * d.barShare * box.width))"
                if sig != lastSig {
                    lastSig = sig
                    await draw(c, .settled, now)
                }
                try? await Task.sleep(for: WidgetRaster.pause(250))
            }
        }
    }
}
