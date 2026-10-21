// Settings of the Now playing (Spotify) widget. Same string-dictionary contract as the other styles in WidgetStyles.swift
// (ARGB colors as decimal UInt32 strings); parsed by hand because that file's dictionary helpers are file-private.
import CoreGraphics
import Foundation

enum NowPlayingDesign: String, CaseIterable, Sendable {
    case slab, island, disc, ticker, text, twoLine, cover, popup

    var title: String {
        switch self {
        case .slab: "Slab"
        case .island: "Island"
        case .disc: "Disc"
        case .ticker: "Ticker"
        case .text: "Text"
        case .twoLine: "Two lines"
        case .cover: "Text with cover"
        case .popup: "Pop-up"
        }
    }

    /// Island, Disc and Ticker animate all the time (equaliser bars, spinning cover): they redraw on a steady tick.
    var isContinuous: Bool { self == .island || self == .disc || self == .ticker }

    /// Share of the widget width the progress bar spans, so the loop redraws only when its pixel width changes. 0 = no bar.
    var barShare: CGFloat {
        switch self {
        case .slab: 0.7
        case .twoLine: 1
        default: 0
        }
    }

    /// Slab shows "1:02 / 3:20" text, the one thing besides the bar that changes while a song plays.
    var showsTime: Bool { self == .slab }
}

struct NowPlayingWidgetStyle: Equatable, Sendable {
    var design: NowPlayingDesign = .slab
    var accentColor: UInt32 = 0xFF1D_B954   // Spotify green
    var face = ""
    var popupSeconds = 6   // Pop-up only: how long it stays after each song change

    init() {}
    init(_ d: [String: String]) {
        let o = NowPlayingWidgetStyle()
        design = d["design"].flatMap(NowPlayingDesign.init(rawValue:)) ?? o.design
        accentColor = d["accentColor"].flatMap { UInt32($0) } ?? o.accentColor
        face = d["face"] ?? o.face
        // The slider may store "6.0"; keep it in the editor's range.
        popupSeconds = min(30, max(2, d["popupSeconds"].flatMap { Double($0) }.map { Int($0.rounded()) } ?? o.popupSeconds))
    }

    /// Artboard size x 2 (the mockups are half of a 1920x1080 canvas). Text-box designs hug their text inside this area.
    var natural: CGSize {
        switch design {
        case .slab: CGSize(width: 840, height: 256)
        case .island: CGSize(width: 880, height: 152)   // 840 open + room for the spring's overshoot
        case .disc: CGSize(width: 860, height: 224)
        case .ticker: CGSize(width: 920, height: 96)
        case .text: CGSize(width: 920, height: 58)
        case .twoLine: CGSize(width: 520, height: 98)
        case .cover: CGSize(width: 920, height: 60)
        case .popup: CGSize(width: 1040, height: 58)
        }
    }

    var data: [String: String] {
        ["design": design.rawValue, "accentColor": "\(accentColor)", "face": face, "popupSeconds": "\(popupSeconds)"]
    }
}
