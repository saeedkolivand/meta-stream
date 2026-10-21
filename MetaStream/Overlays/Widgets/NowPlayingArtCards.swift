// Now playing cards on the GPU: Slab, Island, Disc, Ticker. Same geometry, colours and sizes as NowPlayingDesigns.swift
// (natural points), the pose lanes applied per element about that element's centre like SwiftUI's npLane.
import CoreImage
import UIKit

extension NPDraw {
    /// Dark card: cover, NOW PLAYING in the accent, title, artist, progress bar with times. Title and artist slide up.
    func slab() -> CIImage {
        let label = NPRun(text: "NOW PLAYING", size: 22, color: accent, tracking: 2.6 / 22)
        let title = NPRun(text: track.title, size: 40)
        let artist = NPRun(text: track.artist, size: 30, weight: .regular, color: Self.grey)
        let labelH = measure(label).height, titleH = measure(title).height, artistH = measure(artist).height
        let colH = labelH + titleH + artistH + 16
        let rowH = max(144, colH)
        let colX: CGFloat = 200, colW: CGFloat = 612
        let colTop = 28 + (rowH - colH) / 2
        let titleTop = colTop + labelH + 8, artistTop = titleTop + titleH + 8
        let coverY = 28 + (rowH - 144) / 2

        let small = { (text: String) in NPRun(text: text, size: 24, weight: .regular, color: Self.grey) }
        let timeH = measure(small("0:00")).height
        let timeTop = 28 + rowH + 24, timeMid = timeTop + timeH / 2
        let elapsedW = measure(small(Self.tabular(elapsed))).width, totalW = measure(small(Self.tabular(total))).width
        let barLeft = 28 + elapsedW + 20, barWidth = max(0, 812 - totalW - 20 - barLeft)
        let bar = CGRect(x: barLeft, y: timeMid - 4, width: barWidth, height: 8)

        let pivot = CGPoint(x: colX + colW / 2, y: colTop)
        return pen.stack([
            pill(CGRect(x: 0, y: 0, width: 840, height: timeTop + timeH + 28), 32, Self.card),
            lane(cover(x: 28, y: coverY, size: 144, radius: 20), pose.cover, pivot: CGPoint(x: 100, y: coverY + 72)),
            text(label, left: colX, midY: colTop + labelH / 2),
            lane(text(fit(title, width: colW), left: colX, midY: titleTop + titleH / 2), pose.line1, pivot: pivot),
            lane(text(fit(artist, width: colW), left: colX, midY: artistTop + artistH / 2), pose.line2, pivot: pivot),
            text(small(elapsed), left: 28, midY: timeMid),
            pill(bar, 4, Self.trackBar),
            pill(CGRect(x: barLeft, y: bar.minY, width: barWidth * CGFloat(progress), height: 8), 4, accent),
            text(small(total), left: 812 - totalW, midY: timeMid)
        ])
    }

    /// Capsule that collapses to the round cover, the cover pops, and the capsule springs open again. Three level bars
    /// play all the time. The content is laid out at the open width and only clipped narrower, so text never reflows.
    func island() -> CIImage {
        let width = min(880, max(152, 152 + 688 * pose.reveal))
        let capsule = pill(CGRect(x: 0, y: 0, width: width, height: 152), 76, Self.island)
        let title = fit(NPRun(text: track.title, size: 38), width: 568)
        let artist = fit(NPRun(text: track.artist, size: 28, weight: .regular, color: Self.grey), width: 568)
        let titleH = measure(title).height, artistH = measure(artist).height
        let top = 76 - (titleH + 6 + artistH) / 2
        let words = pen.stack([
            text(title, left: 160, midY: top + titleH / 2),
            text(artist, left: 160, midY: top + titleH + 6 + artistH / 2)
        ] + bars(NPBars(left: 756, bottom: 98, width: 8, height: 44, gap: 6, radius: 4, period: 0.9, step: 0.3, low: 0.35)))
        let content = [
            lane(cover(x: 20, y: 40, size: 112, radius: 56), pose.cover, pivot: CGPoint(x: 76, y: 76)),
            pen.opacity(words, Double(pose.line1.alpha))
        ]
        return pen.stack([capsule, pen.clip(pen.stack(content), to: capsule)])
    }

    /// Round cover that spins all the time inside a progress ring; the disc drops out, a new one drops in with a bounce,
    /// and the text slides sideways. ring: the track is a plain ring; the progress is a drawn-on stroke (progressStroke +
    /// reveal) round the same circle, starting at 12 o'clock and running clockwise.
    func disc() -> CIImage {
        let middle = CGPoint(x: 116, y: 112)
        let card = pill(CGRect(x: 0, y: 0, width: 860, height: 224), 36, Self.card)
        let around = (0...96).map { step -> CGPoint in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(step) / 96
            return point(CGPoint(x: middle.x + 86 * CGFloat(cos(angle)), y: middle.y + 86 * CGFloat(sin(angle))))
        }
        var spin = pose.cover
        spin.rot += NowPlayingMotion.spin(clock)
        let record = pen.stack([cover(x: 42, y: 38, size: 148, radius: 74), pen.disc(point(middle), 8 * ratio, Self.card)])

        let title = fit(NPRun(text: track.title, size: 40), width: 584)
        let artist = fit(NPRun(text: track.artist, size: 30, weight: .regular, color: Self.grey), width: 584)
        let time = NPRun(text: "\(elapsed) / \(total)", size: 24, weight: .regular, color: Self.grey)
        let titleH = measure(title).height, artistH = measure(artist).height, timeH = measure(time).height
        let top = 112 - (titleH + artistH + timeH + 16) / 2
        let words = pen.stack([
            text(title, left: 240, midY: top + titleH / 2),
            text(artist, left: 240, midY: top + titleH + 8 + artistH / 2),
            text(time, left: 240, midY: top + titleH + artistH + 16 + timeH / 2)
        ])
        let layers = [
            card,
            pen.ring(point(middle), inner: 82 * ratio, outer: 90 * ratio, Self.trackBar),
            pen.reveal(pen.progressStroke(around, width: 8 * ratio), upTo: progress, accent),
            lane(record, spin, pivot: middle),
            lane(words, pose.line1, pivot: CGPoint(x: 532, y: 112))
        ]
        return pen.clip(pen.stack(layers), to: card)   // the disc leaves and arrives through the card's edge
    }

    /// Slim strip: small cover (flips), equaliser bars, "Title · Artist". The text clip-wipes out and in; the strip hugs it.
    func ticker() -> CIImage {
        let parts = [NPRun(text: track.title, size: 32),
                     NPRun(text: " · ", size: 32, weight: .regular, color: Self.dim),
                     NPRun(text: track.artist, size: 32, weight: .regular, color: Self.grey)]
        let laid = layout(parts, maxWidth: 720)
        let textLeft: CGFloat = 158
        let card = pill(CGRect(x: 0, y: 0, width: min(920, textLeft + laid.width + 32), height: 96), 20, Self.card)
        let wipe = fill(CGRect(x: textLeft + laid.width * pose.trail, y: 0,
                               width: max(0, laid.width * (pose.reveal - pose.trail)), height: 96), Self.white)
        return pen.stack([
            card,
            lane(cover(x: 12, y: 12, size: 72, radius: 12), pose.cover, pivot: CGPoint(x: 48, y: 48))
        ] + bars(NPBars(left: 108, bottom: 64, width: 6, height: 32, gap: 4, radius: 0, period: 0.8, step: 0.25, low: 0.3)) + [
            pen.clip(row(laid.runs, left: textLeft, midY: 48), to: wipe)
        ])
    }
}
