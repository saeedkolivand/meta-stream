// Settings of every in-app widget. Stored as strings in OverlayLayer.data so a layer stays one flat, Codable value:
// ARGB colors as decimal UInt32 strings (what OverlayRaster.color(argb:) reads), bools "true"/"false", lists comma-separated.
// Missing or unparsable keys fall back to the default, so old packs keep loading when a field is added.
import CoreGraphics
import CoreModel
import Foundation

private extension Dictionary where Key == String, Value == String {
    func int(_ k: String, _ d: Int) -> Int { Int(self[k] ?? "") ?? d }
    func num(_ k: String, _ d: CGFloat) -> CGFloat { Double(self[k] ?? "").map { CGFloat($0) } ?? d }
    func flag(_ k: String, _ d: Bool) -> Bool { self[k] == "true" ? true : self[k] == "false" ? false : d }
    func argb(_ k: String, _ d: UInt32) -> UInt32 { UInt32(self[k] ?? "") ?? d }
    func str(_ k: String, _ d: String) -> String { self[k] ?? d }
}

private func flagText(_ b: Bool) -> String { b ? "true" : "false" }

/// Which event kinds an alert or event list reacts to; chat messages never do.
private func eventShown(_ k: ChatEvent.Kind, follow: Bool, subscribe: Bool, raid: Bool, tip: Bool, cheer: Bool) -> Bool {
    switch k {
    case .message: return false
    case .follow: return follow
    case .subscribe: return subscribe
    case .raid: return raid
    case .tip: return tip
    case .cheer: return cheer
    }
}

public struct ChatWidgetStyle: Equatable, Sendable {
    public var width: CGFloat = 600
    public var height: CGFloat = 500
    public var fontSize: CGFloat = 22
    public var maxMessages = 8
    public var fadeSeconds = 0   // 0 = never
    public var background = false
    public var backgroundColor: UInt32 = 0xD910_1014   // flat near-black, 85%: reads on any video without looking like a box
    public var textColor: UInt32 = 0xFFFF_FFFF
    public var senderColors = true
    public var shadow = true
    public var bold = true
    public var badges = true
    public var platform = true
    public var hideCommands = true
    public var hideBots = true
    public var highlight = ""
    public var highlightColor: UInt32 = 0xFFFF_C83D
    public var showEvents = true
    public var face = ""

    public init() {}
    public init(_ d: [String: String]) {
        let o = ChatWidgetStyle()
        width = d.num("width", o.width); height = d.num("height", o.height); fontSize = d.num("fontSize", o.fontSize)
        maxMessages = d.int("maxMessages", o.maxMessages); fadeSeconds = d.int("fadeSeconds", o.fadeSeconds)
        background = d.flag("background", o.background); backgroundColor = d.argb("backgroundColor", o.backgroundColor)
        textColor = d.argb("textColor", o.textColor); senderColors = d.flag("senderColors", o.senderColors)
        shadow = d.flag("shadow", o.shadow); bold = d.flag("bold", o.bold); badges = d.flag("badges", o.badges)
        platform = d.flag("platform", o.platform); hideCommands = d.flag("hideCommands", o.hideCommands)
        hideBots = d.flag("hideBots", o.hideBots)
        highlight = d.str("highlight", o.highlight); highlightColor = d.argb("highlightColor", o.highlightColor)
        showEvents = d.flag("showEvents", o.showEvents); face = d.str("face", o.face)
    }

    public var natural: CGSize { CGSize(width: width, height: height) }

    public var data: [String: String] {
        ["width": "\(Double(width))", "height": "\(Double(height))", "fontSize": "\(Double(fontSize))",
         "maxMessages": "\(maxMessages)", "fadeSeconds": "\(fadeSeconds)", "background": flagText(background),
         "backgroundColor": "\(backgroundColor)", "textColor": "\(textColor)", "senderColors": flagText(senderColors),
         "shadow": flagText(shadow), "bold": flagText(bold), "badges": flagText(badges), "platform": flagText(platform),
         "hideCommands": flagText(hideCommands), "hideBots": flagText(hideBots),
         "highlight": highlight, "highlightColor": "\(highlightColor)", "showEvents": flagText(showEvents), "face": face]
    }
}

public struct AlertWidgetStyle: Equatable, Sendable {
    public var follow = true
    public var subscribe = true
    public var raid = true
    public var tip = true
    public var cheer = true
    public var holdSeconds = 5
    public var fontSize: CGFloat = 40
    public var accentColor: UInt32 = 0xFF91_46FF
    public var textColor: UInt32 = 0xFFFF_FFFF
    public var face = ""
    public var design = "island"          // DonationAlertKind raw value; donations (tips, Bits, KICKs) only
    public var designAccent: UInt32 = 0   // 0 = the design's own colour
    public var designSecond: UInt32 = 0   // neon's second tube; 0 = the design's own
    public var designSpeed = "normal"     // "slow" | "normal" | "quick"

    public init() {}
    public init(_ d: [String: String]) {
        let o = AlertWidgetStyle()
        design = d.str("design", o.design); designAccent = d.argb("designAccent", o.designAccent)
        designSecond = d.argb("designSecond", o.designSecond); designSpeed = d.str("designSpeed", o.designSpeed)
        follow = d.flag("follow", o.follow); subscribe = d.flag("subscribe", o.subscribe); raid = d.flag("raid", o.raid)
        tip = d.flag("tip", o.tip); cheer = d.flag("cheer", o.cheer); holdSeconds = d.int("holdSeconds", o.holdSeconds)
        fontSize = d.num("fontSize", o.fontSize); accentColor = d.argb("accentColor", o.accentColor)
        textColor = d.argb("textColor", o.textColor); face = d.str("face", o.face)
    }

    public var natural: CGSize { CGSize(width: 900, height: 240) }

    public var donationKind: DonationAlertKind { DonationAlertKind(rawValue: design) ?? .island }

    public var donationStyle: DonationAlertStyle {
        DonationAlertStyle(accent: designAccent, second: designSecond,
                           speed: designSpeed == "slow" ? 0.75 : designSpeed == "quick" ? 1.33 : 1)
    }

    public func shows(_ kind: ChatEvent.Kind) -> Bool {
        eventShown(kind, follow: follow, subscribe: subscribe, raid: raid, tip: tip, cheer: cheer)
    }

    public var data: [String: String] {
        ["design": design, "designAccent": "\(designAccent)", "designSecond": "\(designSecond)", "designSpeed": designSpeed,
         "follow": flagText(follow), "subscribe": flagText(subscribe), "raid": flagText(raid), "tip": flagText(tip),
         "cheer": flagText(cheer), "holdSeconds": "\(holdSeconds)", "fontSize": "\(Double(fontSize))",
         "accentColor": "\(accentColor)", "textColor": "\(textColor)", "face": face]
    }
}

public struct EventListStyle: Equatable, Sendable {
    public var width: CGFloat = 520
    public var height: CGFloat = 420
    public var maxEvents = 5
    public var fontSize: CGFloat = 26
    public var follow = true
    public var subscribe = true
    public var raid = true
    public var tip = true
    public var cheer = true
    public var background = true
    public var backgroundColor: UInt32 = 0x7300_0000
    public var textColor: UInt32 = 0xFFFF_FFFF
    public var face = ""

    public init() {}
    public init(_ d: [String: String]) {
        let o = EventListStyle()
        width = d.num("width", o.width); height = d.num("height", o.height); maxEvents = d.int("maxEvents", o.maxEvents)
        fontSize = d.num("fontSize", o.fontSize); follow = d.flag("follow", o.follow)
        subscribe = d.flag("subscribe", o.subscribe); raid = d.flag("raid", o.raid); tip = d.flag("tip", o.tip)
        cheer = d.flag("cheer", o.cheer); background = d.flag("background", o.background)
        backgroundColor = d.argb("backgroundColor", o.backgroundColor); textColor = d.argb("textColor", o.textColor)
        face = d.str("face", o.face)
    }

    public var natural: CGSize { CGSize(width: width, height: height) }

    public func shows(_ kind: ChatEvent.Kind) -> Bool {
        eventShown(kind, follow: follow, subscribe: subscribe, raid: raid, tip: tip, cheer: cheer)
    }

    public var data: [String: String] {
        ["width": "\(Double(width))", "height": "\(Double(height))", "maxEvents": "\(maxEvents)",
         "fontSize": "\(Double(fontSize))", "follow": flagText(follow), "subscribe": flagText(subscribe),
         "raid": flagText(raid), "tip": flagText(tip), "cheer": flagText(cheer), "background": flagText(background),
         "backgroundColor": "\(backgroundColor)", "textColor": "\(textColor)", "face": face]
    }
}

public struct GoalWidgetStyle: Equatable, Sendable {
    public var width: CGFloat = 720
    public var height: CGFloat = 120
    public var fontSize: CGFloat = 28
    public var barColor: UInt32 = 0xFF53_FC18
    public var trackColor: UInt32 = 0xFF26_262B
    public var textColor: UInt32 = 0xFFFF_FFFF
    public var backgroundColor: UInt32 = 0xD910_1014
    public var background = true
    public var showPercent = true
    public var showOther = false
    public var face = ""
    public var design = "bar"   // "bar" | "liquid" | "road" | "segments" | "hairline" | "island" | "miniring" | "dots" | "spark"

    public init() {}
    public init(_ d: [String: String]) {
        let o = GoalWidgetStyle()
        design = d.str("design", o.design)
        width = d.num("width", o.width); height = d.num("height", o.height); fontSize = d.num("fontSize", o.fontSize)
        barColor = d.argb("barColor", o.barColor); trackColor = d.argb("trackColor", o.trackColor)
        textColor = d.argb("textColor", o.textColor); backgroundColor = d.argb("backgroundColor", o.backgroundColor)
        background = d.flag("background", o.background); showPercent = d.flag("showPercent", o.showPercent)
        showOther = d.flag("showOther", o.showOther); face = d.str("face", o.face)
    }

    /// The bar follows the box sliders; the other designs are drawn at a fixed size.
    public var natural: CGSize {
        switch design {
        case "liquid": CGSize(width: 630, height: 114)   // board size x GoalDesignView.scale
        case "road": CGSize(width: 750, height: 111)
        case "segments": CGSize(width: 720, height: 60)
        // Variable-width designs: a generous box (~40-character title) the content hugs one side of.
        case "hairline": CGSize(width: 720, height: 130)
        case "island": CGSize(width: 800, height: 90)
        case "miniring": CGSize(width: 760, height: 150)
        case "dots": CGSize(width: 880, height: 96)
        case "spark": CGSize(width: 760, height: 120)
        default: CGSize(width: width, height: height)
        }
    }

    public var data: [String: String] {
        ["design": design, "width": "\(Double(width))", "height": "\(Double(height))", "fontSize": "\(Double(fontSize))",
         "barColor": "\(barColor)", "trackColor": "\(trackColor)", "textColor": "\(textColor)",
         "backgroundColor": "\(backgroundColor)", "background": flagText(background), "showPercent": flagText(showPercent),
         "showOther": flagText(showOther), "face": face]
    }
}

public struct QRWidgetStyle: Equatable, Sendable {
    public var text = ""
    public var caption = ""
    public var foreground: UInt32 = 0xFF00_0000
    public var background: UInt32 = 0xFFFF_FFFF
    public var face = ""

    public init() {}
    public init(_ d: [String: String]) {
        let o = QRWidgetStyle()
        text = d.str("text", o.text); caption = d.str("caption", o.caption); foreground = d.argb("foreground", o.foreground)
        background = d.argb("background", o.background); face = d.str("face", o.face)
    }

    public var natural: CGSize { CGSize(width: 400, height: caption.isEmpty ? 400 : 470) }

    public var data: [String: String] {
        ["text": text, "caption": caption, "foreground": "\(foreground)", "background": "\(background)", "face": face]
    }
}

/// In-app text. OBS text layers use the same keys (text/size/bold/color/face), so the two share a decoder.
public struct TextWidgetStyle: Equatable, Sendable {
    public var text = ""
    public var size: CGFloat = 64   // font px at a 1080 px short side
    public var bold = true
    public var color: UInt32 = 0xFFFF_FFFF
    public var face = ""
    public var shadow = true
    public var background = false
    public var backgroundColor: UInt32 = 0x3310_1014   // 20% near-black
    public var rotate = false        // show one line of `text` at a time (socials)
    public var rotateSeconds = 5

    public init() {}
    public init(_ d: [String: String]) {
        let o = TextWidgetStyle()
        text = d.str("text", o.text); size = d.num("size", o.size); bold = d.flag("bold", o.bold)
        color = d.argb("color", o.color); face = d.str("face", o.face); shadow = d.flag("shadow", o.shadow)
        background = d.flag("background", o.background); backgroundColor = d.argb("backgroundColor", o.backgroundColor)
        rotate = d.flag("rotate", o.rotate)
        rotateSeconds = Int(d.num("rotateSeconds", CGFloat(o.rotateSeconds)))   // the slider may store "5.0"
    }

    public var data: [String: String] {
        ["rotate": flagText(rotate), "rotateSeconds": "\(rotateSeconds)",
         "text": text, "size": "\(Double(size))", "bold": flagText(bold), "color": "\(color)", "face": face,
         "shadow": flagText(shadow), "background": flagText(background), "backgroundColor": "\(backgroundColor)"]
    }
}
