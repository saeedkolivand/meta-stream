// Now playing cards: Slab, Island, Disc, Ticker. Sizes are the mockups' px x 2 (they are half of a 1920x1080 canvas).
import SwiftUI

/// Dark card: cover, NOW PLAYING in the accent, title, artist, progress bar with times. Title and artist slide up.
struct NPSlab: View {
    let x: NPContext

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 28) {
                x.cover(144, radius: 20).npLane(x.pose.cover)
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOW PLAYING").font(x.font(22)).tracking(2.6).foregroundColor(x.accent).lineLimit(1)
                    npText(x.track.title, font: x.font(40), color: .white)
                        .frame(maxWidth: .infinity, alignment: .leading).npLane(x.pose.line1)
                    npText(x.track.artist, font: x.font(30, .regular), color: .npGrey)
                        .frame(maxWidth: .infinity, alignment: .leading).npLane(x.pose.line2)
                }
            }
            HStack(spacing: 20) {
                Text(x.elapsed)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.npTrack)
                        Capsule().fill(x.accent).frame(width: geo.size.width * x.progress)
                    }
                }
                .frame(height: 8)
                Text(x.total)
            }
            .font(x.font(24, .regular)).monospacedDigit().foregroundColor(.npGrey)
        }
        .padding(28)
        .frame(width: 840, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32).fill(Color.npCard))
    }
}

/// Capsule that collapses to the round cover, the cover pops, and the capsule springs open again. Three level bars
/// play all the time. The capsule is laid out at its open width and only clipped narrower, so text never reflows.
struct NPIsland: View {
    let x: NPContext
    private let openW: CGFloat = 840   // the spring overshoots past this by ~5% of the travel; the 880 natural width leaves room
    private let height: CGFloat = 152

    var body: some View {
        let width = min(880, max(height, height + (openW - height) * x.pose.reveal))
        HStack(spacing: 28) {
            x.cover(112, radius: 56).npLane(x.pose.cover)
            VStack(alignment: .leading, spacing: 6) {
                npText(x.track.title, font: x.font(38), color: .white)
                npText(x.track.artist, font: x.font(28, .regular), color: .npGrey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(x.pose.line1.alpha)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4).fill(x.accent).frame(width: 8, height: 44)
                        .scaleEffect(y: NowPlayingMotion.eq(x.clock, period: 0.9, offset: 0.3 * Double(index), low: 0.35), anchor: .bottom)
                }
            }
            .frame(height: 44)
            .padding(.trailing, 28)
            .opacity(x.pose.line1.alpha)
        }
        .padding(20)
        .frame(width: openW, height: height, alignment: .leading)
        .frame(width: width, height: height, alignment: .leading)
        .background(Capsule().fill(Color.npIsland))
        .clipShape(Capsule())
    }
}

/// Round cover that spins all the time inside a progress ring; the disc drops out, a new one drops in with a bounce,
/// and the text slides sideways.
struct NPDisc: View {
    let x: NPContext

    private var discLane: NowPlayingLane {
        var lane = x.pose.cover
        lane.rot += NowPlayingMotion.spin(x.clock)
        return lane
    }

    var body: some View {
        HStack(spacing: 32) {
            ZStack {
                Circle().stroke(Color.npTrack, lineWidth: 8).frame(width: 172, height: 172)
                Circle().trim(from: 0, to: x.progress)
                    .stroke(x.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 172, height: 172).rotationEffect(.degrees(-90))
                ZStack {
                    x.cover(148, radius: 74)
                    Circle().fill(Color.npCard).frame(width: 16, height: 16)   // spindle hole
                }
                .npLane(discLane)
            }
            .frame(width: 184, height: 184)
            VStack(alignment: .leading, spacing: 8) {
                npText(x.track.title, font: x.font(40), color: .white)
                npText(x.track.artist, font: x.font(30, .regular), color: .npGrey)
                Text("\(x.elapsed) / \(x.total)").font(x.font(24, .regular)).monospacedDigit().foregroundColor(.npGrey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .npLane(x.pose.line1)
        }
        .padding(.leading, 24).padding(.trailing, 36)
        .frame(width: 860, height: 224, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 36).fill(Color.npCard))
        .clipShape(RoundedRectangle(cornerRadius: 36))   // the disc leaves and arrives through the card's edge
    }
}

/// Slim strip: small cover (flips), equaliser bars, "Title · Artist". The text clip-wipes out and in; the strip hugs it.
struct NPTicker: View {
    let x: NPContext

    var body: some View {
        HStack(spacing: 24) {
            x.cover(72, radius: 12).npLane(x.pose.cover)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle().fill(x.accent).frame(width: 6, height: 32)
                        .scaleEffect(y: NowPlayingMotion.eq(x.clock, period: 0.8, offset: 0.25 * Double(index), low: 0.3), anchor: .bottom)
                }
            }
            .frame(height: 32)
            npRuns([(x.track.title, x.font(32), .white), (" · ", x.font(32, .regular), .npDim),
                    (x.track.artist, x.font(32, .regular), .npGrey)])
                .frame(maxWidth: 720, alignment: .leading)
                .clipShape(NPWipe(shut: 0, reveal: x.pose.reveal, trail: x.pose.trail))
        }
        .padding(.leading, 12).padding(.trailing, 32)
        .frame(height: 96)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.npCard))
        .frame(maxWidth: 920, alignment: .leading)
    }
}
