// Now playing in the text-widget look on the GPU: Text, Two lines, Text with cover, Pop-up. Same layout as
// NowPlayingDesignsText.swift: 20% near-black box hugging its content (padding 9.6), bold white text, drop shadow.
// The music.note SF Symbol stands where the emoji used to be.
import CoreImage
import UIKit

extension NPDraw {
    private static let noteSlot: CGFloat = 36   // the note's share of a row (the emoji was ~38 wide)

    private func note(left: CGFloat, midY: CGFloat) -> CIImage {
        pen.symbol("music.note", pointSize: 30 * ratio, color: Self.white, at: point(CGPoint(x: left + Self.noteSlot / 2, y: midY)))
    }

    /// The box with `content` on it, wiped from the left: at reveal 0 only `shut` points of it show.
    private func wiped(_ content: CIImage, size: CGSize, shut: CGFloat) -> CIImage {
        let right = shut + (size.width - shut) * pose.reveal
        let left = size.width * pose.trail
        let wipe = fill(CGRect(x: left, y: 0, width: max(0, right - left), height: size.height), Self.white)
        return pen.clip(pen.stack([fill(CGRect(origin: .zero, size: size), Self.box), content]), to: wipe)
    }

    /// Note + text row in the plain box (Text and Pop-up).
    private func noted(_ parts: [NPRun], maxWidth: CGFloat, shut: CGFloat) -> CIImage {
        let pad: CGFloat = 9.6, left = pad + Self.noteSlot + 12
        let laid = layout(parts, maxWidth: maxWidth - left - pad)
        let height = (measure(parts[0]).height + 2 * pad).rounded(.up)
        let size = CGSize(width: left + laid.width + pad, height: height)
        let content = shadowed(pen.stack([note(left: pad, midY: height / 2), row(laid.runs, left: left, midY: height / 2)]))
        return wiped(content, size: size, shut: shut)
    }

    /// Note, then "Title · Artist"; a song change wipes the box back to just the note, then open again.
    func text() -> CIImage { noted([NPRun(text: line, size: 32)], maxWidth: 920, shut: 62) }

    /// Note, then "Now playing: Title · Artist"; the widget task closes it after the hold time.
    func popup() -> CIImage {
        noted([NPRun(text: "Now playing: ", size: 32, weight: .semibold), NPRun(text: line, size: 32)], maxWidth: 1040, shut: 0)
    }

    /// Note + title over the artist, a thin progress line along the bottom; the lines slide up one after the other.
    func twoLine() -> CIImage {
        let title = fit(NPRun(text: track.title, size: 32), width: 520 - 24 - Self.noteSlot - 12)
        let artist = fit(NPRun(text: track.artist, size: 26, weight: .semibold), width: 520 - 68 - 12)
        let titleH = measure(title).height, artistH = measure(artist).height
        let titleMid = 10 + titleH / 2, artistMid = 10 + titleH + 4 + artistH / 2
        let lines = shadowed(pen.stack([
            note(left: 12, midY: titleMid),
            lane(text(title, left: 12 + Self.noteSlot + 12, midY: titleMid), pose.line1, pivot: CGPoint(x: 260, y: titleMid)),
            lane(text(artist, left: 68, midY: artistMid), pose.line2, pivot: CGPoint(x: 260, y: artistMid))
        ]))
        let progressLine = pen.stack([
            fill(CGRect(x: 0, y: 94, width: 520, height: 4), Self.white, alpha: 0.25),
            fill(CGRect(x: 0, y: 94, width: 520 * CGFloat(progress), height: 4), accent)
        ])
        let area = fill(CGRect(x: 0, y: 0, width: 520, height: 98), Self.white)   // the lines slide in from inside the box
        return pen.clip(pen.stack([fill(CGRect(x: 0, y: 0, width: 520, height: 98), Self.box), lines, progressLine]), to: area)
    }

    /// A small square cover instead of the note; the box wipes and the cover flips on a song change.
    func cornerCover() -> CIImage {
        let parts = [NPRun(text: track.title, size: 32), NPRun(text: " · ", size: 32),
                     NPRun(text: track.artist, size: 32, weight: .semibold)]
        let left: CGFloat = 8 + 44 + 14
        let laid = layout(parts, maxWidth: 920 - left - 12)
        let size = CGSize(width: left + laid.width + 12, height: 60)
        let content = pen.stack([
            lane(cover(x: 8, y: 8, size: 44, radius: 0), pose.cover, pivot: CGPoint(x: 30, y: 30)),
            shadowed(row(laid.runs, left: left, midY: 30))
        ])
        return wiped(content, size: size, shut: 60)
    }
}
