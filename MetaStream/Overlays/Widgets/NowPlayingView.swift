// Native Now playing widget view: one of eight designs (NowPlayingDesigns / NowPlayingDesignsText) drawn at one pose.
// Flat fills only. The cover is the real album art, aspect-filled and clipped to each design's shape; until it has
// downloaded a flat accent-tinted placeholder with a note stands in.
import SwiftUI
import UIKit

extension Color {
    static let npCard = Color(red: 20 / 255, green: 21 / 255, blue: 24 / 255)       // the mockups' #141518
    static let npIsland = Color(red: 17 / 255, green: 18 / 255, blue: 20 / 255)     // #111214
    static let npGrey = Color(red: 0xA9 / 255, green: 0xAD / 255, blue: 0xB5 / 255)
    static let npDim = Color(red: 0x6F / 255, green: 0x74 / 255, blue: 0x7D / 255)
    static let npTrack = Color(red: 0x2C / 255, green: 0x2F / 255, blue: 0x35 / 255)
    static let npBox = Color(uiColor: OverlayRaster.color(argb: 0x3310_1014))      // the text widgets' 20% near-black box
}

/// What every design reads: the song on screen, its cover, the pose of this frame and the clock for endless motion.
@MainActor
struct NPContext {
    let style: NowPlayingWidgetStyle
    let track: NowPlayingTrack
    let art: UIImage?
    let pose: NowPlayingPose
    let clock: Double
    let now: Date

    var accent: Color { Color(uiColor: OverlayRaster.color(argb: style.accentColor)) }
    func font(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> Font { WidgetFonts.font(face: style.face, size: size, weight: weight) }
    var elapsed: String { Self.mmss(track.elapsedMs(now)) }
    var total: String { Self.mmss(track.durationMs) }
    var progress: CGFloat { CGFloat(min(1, max(0, track.progress(now)))) }
    /// "Title · Artist"; just the title for a track without artists.
    var line: String { track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)" }

    static func mmss(_ ms: Int) -> String {
        let secs = max(0, ms) / 1000
        return "\(secs / 60):" + String(format: "%02d", secs % 60)
    }

    func cover(_ size: CGFloat, radius: CGFloat) -> some View { NPCover(art: art, accent: accent, size: size, radius: radius) }
}

struct NowPlayingView: View {
    let style: NowPlayingWidgetStyle
    let track: NowPlayingTrack
    let art: UIImage?
    let pose: NowPlayingPose
    let clock: Double         // absolute seconds: the disc's spin and the equaliser bars are functions of it
    var now = Date()          // when elapsed time and progress are read

    var body: some View {
        let x = NPContext(style: style, track: track, art: art, pose: pose, clock: clock, now: now)
        let size = style.natural
        Group {
            switch style.design {
            case .slab: NPSlab(x: x)
            case .island: NPIsland(x: x)
            case .disc: NPDisc(x: x)
            case .ticker: NPTicker(x: x)
            case .text: NPText(x: x)
            case .twoLine: NPTwoLine(x: x)
            case .cover: NPCornerCover(x: x)
            case .popup: NPPopup(x: x)
            }
        }
        .opacity(pose.alpha)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Editor preview: a settled card for a made-up song.
    static func sample(_ style: NowPlayingWidgetStyle) -> NowPlayingView {
        NowPlayingView(style: style, track: NowPlayingTrack(id: "sample", title: "Blinding Lights", artist: "The Weeknd", artURL: "",
                                                            durationMs: 200_000, progressMs: 62_000, at: Date()),
                       art: nil, pose: .settled, clock: 0.3)
    }
}

// MARK: shared pieces

/// Album art (or the placeholder) as a square of `size` with rounded corners; radius size/2 makes it a circle.
struct NPCover: View {
    let art: UIImage?
    let accent: Color
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let art {
                Image(uiImage: art).resizable().scaledToFill().frame(width: size, height: size).clipped()
            } else {
                accent.opacity(0.35)
                Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .bold)).foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Left-to-right wipe: shows from `trail` to a right edge that moves from `shut` points wide (at reveal 0) to the full
/// width (reveal 1). `shut` 0 hides the box completely.
struct NPWipe: Shape {
    var shut: CGFloat
    var reveal: CGFloat
    var trail: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let right = shut + (rect.width - shut) * reveal
        let left = rect.width * trail
        return Path(CGRect(x: rect.minX + left, y: rect.minY, width: max(0, right - left), height: rect.height))
    }
}

extension View {
    /// One animated element of the pose (offset, scale, flip, spin, opacity).
    func npLane(_ lane: NowPlayingLane) -> some View {
        scaleEffect(x: max(0.001, lane.scale * lane.scaleX), y: max(0.001, lane.scale))
            .rotationEffect(.degrees(lane.rot))
            .offset(x: lane.dx, y: lane.dy)
            .opacity(lane.alpha)
    }

    /// The text widgets' drop shadow (0, 2, blur 4, black 80%).
    func npShadow() -> some View { shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2) }
}

/// One run of text. Persian/Arabic flows right-to-left, but the direction is set on the Text alone (GoalView's rule), so the
/// frames and stacks around it stay left-anchored and the card layout never mirrors.
@MainActor func npText(_ text: String, font: Font, color: Color) -> some View {
    Text(text).font(font).foregroundColor(color).lineLimit(1)
        .environment(\.layoutDirection, WidgetFonts.isRTL(text) ? .rightToLeft : .leftToRight)
}

/// Several styled runs on one line ("Title · Artist" with a dim dot). Direction follows the first run.
@MainActor func npRuns(_ parts: [(text: String, font: Font, color: Color)]) -> some View {
    var out = AttributedString()
    for part in parts {
        var run = AttributedString(part.text)
        run.font = part.font
        run.foregroundColor = part.color
        out += run
    }
    return Text(out).lineLimit(1)
        .environment(\.layoutDirection, WidgetFonts.isRTL(parts.first?.text ?? "") ? .rightToLeft : .leftToRight)
}
