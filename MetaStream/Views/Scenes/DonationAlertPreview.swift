import SwiftUI

/// Loops the chosen donation design with the stream's own drawing code (like the stinger preview), over a stand-in scene.
/// The Island design is the CPU banner (AlertBannerView) driven by AlertIsland.pose, as on stream without a GPU mixer.
struct DonationAlertPreview: View {
    let style: AlertWidgetStyle
    @State private var start = Date()
    @State private var holder = CanvasHolder()
    @Environment(\.displayScale) private var displayScale

    /// Keeps one StingerCanvas (and its text cache) per preview size.
    private final class CanvasHolder {
        var canvas: StingerCanvas?
        func canvas(for size: CGSize) -> StingerCanvas {
            if let cached = canvas, cached.size == size { return cached }
            let made = StingerCanvas(size: size)
            canvas = made
            return made
        }
    }

    @MainActor private static let context = CIContext()

    /// A tip with a Persian message, so right-to-left layout is visible; EUR so the amount reads "€20".
    private static let tip = ChatEvent(kind: .tip, user: "Ali", text: "مرسی بابت استریم!", amountCents: 2000,
                                       money: Money(20, "EUR"), origin: "donofa")

    private static let info: DonationAlertInfo = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "d MMM yyyy"
        let date = fmt.string(from: Date()).uppercased()
        fmt.dateFormat = "HH:mm"
        let goal = DonationAlertInfo.Goal(title: "New camera", before: "€312", after: "€332", target: "€800",
                                          from: 0.39, to: 0.415, box: nil)
        return DonationAlertInfo(name: "Ali", initial: "A", amount: "€20", message: "مرسی بابت استریم!", source: "DONOFA",
                                 rate: "₮59,000/€", toGoal: "€20.00", tier: 1, date: date, time: fmt.string(from: Date()), goal: goal)
    }()

    var body: some View {
        TimelineView(.animation) { tl in
            let kind = style.donationKind
            let total = kind == .island ? AlertIsland.total(hold: style.holdSeconds) : kind.seconds / max(style.donationStyle.speed, 0.1)
            let secs = tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: total + 1)   // ~1 s rest between plays
            ZStack {
                Color(white: 0.12)
                Text("Your stream").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.35))
                if kind == .island { island(secs: secs) } else { art(kind: kind, secs: secs, total: total) }
            }
            .overlay(alignment: .topTrailing) {
                Button { start = Date() } label: { Image(systemName: "arrow.counterclockwise").padding(8) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Replay")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }

    private func art(kind: DonationAlertKind, secs: Double, total: Double) -> some View {
        Canvas { ctx, size in
            guard secs <= total, size.width >= 1, size.height >= 1 else { return }
            let px = CGSize(width: (size.width * displayScale).rounded(), height: (size.height * displayScale).rounded())
            let board = holder.canvas(for: px)
            // Top-left art flipped once into Core Image's bottom-left space, as OverlayScreen does on stream.
            let image = DonationArt.frame(kind, p: secs / total, info: Self.info, style: style.donationStyle, c: board, box: nil)
                .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: board.size.height))
                .cropped(to: board.bounds)
            guard let cg = Self.context.createCGImage(image, from: board.bounds, format: .BGRA8,
                                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            else { return }
            ctx.draw(Image(decorative: cg, scale: displayScale), in: CGRect(origin: .zero, size: size))
        }
    }

    /// The 900x240 banner scaled to the preview width.
    private func island(secs: Double) -> some View {
        GeometryReader { geo in
            let big = AlertIsland.isBig(Self.tip)
            AlertBannerView(event: Self.tip, style: style, pose: AlertIsland.pose(at: min(secs, AlertIsland.total(hold: style.holdSeconds)),
                                                                                  hold: style.holdSeconds, big: big))
                .frame(width: 900, height: 240)
                .scaleEffect(geo.size.width / 900, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}
