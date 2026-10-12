// SwiftUI views for the native stream widgets. The compositor rasterises them with ImageRenderer and the scene
// editor draws the very same views, so what you arrange is exactly what goes out. Point sizes are fixed (never
// Dynamic Type) and every view lays out at exactly its natural size.
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private func argbColor(_ argb: UInt32) -> Color { Color(uiColor: OverlayRaster.color(argb: argb)) }

/// SF Symbol + tint per event kind, shared by chat event rows and the event list.
private func eventSymbol(_ k: ChatEvent.Kind) -> (name: String, color: Color) {
    switch k {
    case .message: return ("bubble.left.fill", .white)
    case .follow: return ("heart.fill", .pink)
    case .subscribe: return ("star.fill", .purple)
    case .tip: return ("dollarsign.circle.fill", .green)
    case .cheer: return ("sparkles", .orange)
    case .raid: return ("person.3.fill", .blue)
    }
}

/// Rows flip to right-to-left when their text starts in a Persian/Arabic/Hebrew run: dot, badges and name then
/// sit on the right and the text flows RTL. Applied inside, so the outer frame alignment stays screen-relative.
private extension View {
    func rowDirection(_ rtl: Bool) -> some View {
        environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}

// MARK: chat

struct StreamChatView: View {
    let events: [ChatEvent]
    let style: ChatWidgetStyle
    @ObservedObject var emotes: Emotes
    var channel: String = ""
    var now: Date = Date()

    /// Events that survive the filters and the fade, oldest first, at most maxMessages.
    static func rows(_ events: [ChatEvent], _ style: ChatWidgetStyle, now: Date) -> [ChatEvent] {
        let bots = Set(style.botNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let fade = Double(style.fadeSeconds)
        let kept = events.filter { e in
            if fade > 0, now.timeIntervalSince(e.at) > fade { return false }
            if e.kind != .message { return style.showEvents }
            if style.hideCommands, e.text.hasPrefix("!") { return false }
            return !(style.hideBots && bots.contains(e.user.lowercased()))
        }
        return Array(kept.suffix(Int(style.maxMessages)))
    }

    /// 1 until the last 2 s before the fade deadline, then ramps to 0.
    static func opacity(_ e: ChatEvent, _ style: ChatWidgetStyle, now: Date) -> Double {
        let fade = Double(style.fadeSeconds)
        guard fade > 0 else { return 1 }
        return max(0, min(1, (fade - now.timeIntervalSince(e.at)) / 2))
    }

    private var size: CGFloat { CGFloat(style.fontSize) }
    private func font(_ w: UIFont.Weight, _ k: CGFloat = 1) -> Font { WidgetFonts.font(face: style.face, size: size * k, weight: w) }

    private func highlighted(_ e: ChatEvent) -> Bool {
        if e.kind != .message { return true }
        let t = e.text.lowercased()
        let words = style.highlight.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let me = channel.trimmingCharacters(in: .whitespaces).lowercased()
        return words.contains { t.contains($0) } || (!me.isEmpty && t.contains(me))
    }

    var body: some View {
        let rows = Self.rows(events, style, now: now)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, e in
                row(e).opacity(Self.opacity(e, style, now: now))
            }
        }
        .padding(8)
        .frame(width: CGFloat(style.width), height: CGFloat(style.height), alignment: .bottomLeading)
        .clipped()
    }

    private func row(_ e: ChatEvent) -> some View {
        let isMessage = e.kind == .message
        let rtl = WidgetFonts.isRTL(isMessage ? e.text : DisplayNames.eventSummary(e))
        let text = argbColor(style.textColor)
        return HStack(alignment: .top, spacing: 6) {
            if style.platform {
                Circle().fill(DisplayNames.originColor(e.origin)).frame(width: size * 0.4, height: size * 0.4)
                    .padding(.top, size * 0.4)
            }
            if isMessage {
                if style.badges { ForEach(Array(e.badges.prefix(3).enumerated()), id: \.offset) { _, b in chip(b) } }
                messageLine(e, text)
            } else {
                Image(systemName: eventSymbol(e.kind).name).font(font(.bold)).foregroundColor(eventSymbol(e.kind).color)
                Text(DisplayNames.eventSummary(e)).font(font(.bold)).foregroundColor(text).multilineTextAlignment(.leading)
            }
        }
        .shadow(color: style.shadow ? Color.black.opacity(0.85) : Color.clear, radius: 2, x: 0, y: 1)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background { if style.background { RoundedRectangle(cornerRadius: 10).fill(argbColor(style.backgroundColor)) } }
        .overlay { if highlighted(e) { RoundedRectangle(cornerRadius: 10).stroke(argbColor(style.highlightColor), lineWidth: 2) } }
        .rowDirection(rtl)
        .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
    }

    /// Name and message stay one Text so bidi resolves mixed-script lines; emotes are inline images (Text concatenation).
    // ponytail: emotes stay 22 pt (Emotes resizes once, to 22 pt) whatever the font size. Upgrade: pass a height to
    // Emotes.image(for:) and cache one size per bucket.
    private func messageLine(_ e: ChatEvent, _ text: Color) -> Text {
        let name = style.senderColors ? DisplayNames.nameColor(e) : text
        let head = Text(e.user + ": ").font(font(.bold)).foregroundColor(name)
        let body = Emotes.tokenize(e.text, byName: emotes.byName).reduce(Text("")) { partial, run in
            switch run {
            case .text(let s): return partial + Text(s).font(font(style.bold ? .semibold : .regular)).foregroundColor(text)
            case .emote(let url):
                if let img = emotes.image(for: url) { return partial + Text(img) }
                return partial + Text("")
            }
        }
        return head + body
    }

    private func chip(_ badge: String) -> some View {
        let s = DisplayNames.badgeStyle(badge)
        return HStack(spacing: 2) {
            Image(systemName: s.symbol)
            if !s.label.isEmpty { Text(s.label) }
        }
        .font(font(.heavy, 0.5)).foregroundColor(s.color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(s.color.opacity(0.22), in: Capsule())
        .padding(.top, size * 0.2)
    }

    static var samples: [ChatEvent] {   // computed so previews get fresh timestamps and never age out under "fade"
        [
            ChatEvent(kind: .message, user: "ninja_fox", text: "that clutch was insane", origin: "twitch", badges: ["subscriber"], color: "#FF7F50"),
            ChatEvent(kind: .message, user: "سارا", text: "سلام! استریم خیلی خوبه 🔥", origin: "kick", badges: ["vip"], color: "#4FC3F7"),
            ChatEvent(kind: .message, user: "ModMike", text: "welcome in, be nice in chat", origin: "youtube", badges: ["moderator"]),
            ChatEvent(kind: .subscribe, user: "BigDaddyBear", origin: "twitch"),
            ChatEvent(kind: .message, user: "Reza", text: "gg خیلی خوب بود", origin: "kick", badges: ["subscriber"], color: "#B39DDB"),
            ChatEvent(kind: .tip, user: "Lena", text: "keep it up!", amountCents: 500, origin: "youtube"),
        ]
    }
}

// MARK: alerts

struct AlertBannerView: View {
    let event: ChatEvent
    let style: AlertWidgetStyle

    private var size: CGFloat { CGFloat(style.fontSize) }

    private var label: String {
        switch event.kind {
        case .message: return ""
        case .follow: return "NEW FOLLOWER"
        case .subscribe: return "NEW SUBSCRIBER"
        case .tip: return String(format: "TIPPED $%.2f", Double(event.amountCents) / 100)
        case .cheer: return "CHEERED \(event.count) BITS"
        case .raid: return "RAID · \(event.count) VIEWERS"
        }
    }

    var body: some View {
        let accent = argbColor(style.accentColor), text = argbColor(style.textColor)
        let rtl = WidgetFonts.isRTL(event.user + event.text)
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color.black.opacity(0.78))
            RoundedRectangle(cornerRadius: 30).stroke(accent, lineWidth: 4)
            HStack(spacing: 28) {
                Image(systemName: eventSymbol(event.kind).name)
                    .font(.system(size: 56, weight: .bold)).foregroundColor(.white)
                    .frame(width: 118, height: 118).background(accent, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(WidgetFonts.font(face: style.face, size: size * 0.5, weight: .bold)).foregroundColor(accent)
                    Text(event.user).font(WidgetFonts.font(face: style.face, size: size, weight: .bold)).foregroundColor(text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !event.text.isEmpty {
                        Text(event.text).font(WidgetFonts.font(face: style.face, size: size * 0.55, weight: .regular))
                            .foregroundColor(text.opacity(0.85)).lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 36)
            .rowDirection(rtl)
        }
        .frame(width: 900, height: 240)
    }

    static var sample: ChatEvent { ChatEvent(kind: .follow, user: "ninja_fox", text: "", origin: "twitch") }
}

// MARK: event list

struct EventListView: View {
    let events: [ChatEvent]
    let style: EventListStyle

    /// Newest first, only the kinds the style shows.
    static func rows(_ events: [ChatEvent], _ style: EventListStyle) -> [ChatEvent] {
        Array(events.filter { $0.kind != .message && style.shows($0.kind) }.suffix(Int(style.maxEvents)).reversed())
    }

    var body: some View {
        let size = CGFloat(style.fontSize)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.rows(events, style).enumerated()), id: \.offset) { _, e in
                let rtl = WidgetFonts.isRTL(DisplayNames.eventSummary(e))
                HStack(spacing: 8) {
                    Image(systemName: eventSymbol(e.kind).name).foregroundColor(eventSymbol(e.kind).color)
                    Text(DisplayNames.eventSummary(e)).foregroundColor(argbColor(style.textColor)).lineLimit(2).multilineTextAlignment(.leading)
                }
                .font(WidgetFonts.font(face: style.face, size: size, weight: .semibold))
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background { if style.background { RoundedRectangle(cornerRadius: 10).fill(argbColor(style.backgroundColor)) } }
                .rowDirection(rtl)
                .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
            }
        }
        .padding(8)
        .frame(width: CGFloat(style.width), height: CGFloat(style.height), alignment: .topLeading)
        .clipped()
    }

    static var samples: [ChatEvent] {
        [
            ChatEvent(kind: .follow, user: "ninja_fox", origin: "twitch"),
            ChatEvent(kind: .subscribe, user: "سارا", origin: "kick"),
            ChatEvent(kind: .tip, user: "Lena", text: "keep it up!", amountCents: 500, origin: "youtube"),
            ChatEvent(kind: .raid, user: "BigDaddyBear", count: 42, origin: "twitch"),
            ChatEvent(kind: .cheer, user: "Reza", count: 100, origin: "twitch"),
        ]
    }
}

// MARK: QR

enum QRCode {
    /// `size` is in output px; the code is a square of `size.width` with the caption in the rest. Nearest-neighbour
    /// scaling keeps module edges crisp for scanners (CoreImage's own output is 1 px per module).
    @MainActor static func image(_ text: String, style: QRWidgetStyle, size: CGSize) -> UIImage? {
        guard !text.isEmpty, size.width >= 8, size.height >= 8 else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let raw = f.outputImage else { return nil }
        let colored = raw.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(color: OverlayRaster.color(argb: style.foreground)),
            "inputColor1": CIColor(color: OverlayRaster.color(argb: style.background)),
        ])
        let side = size.width, pad = side * 0.06, avail = side - 2 * pad, modules = raw.extent.width
        let k = max(1, floor(avail / modules))
        let big = colored.transformed(by: CGAffineTransform(scaleX: k, y: k))
        guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
        let drawSide = k * modules <= avail ? k * modules : avail
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            OverlayRaster.fill(argb: style.background, in: CGRect(origin: .zero, size: size))
            ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage: cg).draw(in: CGRect(x: (side - drawSide) / 2, y: (side - drawSide) / 2, width: drawSide, height: drawSide))
            guard !style.caption.isEmpty, size.height > side else { return }
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WidgetFonts.uiFont(face: style.face, size: min((size.height - side) * 0.45, side * 0.085), weight: .semibold),
                .foregroundColor: OverlayRaster.color(argb: style.foreground), .paragraphStyle: para,
            ]
            let area = CGRect(x: pad, y: side, width: size.width - 2 * pad, height: size.height - side)
            let h = min(area.height, (style.caption as NSString).boundingRect(with: area.size, options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height)
            (style.caption as NSString).draw(with: CGRect(x: area.minX, y: area.minY + (area.height - h) / 2, width: area.width, height: h),
                                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
        }
    }
}
