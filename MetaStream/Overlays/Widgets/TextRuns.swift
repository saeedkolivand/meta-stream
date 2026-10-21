// Inline icons in text widgets: "{i:clock} {time}" draws the SF Symbol named in the token where it stands, sized to the text
// and centred on its cap height, in the text colour. This file parses a (resolved) text into runs and measures them; the
// GPU text widget (GPUTextWidget.swift) and the editor preview both go through it, so they agree on every size.
import UIKit

enum TextRun: Equatable, Sendable {
    case text(String)
    case icon(String)
}

/// Where each run of a text widget sits, in px, top-left origin, padding included.
struct TextPlan: Sendable {
    struct Item: Sendable {
        let run: TextRun
        let x: CGFloat       // left edge
        let width: CGFloat
        let midY: CGFloat    // vertical centre: of the line box for text, of the cap height for an icon
    }

    var items: [Item] = []
    var size = CGSize.zero   // natural size of the widget box, padding included
    var pad: CGFloat = 0
    var px: CGFloat = 0
}

enum TextRuns {
    private static func isNameChar(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "." || ch == "-" || ch == "_" }

    /// Splits `s` at its `{i:name}` tokens. A "{i:" that isn't a well-formed token stays plain text.
    static func parse(_ text: String) -> [TextRun] {
        var out: [TextRun] = []
        func add(_ part: Substring) {
            guard !part.isEmpty else { return }
            if case .text(let last)? = out.last { out[out.count - 1] = .text(last + part) } else { out.append(.text(String(part))) }
        }
        var rest = Substring(text)
        while let open = rest.range(of: "{i:") {
            add(rest[..<open.lowerBound])
            if let close = rest[open.upperBound...].firstIndex(of: "}"), close > open.upperBound,
               rest[open.upperBound..<close].allSatisfy(isNameChar) {
                out.append(.icon(String(rest[open.upperBound..<close])))
                rest = rest[rest.index(after: close)...]
            } else {
                add(rest[open])
                rest = rest[open.upperBound...]
            }
        }
        add(rest)
        return out
    }

    /// One run list per line.
    static func lines(_ text: String) -> [[TextRun]] { text.components(separatedBy: "\n").map(parse) }

    /// Runs the widget draws: text at `px` (bold or regular, `face`), icons at the same point size, lines left-aligned.
    /// `pad` is the backdrop's margin. Measured exactly as StingerCanvas draws (same font, same NSAttributedString size).
    static func plan(_ text: String, face: String, bold: Bool, px: CGFloat, pad: CGFloat) -> TextPlan {
        let font = WidgetFonts.uiFont(face: face, size: px, weight: bold ? .bold : .regular)
        let rowH = ceil(font.lineHeight)
        let iconMid = font.ascender - font.capHeight / 2
        let cfg = UIImage.SymbolConfiguration(pointSize: px, weight: .bold)
        var plan = TextPlan(pad: pad, px: px)
        var top = pad, widest: CGFloat = 0
        for line in lines(text) {
            var x = pad, height = rowH
            for run in line {
                switch run {
                case .text(let str):
                    let box = NSAttributedString(string: str, attributes: [.font: font]).size()
                    plan.items.append(.init(run: run, x: x, width: ceil(box.width), midY: top + ceil(box.height) / 2))
                    x += ceil(box.width)
                    height = max(height, ceil(box.height))
                case .icon(let name):
                    let wide = ceil(UIImage(systemName: name, withConfiguration: cfg)?.size.width ?? 0)
                    plan.items.append(.init(run: run, x: x, width: wide, midY: top + iconMid))
                    x += wide
                }
            }
            widest = max(widest, x - pad)
            top += height
        }
        plan.size = CGSize(width: widest + 2 + 2 * pad, height: top + pad)
        return plan
    }

    /// The SF Symbol each emoji the old presets and saved scenes used stands for.
    private static let emojiIcons: [(emoji: String, symbol: String)] = [
        ("🕒", "clock"), ("🔴", "record.circle"), ("👁", "eye"), ("🚗", "car.fill"), ("🛣", "road.lanes"), ("📷", "camera"),
        ("🎵", "music.note"), ("✈", "paperplane"), ("🔥", "flame"), ("⏱", "stopwatch"), ("📍", "mappin"), ("❤", "heart.fill"),
        ("💸", "banknote"), ("🎯", "target")
    ]

    /// `s` with those emoji swapped for icon tokens (a variation selector after one is dropped with it).
    static func iconized(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\u{FE0F}", with: "")
        for (emoji, symbol) in emojiIcons { out = out.replacingOccurrences(of: emoji, with: "{i:\(symbol)}") }
        return out
    }

    /// `pack` with the emoji in its in-app text layers swapped for icon tokens; nil when nothing changed.
    static func iconized(_ pack: OverlayPack) -> OverlayPack? {
        var moved = pack, changed = false
        for sc in moved.scenes.indices {
            for li in moved.scenes[sc].layers.indices {
                let layer = moved.scenes[sc].layers[li]
                guard layer.type == .text, layer.layout != nil else { continue }
                let text = iconized(layer.data["text"] ?? "")
                if text != layer.data["text"] {
                    moved.scenes[sc].layers[li].data["text"] = text
                    changed = true
                }
            }
        }
        return changed ? moved : nil
    }

    /// Icons the editor offers, as SF Symbol names.
    static let palette = [
        "clock", "record.circle", "eye", "car.fill", "road.lanes", "camera", "music.note", "paperplane", "flame", "stopwatch", "mappin",
        "heart.fill", "banknote", "target", "star.fill", "bolt.fill", "bell.fill", "gift.fill", "trophy.fill", "mic.fill",
        "gamecontroller.fill", "location.fill", "cloud.sun.fill", "link"
    ]
}

#if DEBUG
extension TextRuns {
    static func demo() {
        assert(parse("") == [], "empty")
        assert(parse("plain") == [.text("plain")], "no token")
        assert(parse("{i:clock} {time}") == [.icon("clock"), .text(" {time}")], "leading icon")
        assert(parse("a{i:car.fill}b{i:eye}") == [.text("a"), .icon("car.fill"), .text("b"), .icon("eye")], "mixed")
        assert(parse("{i:}{i:a b}{i:x") == [.text("{i:}{i:a b}{i:x")], "malformed tokens stay text")
        assert(parse("{i:{i:eye}") == [.text("{i:"), .icon("eye")], "nested open brace")
        assert(lines("a\n{i:eye}").count == 2, "one run list per line")
        assert(iconized("🕒 {time}  ❤️ 🔴") == "{i:clock} {time}  {i:heart.fill} {i:record.circle}", "emoji migration")
        assert(iconized("{i:clock}") == "{i:clock}", "migration is idempotent")
        applog("overlay", "TextRuns.demo() passed")
    }
}
#endif
