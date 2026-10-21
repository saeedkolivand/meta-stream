import SwiftUI

/// Settings › Accounts: every login in one place -- streaming platforms, chat bots, services and donation sites.
/// Connecting here and in Stream Manager use the same Platforms methods, so either shows the other's state.
struct AccountsSettingsView: View {
    @EnvironmentObject var platforms: Platforms
    @ObservedObject private var bot = AppBot.shared
    @ObservedObject private var spotify = SpotifyNowPlaying.shared
    @ObservedObject private var hub = DonationHub.shared
    @AppStorage("telegramOn") private var telegramOn = false
    @AppStorage("telegramChannel") private var telegramChannel = ""

    private static let streaming: [(key: String, letter: String, tint: Color)] = [
        ("kick", "K", Color(red: 0.12, green: 0.55, blue: 0.12)), ("twitch", "T", Color(red: 0.57, green: 0.27, blue: 1)),
        ("youtube", "Y", .red), ("restream", "R", .blue)
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.streaming, id: \.key) { entry in
                    if let adapter = PlatformAdapter.all[entry.key] { streamingRow(adapter, entry.key, entry.letter, entry.tint) }
                }
            } header: { Text("Streaming") } footer: {
                Text("Title, category and stream key live in Stream Manager. " + platforms.status)
            }
            Section("Chat bots") {
                AccountRow(tint: Self.streaming[0].tint, letter: "K", title: "Kick app bot", detail: "Uses your Kick login")
                twitchBotRow
                NavigationLink("App bot settings") { AppBotSettingsView() }
            }
            Section("Services") {
                spotifyRow
                NavigationLink { TelegramSettingsView() } label: {
                    AccountRow(tint: .cyan, symbol: "paperplane.fill", title: "Telegram", detail: telegramDetail)
                }
            }
            Section {
                ForEach(DonationHub.Site.allCases, id: \.self) { site in
                    NavigationLink { DonationSourcesSettingsView() } label: {
                        AccountRow(tint: .red, letter: String(site.title.prefix(1)), title: site.title,
                                   detail: hub.status[site] ?? "Not set up")
                    }
                }
            } header: { Text("Donation sites") } footer: {
                Text("Keys are set on the Donation sources screen.")
            }
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var telegramDetail: String {
        if !telegramOn { return "Live post off" }
        return telegramChannel.isEmpty ? "No channel yet" : telegramChannel
    }

    // MARK: rows

    @ViewBuilder
    private func streamingRow(_ adapter: PlatformAdapter, _ key: String, _ letter: String, _ tint: Color) -> some View {
        let user = adapter.user(platforms)
        if !adapter.hasApp {
            AccountRow(tint: tint, letter: letter, title: adapter.name, detail: "No client ID in this build")
        } else if adapter.connected(platforms) {
            AccountRow(tint: tint, letter: letter, title: adapter.name, detail: user.isEmpty ? "Connected" : user,
                       action: AccountAction("Disconnect", destructive: true) { adapter.disconnect(platforms) })
        } else if key == "twitch", !platforms.twitchUserCode.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter this code on Twitch:").font(.footnote).foregroundStyle(.secondary)
                Text(platforms.twitchUserCode).font(.system(.title2, design: .monospaced).bold()).textSelection(.enabled)
                if let url = URL(string: platforms.twitchVerifyURL) {
                    Link("Open \(platforms.twitchVerifyURL)", destination: url).font(.footnote)
                }
            }
        } else {
            AccountRow(tint: tint, letter: letter, title: adapter.name, detail: "Not connected",
                       action: AccountAction("Connect") { adapter.connect(platforms) })
        }
    }

    @ViewBuilder
    private var twitchBotRow: some View {
        let purple = Color(red: 0.57, green: 0.27, blue: 1)
        if bot.twitchBotName.isEmpty {
            AccountRow(tint: purple, letter: "T", title: "Twitch bot account", detail: "Not connected",
                       action: AccountAction("Connect") { bot.connectTwitch() })
        } else {
            AccountRow(tint: purple, letter: "T", title: "Twitch bot account", detail: bot.twitchBotName,
                       action: AccountAction("Disconnect", destructive: true) { bot.disconnectTwitch() })
        }
    }

    private var spotifyRow: some View {
        AccountRow(tint: .green, symbol: "music.note", title: "Spotify", detail: spotify.connected ? "Connected" : "Not connected",
                   action: spotify.connected ? AccountAction("Disconnect", destructive: true) { spotify.disconnect() }
                                             : AccountAction("Connect") { spotify.connect() })
    }
}

/// A Connect / Disconnect button on an account line.
private struct AccountAction {
    let title: String
    let destructive: Bool
    let run: @MainActor () -> Void

    init(_ title: String, destructive: Bool = false, run: @escaping @MainActor () -> Void) {
        self.title = title
        self.destructive = destructive
        self.run = run
    }
}

/// One account line: tile, name, status, and an optional Connect / Disconnect button.
private struct AccountRow: View {
    let tint: Color
    var symbol: String?
    var letter: String?
    let title: String
    let detail: String
    var action: AccountAction?

    var body: some View {
        HStack(spacing: 12) {
            SettingsTile(color: tint, symbol: symbol, letter: letter)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action.title, role: action.destructive ? .destructive : nil, action: action.run)
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
