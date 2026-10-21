import SwiftUI

/// The settings list's section headings, in display order.
enum SettingsGroup: String, CaseIterable {
    case accounts, stream, onScreen, chat, money, reach, streams, system

    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .stream: return "Stream"
        case .onScreen: return "On screen"
        case .chat: return "Chat"
        case .money: return "Money"
        case .reach: return "Reach"
        case .streams: return "Your streams"
        case .system: return "System"
        }
    }
}

/// What a page's live value and issue checks may read besides UserDefaults.
@MainActor
struct SettingsContext {
    let platforms: Platforms
    let streamer: Streamer
}

/// One settings screen: its row on the list/sidebar, and the screen itself.
struct SettingsPage: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let group: SettingsGroup
    let destination: @MainActor () -> AnyView
    /// Short grey summary shown on the row; empty = show nothing.
    var value: @MainActor (SettingsContext) -> String = { _ in "" }
}

/// One searchable setting. A plain on/off switch carries its UserDefaults key and default so search can flip it inline;
/// everything else opens its page.
struct SettingsItem: Identifiable {
    let id: String
    let title: String
    let pageID: String
    let keywords: String
    var path = ""
    var key: String?
    var defaultOn = false
    var sub: String?          // the sub-screen it sits on ("Pro controls"), for the breadcrumb

    init(_ title: String, _ pageID: String, _ keywords: String = "", key: String? = nil, on: Bool = false, sub: String? = nil) {
        self.id = pageID + "/" + title
        self.title = title
        self.pageID = pageID
        self.keywords = keywords
        self.key = key
        self.defaultOn = on
        self.sub = sub
    }
}

/// The single source of the settings rows AND of search: pages and items live here and nowhere else, so adding a
/// screen here adds its row, its sidebar entry and its search hits together.
/// ponytail: item lists are still written by hand (one line per setting); a stale entry only costs a search hit, never a broken row.
@MainActor
enum SettingsCatalog {
    static func pages() -> [SettingsPage] {
        var list = accountsAndStream()
        if Streamer.glassesConfigured {
            list.insert(SettingsPage(id: "glasses", title: "Meta glasses", symbol: "eyeglasses", tint: .indigo, group: .stream,
                                     destination: { AnyView(GlassesVideoSettingsView()) },
                                     value: { _ in SettingsValues.glasses() }), at: 3)
        }
        return list + onScreenAndChat() + moneyAndRest()
    }

    private static func accountsAndStream() -> [SettingsPage] {
        [
            SettingsPage(id: "accounts", title: "Accounts", symbol: "person.crop.circle.fill", tint: .blue, group: .accounts,
                         destination: { AnyView(AccountsSettingsView()) }, value: { SettingsValues.accounts($0) }),
            SettingsPage(id: "ingest", title: "Destination", symbol: "dot.radiowaves.up.forward", tint: .red, group: .stream,
                         destination: { AnyView(IngestSettingsView()) }, value: { _ in SettingsValues.ingest() }),
            SettingsPage(id: "camera", title: "Camera", symbol: "camera.fill", tint: .gray, group: .stream,
                         destination: { AnyView(CameraSettingsView()) }, value: { SettingsValues.camera($0) }),
            SettingsPage(id: "audio", title: "Audio", symbol: "mic.fill", tint: .pink, group: .stream,
                         destination: { AnyView(AudioSettingsView()) }, value: { SettingsValues.audio($0) }),
            SettingsPage(id: "privacy", title: "Privacy blur", symbol: "eye.slash.fill", tint: .teal, group: .stream,
                         destination: { AnyView(PrivacySettingsView()) }, value: { _ in SettingsValues.privacy() })
        ]
    }

    private static func onScreenAndChat() -> [SettingsPage] {
        [
            SettingsPage(id: "overlays", title: "Scenes & widgets", symbol: "square.stack.3d.up.fill", tint: .orange, group: .onScreen,
                         destination: { AnyView(OverlaySettingsView()) }, value: { _ in SettingsValues.scenes() }),
            SettingsPage(id: "transitions", title: "Transitions", symbol: "rectangle.2.swap", tint: .purple, group: .onScreen,
                         destination: { AnyView(SceneOptionsView()) }),
            SettingsPage(id: "theme", title: "Theme & story", symbol: "paintpalette.fill", tint: .pink, group: .onScreen,
                         destination: { AnyView(ThemeSettingsView()) }, value: { _ in SettingsValues.theme() }),
            SettingsPage(id: "chat", title: "Chat & read aloud", symbol: "bubble.left.and.text.bubble.right.fill", tint: .green,
                         group: .chat, destination: { AnyView(ReadAloudSettingsView()) }, value: { _ in SettingsValues.chat() }),
            SettingsPage(id: "commands", title: "Commands", symbol: "exclamationmark.bubble.fill", tint: .orange, group: .chat,
                         destination: { AnyView(CommandsSettingsView()) }, value: { _ in SettingsValues.commands() }),
            SettingsPage(id: "appbot", title: "App bot", symbol: "cpu.fill", tint: .indigo, group: .chat,
                         destination: { AnyView(AppBotSettingsView()) }, value: { _ in SettingsValues.appBot() }),
            SettingsPage(id: "bots", title: "Known bots", symbol: "person.badge.shield.checkmark.fill", tint: .gray, group: .chat,
                         destination: { AnyView(BotsSettingsView()) })
        ]
    }

    private static func moneyAndRest() -> [SettingsPage] {
        [
            SettingsPage(id: "goal", title: "Goal", symbol: "target", tint: .green, group: .money,
                         destination: { AnyView(GoalSettingsView()) }, value: { _ in SettingsValues.goal() }),
            SettingsPage(id: "sources", title: "Donation sources", symbol: "heart.fill", tint: .red, group: .money,
                         destination: { AnyView(DonationSourcesSettingsView()) }, value: { _ in SettingsValues.sources() }),
            SettingsPage(id: "donatepage", title: "Donate page", symbol: "globe", tint: .blue, group: .money,
                         destination: { AnyView(DonatePageSettingsView()) }),
            SettingsPage(id: "telegram", title: "Telegram", symbol: "paperplane.fill", tint: .cyan, group: .reach,
                         destination: { AnyView(TelegramSettingsView()) }, value: { _ in SettingsValues.telegram() }),
            SettingsPage(id: "spotify", title: "Spotify", symbol: "music.note", tint: .green, group: .reach,
                         destination: { AnyView(SpotifySettingsView()) }, value: { _ in SettingsValues.spotify() }),
            SettingsPage(id: "streams", title: "Streams", symbol: "clock.arrow.circlepath", tint: .purple, group: .streams,
                         destination: { AnyView(StreamsView()) }),
            SettingsPage(id: "remote", title: "Remote control", symbol: "antenna.radiowaves.left.and.right", tint: .gray, group: .system,
                         destination: { AnyView(RemoteSettingsView()) }, value: { _ in SettingsValues.remote() }),
            SettingsPage(id: "diagnostics", title: "Diagnostics & about", symbol: "info.circle.fill", tint: .gray, group: .system,
                         destination: { AnyView(DiagnosticsSettingsView()) })
        ]
    }

    /// Items with their breadcrumb ("Chat › App bot") filled in from the page they belong to.
    static func items(pages: [SettingsPage]) -> [SettingsItem] {
        let byID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        return SettingsItems.all.compactMap { item in
            guard let page = byID[item.pageID] else { return nil }   // e.g. glasses items when glasses aren't configured
            var out = item
            out.path = page.group.title + " › " + page.title + (item.sub.map { " › " + $0 } ?? "")
            return out
        }
    }

    /// Every word typed must appear somewhere in the haystack; case and accents ignored.
    static func matches(_ query: String, in haystack: String) -> Bool {
        let words = query.split(separator: " ").map(String.init)
        return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
