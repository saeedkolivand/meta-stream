import SwiftUI

/// The four story layouts (Settings > Theme & story). One setting (`igStoryTemplate`).
enum StoryTemplate: String, CaseIterable, Identifiable {
    case minimal, fullBleed, poster, bilingual

    var id: String { rawValue }

    static var current: StoryTemplate {
        UserDefaults.standard.string(forKey: "igStoryTemplate").flatMap(StoryTemplate.init(rawValue:)) ?? .minimal
    }

    var name: String {
        switch self {
        case .minimal: "Minimal"
        case .fullBleed: "Full bleed"
        case .poster: "Poster"
        case .bilingual: "Bilingual FA / EN"
        }
    }
}

/// The story card, designed at 360x640 points (9:16), rendered at scale 3. All colours come from the theme; the lower
/// area stays empty for the Link sticker (nothing is drawn there, not even a placeholder).
struct StoryCard: View {
    let frame: UIImage?
    let title: String
    let link: String
    let template: StoryTemplate
    let theme: ColorTheme

    var body: some View {
        Group {
            switch template {
            case .minimal: minimal
            case .fullBleed: fullBleed
            case .poster: poster
            case .bilingual: bilingual
            }
        }
        .frame(width: 360, height: 640, alignment: .topLeading)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The colour at the card's outer edge, for Instagram's background layer around it.
    var edge: UInt32 { template == .poster ? theme.accent : theme.bg }

    private var text: Color { theme.color(theme.text) }
    private var muted: Color { theme.color(theme.muted) }
    private var shortLink: String { link.replacingOccurrences(of: "https://", with: "") }

    private func persian(_ weight: String, _ size: CGFloat) -> Font { .custom("Vazirmatn-\(weight)", size: size) }

    /// Accent capsule with an onAccent dot and label.
    private func pill(_ label: String, _ size: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle().fill(theme.color(theme.onAccent)).frame(width: 8, height: 8)
            Text(label).font(.system(size: size, weight: .bold))
        }
        .foregroundStyle(theme.color(theme.onAccent))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(theme.color(theme.accent), in: Capsule())
    }

    @ViewBuilder private func shot(_ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> some View {
        if let frame {
            Image(uiImage: frame).resizable().scaledToFill()
                .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: radius))
        }
    }

    // MARK: layouts

    private var minimal: some View {
        VStack(alignment: .leading, spacing: 16) {
            pill("LIVE on Kick", 15)
            shot(312, 175.5, 14)
            if !title.isEmpty { Text(title).font(.system(size: 24, weight: .bold)).lineLimit(3) }
            if !link.isEmpty { Text(shortLink).font(.system(size: 15)).foregroundStyle(muted) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(text)
        .padding(.top, 84).padding(.horizontal, 24)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(theme.color(theme.bg))
    }

    private var fullBleed: some View {
        ZStack {
            theme.color(theme.surface)
            shot(360, 640, 0)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    pill("LIVE", 14)
                    if !title.isEmpty { Text(title).font(.system(size: 22, weight: .bold)).lineLimit(2) }
                }
                .padding(.top, 72).padding(.horizontal, 20).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color(theme.bg))
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Color.clear.frame(height: 72)   // the Link sticker goes here
                    if !link.isEmpty { Text(shortLink).font(.system(size: 14)).foregroundStyle(muted) }
                }
                .padding(.top, 18).padding(.horizontal, 20).padding(.bottom, 96)
                .frame(maxWidth: .infinity)
                .background(theme.color(theme.bg))
            }
            .foregroundStyle(text)
        }
    }

    private var poster: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LIVE\nNOW").font(.system(size: 76, weight: .black)).lineSpacing(-12)
            if !title.isEmpty { Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(3) }
            shot(312, 176, 10)
            if !link.isEmpty { Text(shortLink).font(.system(size: 14, weight: .semibold)) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.color(theme.onAccent))
        .padding(.top, 76).padding(.horizontal, 24)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(theme.color(theme.accent))
    }

    private var bilingual: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                pill("LIVE", 15)
                Spacer()
                Text("الان لایوم").font(persian("Bold", 18))
            }
            shot(312, 175.5, 14)
            if !title.isEmpty { Text(title).font(.system(size: 24, weight: .bold)).lineLimit(3) }
            Text("بیاید تو لایو، لینک پایینه").font(persian("Regular", 16)).foregroundStyle(muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !link.isEmpty { Text(shortLink).font(.system(size: 15)).foregroundStyle(muted) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(text)
        .padding(.top, 84).padding(.horizontal, 24)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(theme.color(theme.bg))
    }
}
