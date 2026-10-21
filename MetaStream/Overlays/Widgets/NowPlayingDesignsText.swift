// Now playing in the app's text-widget look: 20% near-black box, square corners, padding 0.3 x font size, bold white
// text with a drop shadow. Text, Two lines, Text with cover and Pop-up. Font 32 (the mockups' 16 px x 2).
import SwiftUI

/// The text widgets' box, hugging its content and clip-wiped from the left: at reveal 0 only `shut` points of it show
/// (the note, or the cover), 0 hides it entirely.
struct NPBox<Content: View>: View {
    let x: NPContext
    let shut: CGFloat
    let maxWidth: CGFloat
    let pad: EdgeInsets
    let content: Content

    init(x: NPContext, shut: CGFloat, maxWidth: CGFloat, pad: EdgeInsets = EdgeInsets(top: 9.6, leading: 9.6, bottom: 9.6, trailing: 9.6),
         @ViewBuilder content: () -> Content) {
        self.x = x; self.shut = shut; self.maxWidth = maxWidth; self.pad = pad; self.content = content()
    }

    var body: some View {
        content
            .padding(pad)
            .background(Color.npBox)
            .clipShape(NPWipe(shut: shut, reveal: x.pose.reveal))
            .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

/// "🎵 Title · Artist"; a song change wipes the box back to just the note, then open again.
struct NPText: View {
    let x: NPContext

    var body: some View {
        NPBox(x: x, shut: 62, maxWidth: 920) {
            HStack(spacing: 12) {
                Text("🎵").font(x.font(32)).lineLimit(1).npShadow()
                npText(x.line, font: x.font(32), color: .white).npShadow()
            }
        }
    }
}

/// "🎵 Title" over the artist, a thin progress line along the bottom; the lines slide up one after the other.
struct NPTwoLine: View {
    let x: NPContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("🎵").font(x.font(32)).lineLimit(1)
                    npText(x.track.title, font: x.font(32), color: .white).frame(maxWidth: .infinity, alignment: .leading).npLane(x.pose.line1)
                }
                npText(x.track.artist, font: x.font(26, .semibold), color: .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 56).padding(.top, 4)
                    .npLane(x.pose.line2)
            }
            .padding(.horizontal, 12).padding(.top, 10)
            .npShadow()
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {   // edge to edge: the box's side padding does not apply to it
                Rectangle().fill(Color.white.opacity(0.25))
                Rectangle().fill(x.accent).frame(width: 520 * x.progress)
            }
            .frame(height: 4)
        }
        .frame(width: 520, height: 98, alignment: .top)
        .background(Color.npBox)
        .clipped()   // the lines slide in from inside the box
    }
}

/// A small square cover instead of the note; the box wipes and the cover flips on a song change.
struct NPCornerCover: View {
    let x: NPContext

    var body: some View {
        NPBox(x: x, shut: 60, maxWidth: 920, pad: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12)) {
            HStack(spacing: 14) {
                x.cover(44, radius: 0).npLane(x.pose.cover)
                npRuns([(x.track.title, x.font(32), .white), (" · ", x.font(32), .white), (x.track.artist, x.font(32, .semibold), .white)])
                    .npShadow()
            }
        }
    }
}

/// "🎵 Now playing: Title · Artist" wipes open on each song change; the widget task closes it after the hold time.
struct NPPopup: View {
    let x: NPContext

    var body: some View {
        NPBox(x: x, shut: 0, maxWidth: 1040) {
            HStack(spacing: 12) {
                Text("🎵").font(x.font(32)).lineLimit(1).npShadow()
                npRuns([("Now playing: ", x.font(32, .semibold), .white), (x.line, x.font(32), .white)]).npShadow()
            }
        }
    }
}
