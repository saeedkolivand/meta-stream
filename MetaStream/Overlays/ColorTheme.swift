import SwiftUI

/// Named colour sets shared by the scene templates and the Instagram story card. One setting (`colorTheme`).
/// Values are 0xFFRRGGBB.
enum ColorTheme: String, CaseIterable, Identifiable {
    case kick, red, saffron, turquoise, purple, paper

    var id: String { rawValue }

    /// The chosen theme (Settings > Theme & story); Kick if unset.
    static var current: ColorTheme {
        UserDefaults.standard.string(forKey: "colorTheme").flatMap(ColorTheme.init(rawValue:)) ?? .kick
    }

    var name: String {
        switch self {
        case .kick: "Kick"
        case .red: "Live red"
        case .saffron: "Saffron"
        case .turquoise: "Turquoise"
        case .purple: "Twitch purple"
        case .paper: "Paper"
        }
    }

    var faName: String {
        switch self {
        case .kick: "سبز کیک"
        case .red: "قرمز لایو"
        case .saffron: "زعفرانی"
        case .turquoise: "فیروزه‌ای"
        case .purple: "بنفش"
        case .paper: "کاغذی"
        }
    }

    /// bg, surface, text, muted, accent, onAccent.
    private var palette: [UInt32] {
        switch self {
        case .kick: [0xFF0B_0B0C, 0xFF18_181A, 0xFFF2_F1EC, 0xFFA3_A3A0, 0xFF53_FC18, 0xFF0B_0B0C]
        case .red: [0xFF00_0000, 0xFF27_272A, 0xFFFF_FFFF, 0xFFA1_A1AA, 0xFFE1_1D48, 0xFFFF_FFFF]
        case .saffron: [0xFF1C_1410, 0xFF2E_231C, 0xFFFF_F8EE, 0xFFCD_BBA7, 0xFFF5_9E0B, 0xFF1C_1410]
        case .turquoise: [0xFF07_1A1F, 0xFF0F_2E36, 0xFFEF_FFFE, 0xFF9C_C7CC, 0xFF2D_D4BF, 0xFF07_1A1F]
        case .purple: [0xFF0E_0B16, 0xFF1F_1A2E, 0xFFFF_FFFF, 0xFFB8_AFCF, 0xFF91_46FF, 0xFFFF_FFFF]
        case .paper: [0xFFF7_F5F0, 0xFFE7_E3DA, 0xFF14_1413, 0xFF57_534E, 0xFFDC_2626, 0xFFFF_FFFF]
        }
    }

    var bg: UInt32 { palette[0] }
    var surface: UInt32 { palette[1] }
    var text: UInt32 { palette[2] }
    var muted: UInt32 { palette[3] }
    var accent: UInt32 { palette[4] }
    var onAccent: UInt32 { palette[5] }
    /// The Ticker scene's photo-stand-in backdrop: Kick keeps its slate grey, the rest use their surface.
    var backdrop: UInt32 { self == .kick ? 0xFF2B_3138 : surface }

    /// "#RRGGBB", for Instagram's background layer colours.
    static func hex(_ argb: UInt32) -> String { String(format: "#%06X", argb & 0xFF_FFFF) }

    func color(_ argb: UInt32) -> Color {
        Color(.sRGB, red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
              blue: Double(argb & 0xFF) / 255, opacity: 1)
    }
}
