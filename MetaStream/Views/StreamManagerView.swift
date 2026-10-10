import SwiftUI

/// Title / category / viewers / chat / stream key for the connected accounts.
struct StreamManagerView: View {
    @EnvironmentObject var platforms: Platforms
    @Environment(\.dismiss) private var dismiss
    @AppStorage("platform") var platformPref = "kick"
    @AppStorage("rtmpURL") var ingestURL = Platforms.kickIngest
    @AppStorage("streamKey") var streamKey = ""
    @AppStorage("chatOrigin") var chatOrigin = "kick"
    @AppStorage("chatChannel") var chatChannel = ""
    @AppStorage("restreamChatURL") var restreamChatURL = ""
    @AppStorage("youtubeVideoID") var youtubeVideoID = ""

    init() { ChatOriginKey.migrate() }

    @State private var tab = "kick"
    @State private var title = ""
    @State private var category: StreamCategory?
    @State private var search = ""
    @State private var results: [StreamCategory] = []
    @State private var chatText = ""
    @State private var busy = false
    @State private var announceText = ""
    @State private var raidTarget = ""

    @State private var tags = ""
    @State private var labels: [String: Bool] = [:]
    @State private var delay = 0
    @State private var language = ""
    @State private var description = ""
    @State private var privacy = "public"
    @State private var latency = "normal"

    private var adapter: PlatformAdapter { PlatformAdapter.all[tab] ?? PlatformAdapter.all["kick"]! }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $tab) {
                    Text("Kick").tag("kick"); Text("Twitch").tag("twitch"); Text("Restream").tag("restream"); Text("YouTube").tag("youtube")
                }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
                .onChange(of: tab) { _, _ in loadFields() }

                if !adapter.hasApp {
                    Section { Text("This build has no \(adapter.name) client ID. Add the RESTREAM_/YOUTUBE_ secrets and rebuild.").foregroundStyle(.secondary) }
                } else if !adapter.connected(platforms) {
                    connectSection
                } else {
                    headerSection
                    if tab == "twitch" { twitchActionsSection }
                    infoSection
                    if tab == "restream" { restreamDestinationsSection }
                    keySection
                    if adapter.canSendChat { chatSection }
                    Section {
                        Button("Disconnect \(adapter.name)", role: .destructive) { disconnect() }
                    } footer: { Text(platforms.status) }
                }
            }
            .navigationTitle("Stream Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { tab = ["twitch", "restream", "youtube"].contains(platformPref) ? platformPref : "kick"; loadFields() }
            .onChange(of: platforms.kickTitle) { _, _ in if tab == "kick" { loadFields() } }
            .onChange(of: platforms.twitchTitle) { _, _ in if tab == "twitch" { loadFields() } }
            .onChange(of: platforms.restreamTitle) { _, _ in if tab == "restream" { loadFields() } }
            .onChange(of: platforms.ytTitle) { _, _ in if tab == "youtube" { loadFields() } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: sections

    private var connectSection: some View {
        Section {
            if tab == "twitch", !platforms.twitchUserCode.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter this code on Twitch:").font(.footnote).foregroundStyle(.secondary)
                    Text(platforms.twitchUserCode).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled)
                    Link("Open \(platforms.twitchVerifyURL)", destination: URL(string: platforms.twitchVerifyURL) ?? URL(string: "https://www.twitch.tv/activate")!)
                        .font(.footnote)
                }
            } else {
                Button {
                    adapter.connect(platforms)
                } label: {
                    HStack { Spacer(); Image(systemName: "link"); Text("Connect \(adapter.name)").bold(); Spacer() }
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } footer: {
            Text(tab == "youtube" ? "Create the live stream in YouTube Studio first; the app then finds it.\n" + platforms.status : platforms.status)
        }
    }

    private var headerSection: some View {
        Section {
            HStack {
                let live = adapter.isLive(platforms)
                Circle().fill(live ? .red : .gray).frame(width: 10, height: 10)
                Text(adapter.user(platforms)).bold()
                Spacer()
                if tab == "restream" { Text("\(platforms.restreamDestinations.filter(\.active).count)/\(platforms.restreamDestinations.count) destinations").foregroundStyle(.secondary) }
                else { Text(live ? "\(adapter.viewers(platforms)) viewers" : "offline").foregroundStyle(.secondary) }
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
            }
        }
    }

    /// One scope-gated Twitch action button: disables itself with no tap-time 401 when its write scope
    /// hasn't been granted yet (see Platforms.twitchActionScopes).
    private func twitchActionButton<Label: View>(scopes: Set<String>, extraDisabled: Bool = false, action: @escaping () async -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button { Task { await action() } } label: { label() }
            .disabled(!platforms.twitchHasScopes(scopes) || extraDisabled)
    }

    /// Hands-free Twitch actions: one decisive tap each, no screen reading required to use them (the glasses
    /// use case this app exists for).
    private var twitchActionsSection: some View {
        Section {
            HStack(spacing: 12) {
                twitchActionButton(scopes: Platforms.twitchActionScopes["clips"]!, action: {
                    do { let c = try await platforms.twitchCreateClip(); platforms.status = "Clip created: \(c.url)" }
                    catch { platforms.status = error.localizedDescription }
                }) {
                    VStack(spacing: 4) { Image(systemName: "scissors").font(.title2); Text("Clip").bold() }.frame(maxWidth: .infinity)
                }
                twitchActionButton(scopes: ["channel:manage:broadcast"], action: {
                    do { try await platforms.twitchCreateMarker(); platforms.status = "Marker set" }
                    catch { platforms.status = error.localizedDescription }
                }) {
                    VStack(spacing: 4) { Image(systemName: "bookmark.fill").font(.title2); Text("Marker").bold() }.frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .listRowInsets(EdgeInsets()).padding(.vertical, 4)

            HStack {
                Text("Next ad").foregroundStyle(.secondary)
                Spacer()
                if let next = platforms.twitchAdNextAt { Text(next, style: .relative) } else { Text("unknown") }
            }
            twitchActionButton(scopes: Platforms.twitchActionScopes["ads"]!, extraDisabled: platforms.twitchAdSnoozeCount == 0,
                action: { await platforms.twitchSnoozeAd() }) {
                Text("Snooze ad (\(platforms.twitchAdSnoozeCount) left)")
            }
            twitchActionButton(scopes: Platforms.twitchActionScopes["commercial"]!,
                action: { await platforms.twitchStartCommercial() }) {
                Text("Start 90s commercial")
            }
            HStack {
                Text("Chat lockdown").foregroundStyle(.secondary)
                Spacer()
                twitchActionButton(scopes: Platforms.twitchActionScopes["chat lockdown"]!, action: { await platforms.twitchLockdownChat(on: true) }) { Text("Lock") }
                twitchActionButton(scopes: Platforms.twitchActionScopes["chat lockdown"]!, action: { await platforms.twitchLockdownChat(on: false) }) { Text("Unlock") }
            }
            HStack {
                TextField("Announcement", text: $announceText)
                twitchActionButton(scopes: Platforms.twitchActionScopes["announcements"]!,
                    extraDisabled: announceText.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: { let t = announceText; announceText = ""; await platforms.twitchAnnounce(t) }) { Text("Send") }
            }
            HStack {
                TextField("Raid channel", text: $raidTarget).textInputAutocapitalization(.never).autocorrectionDisabled()
                twitchActionButton(scopes: Platforms.twitchActionScopes["raids"]!,
                    extraDisabled: raidTarget.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: { let t = raidTarget; raidTarget = ""; await platforms.twitchRaid(t) }) { Text("Raid") }
            }
        } header: { Text("Quick actions") } footer: {
            if !platforms.twitchMissingScopeFeatures.isEmpty {
                Text("Disconnect and reconnect Twitch below to enable \(platforms.twitchMissingScopeFeatures.joined(separator: ", ")).")
                    .foregroundStyle(.orange)
            } else {
                Text("Moderation (delete/timeout/ban) is available from chat message rows.")
            }
        }
    }

    private var infoSection: some View {
        Section {
            TextField("Title", text: $title, axis: .vertical).lineLimit(1...3)
            if adapter.hasCategory {
                HStack { Text("Category").foregroundStyle(.secondary); Spacer(); Text(category?.name ?? "—").lineLimit(1) }
                TextField("Search category…", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: search) { _, q in
                        Task { results = tab == "kick" ? await platforms.kickSearch(q) : await platforms.twitchSearch(q) }
                    }
                ForEach(results) { c in
                    Button { category = c; search = ""; results = [] } label: {
                        HStack { Text(c.name); Spacer(); if c == category { Image(systemName: "checkmark") } }
                    }
                }
            }
            if tab == "kick" || tab == "twitch" {
                TextField("Tags, comma separated", text: $tags)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if tab == "twitch" {
                TextField("Language (e.g. en)", text: $language)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Stepper("Stream delay: \(delay)s", value: $delay, in: 0...900, step: 15)
                ForEach(twitchLabelOptions, id: \.id) { opt in
                    Toggle(opt.name, isOn: Binding(get: { labels[opt.id] ?? false }, set: { labels[opt.id] = $0 }))
                }
            }
            if tab == "youtube" {
                TextField("Description", text: $description, axis: .vertical).lineLimit(1...4)
                Picker("Privacy", selection: $privacy) {
                    Text("Public").tag("public"); Text("Unlisted").tag("unlisted"); Text("Private").tag("private")
                }
                Picker("Latency", selection: $latency) {
                    Text("Normal").tag("normal"); Text("Low").tag("low"); Text("Ultra-low").tag("ultraLow")
                }
            }
            Button {
                busy = true
                let draft = StreamInfoDraft(title: title, category: category, tags: tags, labels: labels, delay: delay, language: language, description: description, privacy: privacy, latency: latency)
                Task {
                    await adapter.apply(platforms, draft)
                    busy = false
                }
            } label: {
                HStack { Spacer(); if busy { ProgressView() } else { Text(tab == "restream" ? "Apply title to all destinations" : "Apply changes").bold() }; Spacer() }
            }
            .buttonStyle(.borderedProminent).disabled(busy || title.isEmpty)
        } header: { Text("Stream info") } footer: {
            if tab == "twitch" { Text("Stream delay is Partner-only — Twitch ignores or errors it otherwise. It's the anti-stream-sniping delay, worth it for IRL.") }
        }
    }

    /// The real label set (id, human name) from Platforms.fetchTwitchLabelCatalog() once it's loaded;
    /// Self.twitchLabelIDs + labelName() below while it's still empty (not yet fetched, or the call
    /// failed) -- see that function's doc for why empty is the safe default rather than blocking on it.
    private var twitchLabelOptions: [(id: String, name: String)] {
        platforms.twitchLabelCatalog.isEmpty
            ? Platforms.twitchLabelIDs.map { ($0, Self.labelName($0)) }
            : platforms.twitchLabelCatalog
    }

    /// Fallback names for Self.twitchLabelIDs, used only while twitchLabelOptions hasn't got a fetched
    /// catalog yet.
    private static func labelName(_ id: String) -> String {
        switch id {
        case "DebatedSocialIssuesAndPolitics": return "Debated social issues & politics"
        case "DrugsIntoxication": return "Drugs, intoxication"
        case "SexualThemes": return "Sexual themes"
        case "ViolentGraphic": return "Violent & graphic"
        case "Gambling": return "Gambling"
        case "ProfanityVulgarity": return "Profanity & vulgarity"
        default: return id
        }
    }

    private var restreamDestinationsSection: some View {
        Section {
            ForEach(platforms.restreamDestinations) { ch in
                Toggle(isOn: Binding(get: { ch.active }, set: { v in Task { await platforms.restreamSetActive(ch, v) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ch.name)
                        Text(ch.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } header: { Text("Destinations") } footer: {
            Text("Turning one off stops Restream sending there on your next stream. Add new destinations in the Restream dashboard.")
        }
    }

    private var keySection: some View {
        Section("Stream key") {
            let keyValue = adapter.streamKey(platforms)
            HStack {
                Text(keyValue.isEmpty ? "Not available" : "•••• " + String(keyValue.suffix(4)))
                    .font(.footnote.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Use for streaming") {
                    platformPref = tab
                    ingestURL = adapter.ingest(platforms)
                    streamKey = keyValue
                    chatOrigin = tab
                    if tab == "restream" { restreamChatURL = platforms.restreamChatURL }
                    if tab == "youtube" { youtubeVideoID = platforms.ytVideoID }
                    if chatChannel.isEmpty, adapter.hasCategory { chatChannel = adapter.user(platforms).lowercased() }
                    platforms.status = "Stream key and chat set for \(adapter.name)"
                }
                .disabled(keyValue.isEmpty)
            }
        }
    }

    private var chatSection: some View {
        Section("Send chat") {
            HStack {
                TextField("Message", text: $chatText).onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }.disabled(chatText.isEmpty)
            }
        }
    }

    // MARK: actions

    private func loadFields() {
        let d = adapter.load(platforms, twitchLabelOptions)
        title = d.title; category = d.category; tags = d.tags
        labels = d.labels; delay = d.delay; language = d.language
        description = d.description; privacy = d.privacy; latency = d.latency
        results = []; search = ""
    }

    private func refresh() async {
        await adapter.refresh(platforms)
        loadFields()
    }

    private func disconnect() {
        adapter.disconnect(platforms)
    }

    private func send() {
        let t = chatText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        chatText = ""
        Task { await adapter.send(platforms, t) }
    }
}
