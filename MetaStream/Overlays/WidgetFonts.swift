// Fonts for everything drawn on the stream. Latin stays in the chosen face (system SF by default); Persian/Arabic
// glyphs fall through a cascade list to Vazirmatn, so mixed "gg خیلی خوب" lines render correctly with no per-run work.
import CoreText
import SwiftUI
import UIKit

enum WidgetFonts {
    static let faces: [(id: String, label: String)] = [
        ("", "System"), ("Vazirmatn", "Vazirmatn"), ("Unbounded", "Unbounded"), ("TiltNeon", "Tilt Neon"),
        ("JetBrainsMono", "JetBrains Mono"), ("Manrope", "Manrope"),
    ]

    /// The variable fonts (donation alerts): face id -> PostScript name of the file's default instance.
    private static let variablePS = ["Unbounded": "Unbounded-Regular", "TiltNeon": "TiltNeon-Regular",
                                     "JetBrainsMono": "JetBrainsMono-Regular", "Manrope": "Manrope-ExtraLight"]

    /// UIFont.Weight onto the 100...900 `wght` axis.
    private static func wght(_ w: UIFont.Weight) -> Double {
        switch w.rawValue {
        case ..<(-0.7): 100
        case ..<(-0.5): 200
        case ..<(-0.3): 300
        case ..<0.1: 400
        case ..<0.27: 500
        case ..<0.35: 600
        case ..<0.5: 700
        case ..<0.6: 800
        default: 900
        }
    }

    private static func vazirName(_ w: UIFont.Weight) -> String {
        w.rawValue >= UIFont.Weight.bold.rawValue ? "Vazirmatn-Bold"
            : w.rawValue >= UIFont.Weight.semibold.rawValue ? "Vazirmatn-SemiBold" : "Vazirmatn-Regular"
    }

    /// face "" = system; "Vazirmatn" = Vazirmatn for every script; any other = that UIFont name/family, else system.
    /// weight .bold/.semibold/.regular maps to the matching Vazirmatn file. Always has a Vazirmatn cascade list.
    static func uiFont(face: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let vazir = UIFont(name: vazirName(weight), size: size)
        if face == "Vazirmatn", let vazir { return vazir }
        var base = UIFont.systemFont(ofSize: size, weight: weight)
        if let ps = variablePS[face] {
            let axis = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            let d = UIFontDescriptor(fontAttributes: [.name: ps, .size: size, axis: [0x7767_6874: wght(weight)]])
            let f = UIFont(descriptor: d, size: size)
            if f.fontName.hasPrefix(face) { base = f }   // else the file isn't in the bundle: system font
        } else if !face.isEmpty,
           let named = UIFont(name: face, size: size) ?? UIFont.fontNames(forFamilyName: face).first.flatMap({ UIFont(name: $0, size: size) }) {
            base = named
            if weight.rawValue >= UIFont.Weight.semibold.rawValue, let d = named.fontDescriptor.withSymbolicTraits(.traitBold) {
                base = UIFont(descriptor: d, size: size)
            }
        }
        guard vazir != nil else { return base }   // font file missing from the bundle: plain base font
        let cascade = UIFontDescriptor(fontAttributes: [.name: vazirName(weight), .size: size])
        return UIFont(descriptor: base.fontDescriptor.addingAttributes([.cascadeList: [cascade]]), size: size)
    }

    static func font(face: String, size: CGFloat, weight: UIFont.Weight) -> Font {
        Font(uiFont(face: face, size: size, weight: weight) as CTFont)
    }

    /// True when the first strong-direction character is Hebrew/Arabic-script (U+0590...U+08FF, U+FB1D...U+FEFC).
    static func isRTL(_ text: String) -> Bool {
        for u in text.unicodeScalars {
            let v = u.value
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFEFC).contains(v) { return true }
            if u.properties.isAlphabetic { return false }
        }
        return false
    }
}
