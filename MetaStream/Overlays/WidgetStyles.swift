// Settings of every in-app widget. Stored as strings in OverlayLayer.data so a layer stays one flat, Codable value:
// ARGB colors as decimal UInt32 strings (what OverlayRaster.color(argb:) reads), bools "true"/"false", lists comma-separated.
// Missing or unparsable keys fall back to the default, so old packs keep loading when a field is added.
import CoreGraphics
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

struct ChatWidgetStyle: Equatable, Sendable {
    var width: CGFloat = 600
    var height: CGFloat = 500
    var fontSize: CGFloat = 22
    var maxMessages = 8
    var fadeSeconds = 0   // 0 = never
    var background = false
    var backgroundColor: UInt32 = 0xD910_1014   // flat near-black, 85%: reads on any video without looking like a box
    var textColor: UInt32 = 0xFFFF_FFFF
    var senderColors = true
    var shadow = true
    var bold = true
    var badges = true
    var platform = true
    var hideCommands = true
    var hideBots = true
    var highlight = ""
    var highlightColor: UInt32 = 0xFFFF_C83D
    var showEvents = true
    var face = ""

    init() {}
    init(_ d: [String: String]) {
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

    var natural: CGSize { CGSize(width: width, height: height) }

    var data: [String: String] {
        ["width": "\(Double(width))", "height": "\(Double(height))", "fontSize": "\(Double(fontSize))",
         "maxMessages": "\(maxMessages)", "fadeSeconds": "\(fadeSeconds)", "background": flagText(background),
         "backgroundColor": "\(backgroundColor)", "textColor": "\(textColor)", "senderColors": flagText(senderColors),
         "shadow": flagText(shadow), "bold": flagText(bold), "badges": flagText(badges), "platform": flagText(platform),
         "hideCommands": flagText(hideCommands), "hideBots": flagText(hideBots),
         "highlight": highlight, "highlightColor": "\(highlightColor)", "showEvents": flagText(showEvents), "face": face]
    }
}

struct AlertWidgetStyle: Equatable, Sendable {
    var follow = true
    var subscribe = true
    var raid = true
    var tip = true
    var cheer = true
    var holdSeconds = 5
    var fontSize: CGFloat = 40
    var accentColor: UInt32 = 0xFF91_46FF
    var textColor: UInt32 = 0xFFFF_FFFF
    var face = ""

    init() {}
    init(_ d: [String: String]) {
        let o = AlertWidgetStyle()
        follow = d.flag("follow", o.follow); subscribe = d.flag("subscribe", o.subscribe); raid = d.flag("raid", o.raid)
        tip = d.flag("tip", o.tip); cheer = d.flag("cheer", o.cheer); holdSeconds = d.int("holdSeconds", o.holdSeconds)
        fontSize = d.num("fontSize", o.fontSize); accentColor = d.argb("accentColor", o.accentColor)
        textColor = d.argb("textColor", o.textColor); face = d.str("face", o.face)
    }

    var natural: CGSize { CGSize(width: 900, height: 240) }

    func shows(_ kind: ChatEvent.Kind) -> Bool {
        eventShown(kind, follow: follow, subscribe: subscribe, raid: raid, tip: tip, cheer: cheer)
    }

    var data: [String: String] {
        ["follow": flagText(follow), "subscribe": flagText(subscribe), "raid": flagText(raid), "tip": flagText(tip),
         "cheer": flagText(cheer), "holdSeconds": "\(holdSeconds)", "fontSize": "\(Double(fontSize))",
         "accentColor": "\(accentColor)", "textColor": "\(textColor)", "face": face]
    }
}

struct EventListStyle: Equatable, Sendable {
    var width: CGFloat = 520
    var height: CGFloat = 420
    var maxEvents = 5
    var fontSize: CGFloat = 26
    var follow = true
    var subscribe = true
    var raid = true
    var tip = true
    var cheer = true
    var background = true
    var backgroundColor: UInt32 = 0x7300_0000
    var textColor: UInt32 = 0xFFFF_FFFF
    var face = ""

    init() {}
    init(_ d: [String: String]) {
        let o = EventListStyle()
        width = d.num("width", o.width); height = d.num("height", o.height); maxEvents = d.int("maxEvents", o.maxEvents)
        fontSize = d.num("fontSize", o.fontSize); follow = d.flag("follow", o.follow)
        subscribe = d.flag("subscribe", o.subscribe); raid = d.flag("raid", o.raid); tip = d.flag("tip", o.tip)
        cheer = d.flag("cheer", o.cheer); background = d.flag("background", o.background)
        backgroundColor = d.argb("backgroundColor", o.backgroundColor); textColor = d.argb("textColor", o.textColor)
        face = d.str("face", o.face)
    }

    var natural: CGSize { CGSize(width: width, height: height) }

    func shows(_ kind: ChatEvent.Kind) -> Bool {
        eventShown(kind, follow: follow, subscribe: subscribe, raid: raid, tip: tip, cheer: cheer)
    }

    var data: [String: String] {
        ["width": "\(Double(width))", "height": "\(Double(height))", "maxEvents": "\(maxEvents)",
         "fontSize": "\(Double(fontSize))", "follow": flagText(follow), "subscribe": flagText(subscribe),
         "raid": flagText(raid), "tip": flagText(tip), "cheer": flagText(cheer), "background": flagText(background),
         "backgroundColor": "\(backgroundColor)", "textColor": "\(textColor)", "face": face]
    }
}

struct QRWidgetStyle: Equatable, Sendable {
    var text = ""
    var caption = ""
    var foreground: UInt32 = 0xFF00_0000
    var background: UInt32 = 0xFFFF_FFFF
    var face = ""

    init() {}
    init(_ d: [String: String]) {
        let o = QRWidgetStyle()
        text = d.str("text", o.text); caption = d.str("caption", o.caption); foreground = d.argb("foreground", o.foreground)
        background = d.argb("background", o.background); face = d.str("face", o.face)
    }

    var natural: CGSize { CGSize(width: 400, height: caption.isEmpty ? 400 : 470) }

    var data: [String: String] {
        ["text": text, "caption": caption, "foreground": "\(foreground)", "background": "\(background)", "face": face]
    }
}

/// In-app text. OBS text layers use the same keys (text/size/bold/color/face), so the two share a decoder.
struct TextWidgetStyle: Equatable, Sendable {
    var text = ""
    var size: CGFloat = 64   // font px at a 1080 px short side
    var bold = true
    var color: UInt32 = 0xFFFF_FFFF
    var face = ""
    var shadow = true
    var background = false
    var backgroundColor: UInt32 = 0x3310_1014   // 20% near-black
    var rotate = false        // show one line of `text` at a time (socials)
    var rotateSeconds = 5

    init() {}
    init(_ d: [String: String]) {
        let o = TextWidgetStyle()
        text = d.str("text", o.text); size = d.num("size", o.size); bold = d.flag("bold", o.bold)
        color = d.argb("color", o.color); face = d.str("face", o.face); shadow = d.flag("shadow", o.shadow)
        background = d.flag("background", o.background); backgroundColor = d.argb("backgroundColor", o.backgroundColor)
        rotate = d.flag("rotate", o.rotate)
        rotateSeconds = Int(d.num("rotateSeconds", CGFloat(o.rotateSeconds)))   // the slider may store "5.0"
    }

    var data: [String: String] {
        ["rotate": flagText(rotate), "rotateSeconds": "\(rotateSeconds)",
         "text": text, "size": "\(Double(size))", "bold": flagText(bold), "color": "\(color)", "face": face,
         "shadow": flagText(shadow), "background": flagText(background), "backgroundColor": "\(backgroundColor)"]
    }
}
