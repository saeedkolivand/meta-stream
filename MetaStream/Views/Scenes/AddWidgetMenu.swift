import SwiftUI

/// What the "+" menu can add. Each kind has one place that knows its defaults, so a new widget looks right immediately.
enum NewWidget: CaseIterable {
    case chat, alerts, events, text, clock, liveTime, drive, socials, image, qr, web

    var title: String {
        switch self {
        case .chat: "Chat"
        case .alerts: "Alerts"
        case .events: "Event list"
        case .text: "Text"
        case .clock: "Clock"
        case .liveTime: "Live time"
        case .drive: "Drive"
        case .socials: "Socials"
        case .image: "Image or GIF"
        case .qr: "QR code"
        case .web: "Web widget"
        }
    }

    var icon: String {
        switch self {
        case .chat: OverlayLayerType.chat.icon
        case .alerts: OverlayLayerType.alerts.icon
        case .events: OverlayLayerType.events.icon
        case .text: OverlayLayerType.text.icon
        case .clock: "clock.fill"
        case .liveTime: "record.circle"
        case .drive: "car.fill"
        case .socials: "person.2.fill"
        case .image: OverlayLayerType.image.icon
        case .qr: OverlayLayerType.qr.icon
        case .web: OverlayLayerType.browser.icon
        }
    }

    /// Image and web need input first (a picked file, a URL), so the editor builds those itself with the helpers below.
    func make() -> OverlayLayer? {
        switch self {
        case .chat: OverlayLayer.widget(.chat, name: "Chat", layout: .inset(6), data: ChatWidgetStyle().data)
        case .alerts: OverlayLayer.widget(.alerts, name: "Alerts", layout: .inset(1), data: AlertWidgetStyle().data)
        case .events: OverlayLayer.widget(.events, name: "Event list", layout: .inset(2), data: EventListStyle().data)
        case .text: textLayer()
        case .clock: preset("Clock", "🕒 {time}  {date}  {weather}", 0)
        case .liveTime: preset("Live time", "🔴 {uptime}", 2)
        case .drive: preset("Drive", "🚗 {speed}  🛣 {distance}", 6)
        case .socials: preset("Socials", "📷 IG @yourname\n🎵 TikTok @yourname\n✈️ TG @yourname", 8, rotate: true)
        case .qr: qrLayer()
        case .image, .web: nil
        }
    }

    private func textLayer() -> OverlayLayer {
        var s = TextWidgetStyle()
        s.text = "{time}"
        return OverlayLayer.widget(.text, name: "Text", layout: .inset(0), data: s.data)
    }

    private func preset(_ name: String, _ text: String, _ anchor: Int, rotate: Bool = false) -> OverlayLayer {
        var s = TextWidgetStyle()
        s.text = text; s.size = 32; s.background = true; s.rotate = rotate
        return OverlayLayer.widget(.text, name: name, layout: .inset(anchor), data: s.data)
    }

    private func qrLayer() -> OverlayLayer {
        var s = QRWidgetStyle()
        s.text = "https://example.com"
        return OverlayLayer.widget(.qr, name: "QR code", layout: .inset(8), data: s.data)
    }
}

extension OverlayLayerType {
    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .alerts: "bell.badge.fill"
        case .events: "list.bullet.rectangle.fill"
        case .text: "textformat"
        case .image: "photo.fill"
        case .media: "film.fill"
        case .browser: "globe"
        case .color: "square.fill"
        case .slideshow: "photo.on.rectangle.angled"
        case .qr: "qrcode"
        }
    }
}

extension OverlayLayer {
    /// Centred image, sized so it spans at most 35% of the short side (a 4000 px photo must not cover the frame).
    @MainActor static func pickedImage(file: String) -> OverlayLayer {
        var l = OverlayLayer.widget(.image, name: "Image", layout: .inset(4), data: ["file": file])
        if let n = OverlayStore.shared.naturalSize(l), n.width > 0 {
            l.layout?.scale = min(4, max(0.05, 0.35 * 1080 / n.width))
        }
        return l
    }

    static func web(url: String) -> OverlayLayer {
        .widget(.browser, name: URL(string: url)?.host ?? "Web widget", layout: .inset(4), data: ["url": url, "width": "800", "height": "600"])
    }
}

struct AddWidgetMenu: View {
    let pick: (NewWidget) -> Void

    var body: some View {
        Menu {
            ForEach(NewWidget.allCases, id: \.self) { kind in
                Button { pick(kind) } label: { Label(kind.title, systemImage: kind.icon) }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
        }
        .accessibilityLabel("Add widget")
    }
}
