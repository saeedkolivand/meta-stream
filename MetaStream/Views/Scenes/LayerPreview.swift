import SwiftUI

/// One layer drawn in the editor canvas with the same SwiftUI views the stream renders from, laid out at natural size
/// and scaled to the canvas rect, so what you arrange is what viewers get.
struct LayerPreview: View {
    let layer: OverlayLayer
    let natural: CGSize
    let size: CGSize
    @ObservedObject var emotes: Emotes
    /// Live merged chat; empty falls back to the samples so a quiet chat still shows its look.
    let chat: [ChatEvent]

    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    private var file: String? { layer.type == .slideshow ? layer.files.first : layer.data["file"] }

    var body: some View {
        content
            .frame(width: natural.width, height: natural.height, alignment: .topLeading)
            .scaleEffect(size.width / max(natural.width, 1), anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .task(id: file) { await loadImage() }
    }

    @ViewBuilder private var content: some View {
        switch layer.type {
        case .chat:
            StreamChatView(events: chat.isEmpty ? StreamChatView.samples : chat, style: ChatWidgetStyle(layer.data), emotes: emotes)
        case .alerts:
            AlertBannerView(event: AlertBannerView.sample, style: AlertWidgetStyle(layer.data))
        case .events:
            EventListView(events: EventListView.samples, style: EventListStyle(layer.data))
        case .goal:
            let style = GoalWidgetStyle(layer.data)
            if style.design == "bar" { GoalView.sample(style) } else { GoalDesignView.sample(style) }
        case .nowplaying:
            NowPlayingView.sample(NowPlayingWidgetStyle(layer.data))
        case .qr:
            let style = QRWidgetStyle(layer.data)
            if let img = QRCode.image(style.text.isEmpty ? "https://example.com" : style.text, style: style, size: natural) {
                Image(uiImage: img).resizable().interpolation(.none)
            }
        case .text:
            textView
        case .image, .slideshow:
            if let image { Image(uiImage: image).resizable() } else { placeholder("photo") }
        case .color:
            Rectangle().fill(Color(uiColor: OverlayRaster.color(argb: UInt32(layer.data["color"] ?? "") ?? 0xFF000000)))
        case .browser:
            ZStack {
                RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 6, dash: [28, 18]))
                VStack(spacing: 12) {
                    Image(systemName: "globe").font(.system(size: 120))
                    Text(URL(string: layer.data["url"] ?? "")?.host ?? "Web widget").font(.system(size: 48, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        case .media:
            placeholder("film")
        }
    }

    private var textView: some View {
        let d = layer.data
        let px = CGFloat(Double(d["size"] ?? "") ?? 64)
        let boxed = d["background"] == "true"
        return Text(d["text"] ?? "")
            .font(WidgetFonts.font(face: d["face"] ?? "", size: px, weight: d["bold"] == "false" ? .regular : .bold))
            .foregroundStyle(Color(uiColor: OverlayRaster.color(argb: UInt32(d["color"] ?? "") ?? 0xFFFFFFFF)))
            .shadow(color: d["shadow"] == "false" ? .clear : .black.opacity(0.8), radius: px / 16, x: 0, y: px / 32)
            .padding(boxed ? px / 4 : 0)
            .background(boxed ? Color(uiColor: OverlayRaster.color(argb: UInt32(d["backgroundColor"] ?? "") ?? 0x8C000000)) : .clear,
                        in: RoundedRectangle(cornerRadius: px / 4))
            .fixedSize()
    }

    private func placeholder(_ icon: String) -> some View {
        ZStack {
            Rectangle().fill(.gray.opacity(0.35))
            Image(systemName: icon).font(.system(size: min(natural.width, natural.height) / 3)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func loadImage() async {
        guard let file, layer.type == .image || layer.type == .slideshow else { return }
        if let hit = Self.cache.object(forKey: file as NSString) { image = hit; return }
        // ponytail: decoded on the main actor, once per file name (then cached); fine for overlay-sized images.
        guard let url = OverlayStore.shared.local(file), let img = OverlayRaster.load(url) else { return }
        Self.cache.setObject(img, forKey: file as NSString)
        image = img
    }
}
