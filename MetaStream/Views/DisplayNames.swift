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

    static func eventSummary(_ e: ChatEvent) -> String {
        switch e.kind {
        case .tip:
            let amount = String(format: "%.2f", Double(e.amountCents) / 100)
            return "\(e.user) tipped $\(amount)" + (e.text.isEmpty ? "" : " — \(e.text)")
        case .cheer: return "\(e.user) cheered \(e.count) bits" + (e.text.isEmpty ? "" : " — \(e.text)")
        case .follow: return "\(e.user) followed"
        case .subscribe: return "\(e.user) subscribed"
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

    static func roundButton(_ icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        stripButton(label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(filled ? .black : .white)
                .frame(width: 52, height: 52)
                .background(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
        }, action: action)
    }
}

func hapticTap(strong: Bool = false) {
    UIImpactFeedbackGenerator(style: strong ? .heavy : .light).impactOccurred()
}
