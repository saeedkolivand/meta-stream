import SwiftUI

/// The goal widget's look over a dark stand-in for the stream, at the stream's 16:9, drawn by the same views the
/// stream uses (GoalView for the bar, GoalDesignView for the rest) with sample numbers.
struct GoalPreview: View {
    let style: GoalWidgetStyle

    var body: some View {
        GeometryReader { geo in
            let natural = style.natural
            // The widget at its real size on a 1920x1080 stream, so the preview shows how big it will look.
            let fit = geo.size.width / 1920
            ZStack {
                Color(white: 0.12)
                Text("Your stream").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.35))
                sample
                    .frame(width: natural.width, height: natural.height)
                    .scaleEffect(fit)
                    .frame(width: natural.width * fit, height: natural.height * fit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder private var sample: some View {
        if style.design == "bar" { GoalView.sample(style) } else { GoalDesignView.sample(style) }
    }
}
