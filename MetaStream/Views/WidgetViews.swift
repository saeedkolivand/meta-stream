// SwiftUI views for the native stream widgets. The compositor rasterises them with ImageRenderer and the scene
// editor draws the very same views, so what you arrange is exactly what goes out. Point sizes are fixed (never
// Dynamic Type) and every view lays out at exactly its natural size.
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private func argbColor(_ argb: UInt32) -> Color { Color(uiColor: OverlayRaster.color(argb: argb)) }

/// SF Symbol + tint per event kind, shared by chat event rows and the event list.
func eventSymbol(_ k: ChatEvent.Kind) -> (name: String, color: Color) {
    switch k {
    case .message: return ("bubble.left.fill", .white)
    case .follow: return ("heart.fill", .pink)
    case .subscribe: return ("star.fill", .purple)
    case .tip: return ("dollarsign.circle.fill", .green)
    case .cheer: return ("sparkles", .orange)
    case .raid: return ("person.3.fill", .blue)
    }
}

/// Text that starts in a Persian/Arabic/Hebrew run flows right-to-left. Only the TEXT flips: cards, badges and
/// accents keep the same left-anchored layout as every other row, so mixed-language chat stays one tidy column.
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
    /// Chat burst (see ChatBurst): rows appear without the entry slide.
    var burst = false

    /// Events that survive the filters and the fade, oldest first, at most maxMessages.
    static func rows(_ events: [ChatEvent], _ style: ChatWidgetStyle, now: Date) -> [ChatEvent] {
        let fade = Double(style.fadeSeconds)
        let kept = events.filter { e in
            if fade > 0, now.timeIntervalSince(e.at) > fade { return false }
            if e.offensive { return false }   // on stream a slur can get the channel banned
            if e.kind != .message { return style.showEvents }
            if style.hideCommands, e.text.hasPrefix("!") { return false }
            return !(style.hideBots && BotList.isBot(e.user))
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

    /// Entry motion: 0 -> 1 over the first 0.32 s of a message's life (ease-out), so new rows rise and fade in.
    static func appear(_ e: ChatEvent, now: Date) -> Double {
        let t = min(1, max(0, now.timeIntervalSince(e.at) / 0.32))
        return 1 - pow(1 - t, 3)
    }

    var body: some View {
        let rows = Self.rows(events, style, now: now)
        VStack(alignment: .leading, spacing: size * 0.32) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, e in
                let a = burst ? 1 : Self.appear(e, now: now)
                row(e, animate: i >= rows.count - Self.animatedRows)
                    .opacity(Self.opacity(e, style, now: now) * a)
                    .offset(y: (1 - a) * size * 0.7)
            }
        }
        .padding(8)
        .frame(width: CGFloat(style.width), height: CGFloat(style.height), alignment: .bottomLeading)
        // Older rows dissolve into the video instead of being cut off by a hard edge.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18)],
                             startPoint: .top, endPoint: .bottom))
        .clipped()
    }

    /// Brand accents, not DisplayNames' UI tints: on video the real brand colours read instantly.
    static func brand(_ origin: String) -> Color {
        switch origin {
        case "twitch": return Color(red: 0.57, green: 0.27, blue: 1)        // #9146FF
        case "youtube": return Color(red: 1, green: 0, blue: 0.2)          // #FF0033
        default: return Color(red: 0.33, green: 0.99, blue: 0.09)          // Kick #53FC18
        }
    }

    /// One row on its own: the GPU chat widget rasterises each row once with this (ChatRows.swift).
    @ViewBuilder
    func row(_ e: ChatEvent, animate: Bool) -> some View {
        Group {
            if e.kind == .message { messageCard(e, animate: animate) } else { eventPill(e) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Flat, minimal card: who on top (platform chip, icon badges, name), what they said underneath. One solid fill, no
    /// gradients or borders; with the background off the text sits flush left on the video.
    /// Only the newest rows play animated emotes; older ones hold their first frame. ponytail: 3 rows keeps an idle
    /// chat with one old catJAM from redrawing the whole widget at 10 fps.
    static let animatedRows = 3

    private func messageCard(_ e: ChatEvent, animate: Bool) -> some View {
        let text = argbColor(style.textColor)
        let radius = size * 0.55
        return VStack(alignment: .leading, spacing: size * 0.12) {
            HStack(spacing: size * 0.22) {
                if style.platform { platformChip(e.origin) }
                if style.badges {
                    ForEach(Array(e.badges.prefix(3).enumerated()), id: \.offset) { _, b in
                        Image(systemName: DisplayNames.badgeStyle(b).symbol)
                            .font(font(.bold, 0.62)).foregroundColor(DisplayNames.badgeStyle(b).color)
                    }
                }
                Text(e.user)
                    .font(font(.bold)).kerning(0.2)
                    .foregroundColor(style.senderColors ? DisplayNames.nameColor(e) : text.opacity(0.75))
                    .lineLimit(1)
            }
            messageLine(e, text, animate: animate).lineSpacing(size * 0.08)
                .multilineTextAlignment(.leading).rowDirection(WidgetFonts.isRTL(e.text))
        }
        .padding(.leading, style.background ? size * 0.5 : 0)
        .padding(.trailing, style.background ? size * 0.55 : 0)
        .padding(.vertical, size * (style.background ? 0.36 : 0.15))
        .background {
            if style.background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(argbColor(style.backgroundColor))
            }
        }
        .overlay {
            if highlighted(e) { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(argbColor(style.highlightColor), lineWidth: 2) }
        }
        // No card behind the text: a tight dark shadow keeps the glyphs readable on bright video.
        .shadow(color: style.shadow ? .black.opacity(style.background ? 0.45 : 0.9) : .clear,
                radius: size * (style.background ? 0.35 : 0.12), x: 0, y: size * (style.background ? 0.12 : 0.04))
    }

    /// "K" / "T" / "Y" on the platform's colour, before the name.
    private func platformChip(_ origin: String) -> some View {
        let letter = origin == "twitch" ? "T" : origin == "youtube" ? "Y" : "K"
        return Text(letter).font(font(.heavy, 0.55))
            .foregroundColor(origin == "twitch" || origin == "youtube" ? .white : .black)
            .padding(.horizontal, size * 0.16).padding(.vertical, size * 0.06)
            .background(RoundedRectangle(cornerRadius: size * 0.15).fill(Self.brand(origin)))
    }

    /// Follows/subs/tips/raids/cheers: one flat pill in the event's colour, so they pop without shouting.
    private func eventPill(_ e: ChatEvent) -> some View {
        let sym = eventSymbol(e.kind)
        return HStack(spacing: size * 0.3) {
            Image(systemName: sym.name).font(font(.bold, 0.8))
            Text(DisplayNames.eventSummary(e)).font(font(.bold, 0.82)).lineLimit(2)
                .rowDirection(WidgetFonts.isRTL(DisplayNames.eventSummary(e)))
        }
        .foregroundColor(.white)
        .padding(.horizontal, size * 0.55).padding(.vertical, size * 0.3)
        .background(Capsule().fill(sym.color))
        .shadow(color: style.shadow ? .black.opacity(0.35) : .clear, radius: size * 0.3, x: 0, y: size * 0.1)
    }

    /// The message as one Text so bidi resolves mixed-script lines; emotes are inline images (Text concatenation).
    // ponytail: emotes stay 22 pt (Emotes resizes once, to 22 pt) whatever the font size. Upgrade: pass a height to
    // Emotes.image(for:) and cache one size per bucket.
    private func messageLine(_ e: ChatEvent, _ text: Color, animate: Bool) -> Text {
        Emotes.tokenize(e.text, byName: emotes.byName).reduce(Text("")) { partial, run in
            switch run {
            case .text(let s): return Text("\(partial)\(Text(s).font(font(style.bold ? .semibold : .regular)).foregroundColor(text))")
            case .emote(let url):
                if let img = emotes.image(for: url, at: animate ? now : nil) { return Text("\(partial)\(Text(img))") }
                return partial
            }
        }
    }

    static var samples: [ChatEvent] {   // computed so previews get fresh timestamps and never age out under "fade"
        [
            ChatEvent(kind: .message, user: "ninja_fox", text: "that clutch was insane", origin: "twitch", badges: ["subscriber"], color: "#FF7F50"),
            ChatEvent(kind: .message, user: "سارا", text: "سلام! استریم خیلی خوبه 🔥", origin: "kick", badges: ["vip"], color: "#4FC3F7"),
            ChatEvent(kind: .message, user: "ModMike", text: "welcome in, be nice in chat", origin: "youtube", badges: ["moderator"]),
            ChatEvent(kind: .subscribe, user: "BigDaddyBear", origin: "twitch"),
            ChatEvent(kind: .message, user: "Reza", text: "gg خیلی خوب بود", origin: "kick", badges: ["subscriber"], color: "#B39DDB"),
            ChatEvent(kind: .tip, user: "Lena", text: "keep it up!", amountCents: 500, origin: "youtube"),
        ].map { e in var e = e; e.at = Date().addingTimeInterval(-3); return e }   // past the entry motion, so previews show them settled
    }
}

// MARK: alerts

/// "Island" alert: a near-black capsule that drops in as a dot, opens, shows the event and closes again. All motion
/// comes from `pose` (see AlertIsland), so a frame is a pure function of its inputs; the default pose is the settled card.
struct AlertBannerView: View {
    let event: ChatEvent
    let style: AlertWidgetStyle
    var pose = AlertPose.settled

    private var size: CGFloat { CGFloat(style.fontSize) }
    private var big: Bool { AlertIsland.isBig(event) }
    private var height: CGFloat { AlertIsland.height(event) }
    private var fullWidth: CGFloat { big ? 800 : 740 }
    private func font(_ k: CGFloat, _ w: UIFont.Weight) -> Font { WidgetFonts.font(face: style.face, size: size * k, weight: w) }

    var body: some View {
        let tint = argbColor(AlertIsland.color(event.kind, accent: style.accentColor))
        let open = max(0, pose.open)
        ZStack {
            Capsule().fill(Color(red: 13 / 255, green: 13 / 255, blue: 16 / 255))
            content(tint)
                .frame(width: fullWidth, height: height)
                .opacity(pose.contentAlpha).offset(y: pose.contentRise)
            Capsule().fill(tint).opacity(pose.flash)   // big-tier flash: colour over the whole capsule, fading out
        }
        .frame(width: height + (fullWidth - height) * open, height: height)
        .clipShape(Capsule())
        .offset(y: pose.lift * height).opacity(pose.alpha)
        .padding(.top, 56)   // room above the rest position for the dot to drop in
        .frame(width: 900, height: 240, alignment: .top)
    }

    /// Left-anchored in LTR and RTL alike; only the name/message text runs flow right-to-left.
    private func content(_ tint: Color) -> some View {
        let d: CGFloat = big ? 120 : 84
        let text = argbColor(style.textColor)
        return HStack(spacing: 24) {
            Image(systemName: eventSymbol(event.kind).name)
                .font(.system(size: d * 0.46, weight: .bold))
                .foregroundColor(event.kind == .follow ? Color(white: 17.0 / 255) : .white)   // follow's colour is light
                .frame(width: d, height: d).background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(AlertIsland.label(event)).font(font(0.45, .semibold)).kerning(size * 0.45 * 0.16)
                    .foregroundColor(.white.opacity(0.74)).lineLimit(1)
                Text(event.user).font(font(1, .bold)).foregroundColor(text)
                    .lineLimit(1).minimumScaleFactor(0.5).rowDirection(WidgetFonts.isRTL(event.user))
                if !event.text.isEmpty {
                    Text(event.text).font(font(0.55, .regular)).foregroundColor(.white.opacity(0.74))
                        .lineLimit(1).truncationMode(.tail).rowDirection(WidgetFonts.isRTL(event.text))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let a = AlertIsland.amountParts(event, progress: pose.progress) {
                // Number at the amount size, unit at half of it; capped at 40% of the shared width and shrinking past
                // that, so the name column never collapses.
                let k: CGFloat = big ? 1.8 : 1.3
                (Text(a.number).font(font(k, .bold)).monospacedDigit() + Text(a.unit.isEmpty ? "" : " " + a.unit).font(font(k / 2, .bold)))
                    .foregroundColor(tint).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: AlertIsland.amountMax(big: big), alignment: .trailing)
            }
        }
        .padding(.leading, (height - d) / 2).padding(.trailing, 44)
    }

    static var sample: ChatEvent { ChatEvent(kind: .raid, user: "ninja_fox", text: "", count: 120, origin: "twitch") }
}

// MARK: event list

struct EventListView: View {
    let events: [ChatEvent]
    let style: EventListStyle

    /// Newest first, only the kinds the style shows.
    static func rows(_ events: [ChatEvent], _ style: EventListStyle) -> [ChatEvent] {
        Array(events.filter { $0.kind != .message && style.shows($0.kind) && !$0.offensive }.suffix(Int(style.maxEvents)).reversed())
    }

    /// One event on its own (the GPU event list rasterises each once, see EventRows.swift).
    func row(_ e: ChatEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: eventSymbol(e.kind).name).foregroundColor(eventSymbol(e.kind).color)
            Text(DisplayNames.eventSummary(e)).foregroundColor(argbColor(style.textColor)).lineLimit(2).multilineTextAlignment(.leading)
                .rowDirection(WidgetFonts.isRTL(DisplayNames.eventSummary(e)))
        }
        .font(WidgetFonts.font(face: style.face, size: CGFloat(style.fontSize), weight: .semibold))
        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background { if style.background { RoundedRectangle(cornerRadius: 10).fill(argbColor(style.backgroundColor)) } }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.rows(events, style).enumerated()), id: \.offset) { _, e in row(e) }
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
