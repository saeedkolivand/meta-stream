import SwiftUI

/// iOS-Settings-style rounded square with a white SF Symbol (or a brand letter) on a colour.
struct SettingsTile: View {
    let color: Color
    var symbol: String?
    var letter: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color).frame(width: 30, height: 30)
            .overlay {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                } else if let letter {
                    Text(letter).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}

/// One catalog page as a list row: tile, title, grey value, orange issue badge. The chevron comes from the NavigationLink
/// on iPhone and from the sidebar selection on iPad.
struct SettingsPageRow: View {
    let page: SettingsPage
    let value: String
    let issues: Int
    var wrappedPending = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsTile(color: page.tint, symbol: page.symbol)
            Text(page.title)
            Spacer(minLength: 8)
            if !value.isEmpty { Text(value).foregroundStyle(.secondary).lineLimit(1) }
            if wrappedPending { Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("New") }
            if issues > 0 {
                Text("\(issues)").font(.caption.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color.orange, in: Capsule())
                    .accessibilityLabel("\(issues) to check")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A search hit for one setting: breadcrumb subtitle, and an inline Toggle for plain switches. Others call `open` with their page.
struct SettingsItemRow: View {
    let item: SettingsItem
    let page: SettingsPage
    let open: (String) -> Void

    var body: some View {
        if let key = item.key {
            ItemToggle(item: item, key: key, fallback: item.defaultOn)
        } else {
            Button { open(page.id) } label: {
                HStack(spacing: 12) {
                    SettingsTile(color: page.tint, symbol: page.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.path).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Bound to the same UserDefaults key the real screen's @AppStorage uses, so both stay in step.
private struct ItemToggle: View {
    let item: SettingsItem
    @AppStorage private var isOn: Bool

    init(item: SettingsItem, key: String, fallback: Bool) {
        self.item = item
        _isOn = AppStorage(wrappedValue: fallback, key)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.path).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// The "Ready to go live" card: what will go out, plus one row per real problem, each opening the screen that fixes it.
struct ReadinessCard: View {
    let chips: [String]
    let issues: [SettingsIssue]
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(issues.isEmpty ? Color.green : Color.orange).frame(width: 10, height: 10)
                Text(issues.isEmpty ? "Ready to go live" : "Check before going live").font(.headline)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip).font(.footnote).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                }
            }
            ForEach(issues) { issue in
                Button { open(issue.pageID) } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(issue.message).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
