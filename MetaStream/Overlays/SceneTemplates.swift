// Ready-made Starting / BRB / Ending scenes (the Mono and Ticker looks), built from ordinary widget layers so every
// piece stays editable afterwards. Positions are px of a 1920x1080 frame; widgets scale by the short side.
import CoreGraphics

enum SceneTemplate: String, CaseIterable {
    case mono = "Mono", ticker = "Ticker"

    /// `channel` is the Kick name (empty = no channel line or QR code). The colours come from `theme`; they are baked into
    /// the layers, so changing the theme later doesn't touch scenes already made.
    @MainActor func scenes(channel: String, theme: ColorTheme = .current) -> [OverlayScene] {
        let url = channel.isEmpty ? "" : "kick.com/\(channel.lowercased())"
        switch self {
        case .mono: return Self.mono(url, theme)
        case .ticker: return Self.ticker(url, theme)
        }
    }

    // MARK: Mono: dark, type only, chat on the right

    @MainActor private static func mono(_ url: String, _ theme: ColorTheme) -> [OverlayScene] {
        let (accent, white, grey) = (theme.accent, theme.text, theme.muted)
        func frame(_ label: String, _ headline: String, _ footer: String) -> [OverlayLayer] {
            [fill(theme.bg, 4000, 4000, at(4, 0, 0)),
             text(label, 28, accent, at(0, 96, 96)),
             text(headline, headline.contains("{countdown}") ? 300 : 200, white, at(3, 96, -70)),
             text(footer, 28, grey, at(6, 96, -96))]
        }
        let chatBox = chat(width: 560, height: 760, card: theme.surface, at(8, -96, -96))
        let place = url.isEmpty ? "{weather}" : "{weather}  ·  \(url)"
        var ending = frame("THAT'S A WRAP", "Thanks for\nwatching", "New follower {follower}  ·  New sub {sub}  ·  Live for {uptime}")
        ending.append(text("Next stream: day · time", 28, grey, at(2, -96, 96)))
        if !url.isEmpty { ending.append(qr(url, at(8, -96, -96))) }
        return [
            OverlayScene(name: "Starting soon", layers: frame("STARTING SOON", "{countdown}", place)
                + [text("IRL from {city}", 64, white, at(3, 96, 200)), chatBox], role: "starting"),
            OverlayScene(name: "BRB", layers: frame("STILL LIVE", "Be right\nback", "Live {uptime}  ·  {city}  ·  {weather}")
                + [text("Signal's weak here. Hang tight, I'll be back in a moment.", 36, grey, at(3, 96, 230)), chatBox], role: "brb"),
            OverlayScene(name: "Ending", layers: ending, role: "ending"),
        ]
    }

    // MARK: Ticker: a backdrop (swap in your photo) with a bottom bar

    @MainActor private static func ticker(_ url: String, _ theme: ColorTheme) -> [OverlayScene] {
        let (accent, white, grey, ink) = (theme.accent, theme.text, theme.muted, theme.bg)
        let bar: CGFloat = 180
        func frame(_ label: String, _ title: String, _ sub: String, _ right: String) -> [OverlayLayer] {
            let tag = text(label, 40, theme.onAccent, .inset(6))
            let block = (OverlayStore.shared.naturalSize(tag)?.width ?? 400) + 112
            // Anchor 6/8 puts a widget's bottom on the frame's bottom; dy lifts its centre to `fromBottom`.
            func mid(_ l: OverlayLayer, _ x: CGFloat, _ fromBottom: CGFloat, _ anchor: Int = 6) -> OverlayLayer {
                var l = l
                let h = OverlayStore.shared.naturalSize(l)?.height ?? 0
                l.layout = at(anchor, x, h / 2 - fromBottom)
                return l
            }
            var layers = [fill(theme.backdrop, 4000, 4000, at(4, 0, 0)),
                          fill(ink, 4000, bar, at(7, 0, 0)),
                          fill(accent, block, bar, at(6, 0, 0)),
                          mid(tag, 56, bar / 2),
                          mid(text(title, 52, white, .inset(6)), block + 56, 115),
                          mid(text(sub, 26, grey, .inset(6)), block + 56, 50)]
            if !right.isEmpty { layers.append(mid(text(right, right.contains("{countdown}") ? 104 : 64, white, .inset(8)), -64, bar / 2, 8)) }
            return layers
        }
        let chatBox = chat(width: 520, height: 600, card: ink, at(8, -64, -(bar + 48)))
        let channel = url.isEmpty ? "" : "  ·  \(url)"
        var ending = frame("THANKS FOR WATCHING", "Welcome {follower}  ·  Thanks {sub}", "Live for {uptime}\(channel)", "")
        if !url.isEmpty { ending.append(qr(url, at(8, -64, -(bar + 48)))) }
        return [
            OverlayScene(name: "Starting soon", layers: frame("STARTING SOON", "IRL from {city}", "{weather}\(channel)", "{countdown}") + [chatBox],
                         role: "starting"),
            OverlayScene(name: "BRB", layers: frame("BE RIGHT BACK", "Signal's weak. Back in a moment.", "{city}  ·  {weather}", "{uptime}") + [chatBox],
                         role: "brb"),
            OverlayScene(name: "Ending", layers: ending, role: "ending"),
        ]
    }

    // MARK: layer helpers

    private static func at(_ anchor: Int, _ x: CGFloat, _ y: CGFloat) -> WidgetLayout {
        WidgetLayout(anchor: anchor, dx: x / 1920, dy: y / 1080)
    }

    private static func fill(_ argb: UInt32, _ w: CGFloat, _ h: CGFloat, _ layout: WidgetLayout) -> OverlayLayer {
        .widget(.color, name: "Color", layout: layout, data: ["color": "\(argb)", "width": "\(Double(w))", "height": "\(Double(h))"])
    }

    /// Flat text: no shadow, no backdrop (the templates are solid colour, nothing to lift the glyphs off).
    private static func text(_ s: String, _ size: CGFloat, _ color: UInt32, _ layout: WidgetLayout) -> OverlayLayer {
        var t = TextWidgetStyle()
        t.text = s; t.size = size; t.color = color; t.shadow = false
        return .widget(.text, name: s.replacingOccurrences(of: "\n", with: " "), layout: layout, data: t.data)
    }

    private static func chat(width: CGFloat, height: CGFloat, card: UInt32, _ layout: WidgetLayout) -> OverlayLayer {
        var c = ChatWidgetStyle()
        c.width = width; c.height = height; c.fontSize = 26; c.background = true; c.backgroundColor = card; c.shadow = false
        return .widget(.chat, name: "Chat", layout: layout, data: c.data)
    }

    private static func qr(_ url: String, _ layout: WidgetLayout) -> OverlayLayer {
        var q = QRWidgetStyle()
        q.text = "https://\(url)"; q.caption = url
        return .widget(.qr, name: "QR code", layout: layout, data: q.data)
    }
}
