import SwiftUI

/// Shared display names + small chat-presentation helpers. Single home for every mode/id -> label
/// switch so ContentView, Settings and StreamManager never drift apart with three copies.
enum DisplayNames {
    static func platformName(_ id: String) -> String {
        ["kick": "Kick", "twitch": "Twitch", "youtube": "YouTube", "restream": "Restream",
         "instagram": "Instagram", "tiktok": "TikTok", "custom": "Custom"][id] ?? id
    }

    static func stabilizationShort(_ mode: String) -> String {
        switch mode {
        case "standard": return "STD"
        case "cinematic": return "CINE"
        case "action": return "ACTION"
        default: return "OFF"
        }
    }

    static func stabilizationLabel(_ mode: String) -> String {
        switch mode {
        case "standard": return "Standard"
        case "cinematic": return "Cinematic"
        case "action": return "Action"
        default: return "Off"
        }
    }

    static func originColor(_ origin: String) -> Color {
        origin == "twitch" ? .purple : origin == "youtube" ? .red : .green
    }

    /// SF Symbol + short label + tint per normalized badge id (see ChatBadges).
    static func badgeStyle(_ badge: String) -> (symbol: String, label: String, color: Color) {
        switch badge {
        case "broadcaster": return ("video.fill", "HOST", .red)
        case "moderator": return ("shield.fill", "MOD", .green)
        case "staff": return ("wrench.and.screwdriver.fill", "STAFF", .indigo)
        case "vip": return ("diamond.fill", "VIP", .pink)
        case "verified": return ("checkmark.seal.fill", "", .blue)
        case "founder": return ("star.circle.fill", "FOUNDER", .yellow)
        case "subscriber": return ("star.fill", "SUB", .purple)
        default: return ("flame.fill", "OG", .orange)
        }
    }

    /// Username color: the sender's own color lifted to a readable luminance, else the origin color.
    static func nameColor(_ e: ChatEvent) -> Color {
        guard let hex = e.color, let c = ChatBadges.readableRGB(hex: hex) else { return originColor(e.origin) }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    static func eventSummary(_ e: ChatEvent) -> String {
        switch e.kind {
        case .tip:
            let amount = String(format: "%.2f", Double(e.amountCents) / 100)
            return "\(e.user) tipped $\(amount)" + (e.text.isEmpty ? "" : " — \(e.text)")
        case .cheer: return "\(e.user) cheered \(e.count) bits" + (e.text.isEmpty ? "" : " — \(e.text)")
        case .follow: return "\(e.user) followed"
        case .subscribe:
            return e.count == 0 ? "\(e.user) subscribed" : e.count == 1 ? "\(e.user) gifted a sub" : "\(e.user) gifted \(e.count) subs"
        case .raid: return "\(e.user) raided with \(e.count) viewers"
        case .message: return e.text
        }
    }
}

/// Migrates the old `chatSite` UserDefaults key to `chatOrigin`. Call before first read; safe to call
/// repeatedly. Keeps users' existing choice after the rename.
enum ChatOriginKey {
    static let newKey = "chatOrigin"
    static let oldKey = "chatSite"
    static func migrate() {
        let d = UserDefaults.standard
        if d.object(forKey: newKey) == nil, let old = d.string(forKey: oldKey) {
            d.set(old, forKey: newKey)
        }
    }
}

/// Shared button chrome for the live screen: one capsule pill and one round/strip button so HUD,
/// quick controls and camera strip share sizing, fonts and haptics instead of three copies.
@MainActor
struct StripStyles {
    static func pill(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    static func stripButton<Label: View>(@ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
    }

    /// `tint` fills the circle with a colour (white glyph) and wins over `filled`; nil keeps the white/material look.
    static func roundButton(_ icon: String, filled: Bool, tint: Color? = nil, size: CGFloat = 52,
                            action: @escaping () -> Void) -> some View {
        stripButton(label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(filled && tint == nil ? .black : .white)
                .frame(width: size, height: size)
                .background(tint.map { AnyShapeStyle($0) } ?? (filled ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial)),
                            in: Circle())
        }, action: action)
    }
}

@MainActor
func hapticTap(strong: Bool = false) {
    UIImpactFeedbackGenerator(style: strong ? .heavy : .light).impactOccurred()
}
