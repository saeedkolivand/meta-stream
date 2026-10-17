import SwiftUI

/// Native, aggregated chat sheet: every origin ChatFeed is running lands in one list, newest at the bottom.
struct ChatSheetView: View {
    @EnvironmentObject var chat: ChatFeed
    @EnvironmentObject var platforms: Platforms
    @ObservedObject var vm: StreamViewModel
    @ObservedObject var emotes: Emotes
    @Binding var showChat: Bool
    @Binding var showSettings: Bool
    @Binding var showManager: Bool

    @AppStorage("chatChannel") var chatChannel = ""
    /// Index into chatSizes. Defaults one step above system size: chat is read at a glance from a phone
    /// mounted on a dash, not held at reading distance.
    @AppStorage("chatTextSize") var chatTextSize = 1
    private static let chatSizes: [DynamicTypeSize] = [.large, .xxLarge, .accessibility2, .accessibility4]

    @State private var chatText = ""
    @AppStorage("botCommands") var commandsRaw = BotCommand.seed
    @State private var atBottom = true
    @EnvironmentObject var speaker: Speaker   // injected app-wide in App.swift; sheets inherit it
    @State private var summary: String?
    @State private var summaryError: String?
    @State private var summarizing = false

    /// True once at least one origin is set up to produce chat - Kick needs only a channel name, Twitch/
    /// YouTube need a connected account. Drives the sheet's "no chat source" empty state.
    private var chatConfigured: Bool {
        !chatChannel.isEmpty || platforms.twitchConnected || platforms.ytConnected
    }

    private var sendOrigins: [String] {
        vm.sendOrigins(twitchConnected: platforms.twitchConnected, ytConnected: platforms.ytConnected)
    }

    var body: some View {
        Group {
            if !chatConfigured {
                VStack(spacing: 12) {
                    Text("No chat source set").font(.headline)
                    Text("Set a channel name in Settings, or connect a platform in Stream Manager and tap “Use for streaming”.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Button("Settings") { showChat = false; showSettings = true }
                        Button("Stream Manager") { showChat = false; showManager = true }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatList
            }
        }
        .padding(.top, 8)
    }

    /// Auto-scrolls on new messages only while the user is already at the bottom — the onAppear/onDisappear
    /// pair on the trailing anchor is "is the bottom on screen right now", no scroll-offset PreferenceKey
    /// needed. Once the user scrolls up to read history, new messages stop yanking them back down.
    private var chatList: some View {
        VStack(spacing: 0) {
            if ChatModerator.available { catchUpBar }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chat.recent.enumerated()), id: \.offset) { i, event in
                            chatRow(event, animate: i >= chat.recent.count - StreamChatView.animatedRows)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal)
                }
                .dynamicTypeSize(Self.chatSizes[min(chatTextSize, Self.chatSizes.count - 1)])
                .onChange(of: chat.recent.count) { _, _ in
                    guard atBottom else { return }
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            composeBar
        }
    }

    /// `.message` gets full weight - a card per message: origin circle, role chips + bold colored name on
    /// the first line, message with inline emotes below. Everything else (tips/cheers/follows/subs/raids)
    /// is already spoken aloud by Speaker, so it renders compact and secondary with no card.
    @ViewBuilder
    private func chatRow(_ event: ChatEvent, animate: Bool) -> some View {
        if event.kind == .message {
            HStack(alignment: .top, spacing: 10) {
                originBadge(event.origin)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(event.badges, id: \.self) { badgeChip($0) }
                        Text(event.user).font(.subheadline.weight(.bold))
                            .foregroundStyle(DisplayNames.nameColor(event))
                        if event.flagged {
                            Text("hidden from stream").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        }
                    }
                    if animate, emotes.animates(event.text) {
                        // ponytail: 10 fps; only rows holding an animated emote tick, and LazyVStack only builds visible ones.
                        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in messageText(event, at: ctx.date).font(.body) }
                    } else {
                        messageText(event).font(.body)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(BotList.isAnnouncement(user: event.user, text: event.text) ? Color.yellow.opacity(0.28) : Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12))
            .opacity(event.flagged ? 0.55 : 1)   // AI-flagged: still shown here so the streamer can ban the sender
            .padding(.vertical, 3)
        } else {
            HStack(spacing: 8) {
                originBadge(event.origin)
                Text(DisplayNames.eventSummary(event)).font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
        }
    }

    /// "Catch me up": on-device summary of the last ~60 messages, shown here and optionally read aloud.
    private var catchUpBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: catchUp) {
                Label(summarizing ? "Summarizing…" : "Catch me up", systemImage: "sparkles")
            }
            .disabled(summarizing)
            if let summary {
                Text(summary).font(.footnote)
                HStack {
                    Button("Read it") { speaker.speakSystem(summary) }
                    Button("Dismiss") { self.summary = nil }
                }
                .font(.footnote)
            }
            if let summaryError { Text(summaryError).font(.footnote).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal).padding(.bottom, 6)
    }

    private func catchUp() {
        summarizing = true
        summary = nil
        summaryError = nil
        let events = chat.recent
        Task {
            do { summary = try await ChatSummary.summarize(events) }
            catch let f as ChatSummary.Failure { summaryError = f.message }
            catch { summaryError = "Couldn't summarize right now." }
            summarizing = false
        }
    }

    private func badgeChip(_ badge: String) -> some View {
        let style = DisplayNames.badgeStyle(badge)
        return HStack(spacing: 2) {
            Image(systemName: style.symbol)
            if !style.label.isEmpty { Text(style.label) }
        }
        .font(.caption2.weight(.heavy))
        .foregroundStyle(style.color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(style.color.opacity(0.18), in: Capsule())
        .accessibilityLabel(style.label.isEmpty ? badge : style.label.capitalized)
    }

    private func originBadge(_ origin: String) -> some View {
        Text(origin.isEmpty ? "?" : origin.prefix(1).uppercased())
            .font(.caption2.bold())
            .frame(width: 20, height: 20)
            .foregroundStyle(.white)
            .background(DisplayNames.originColor(origin), in: Circle())
    }

    /// Inline emotes via Text concatenation: `Text(Image(...))` is the only way to get an image flowing
    /// inside wrapped text instead of breaking out as a separate view. An emote still loading renders as
    /// an empty run this pass; the row redraws once it lands.
    private func messageText(_ event: ChatEvent, at time: Date? = nil) -> Text {
        Emotes.tokenize(event.text, byName: emotes.byName).reduce(Text("")) { partial, run in
            switch run {
            case .text(let s): return Text("\(partial)\(Text(s))")
            case .emote(let url):
                if let img = emotes.image(for: url, at: time) { return Text("\(partial)\(Text(img))") }
                return partial
            }
        }
    }

    private var composeBar: some View {
        VStack(spacing: 8) {
            if !vm.slashNote.isEmpty { Text(vm.slashNote).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            commandPicker
            if sendOrigins.count > 1 {
                Picker("Send to", selection: $vm.chatOrigin) {
                    ForEach(sendOrigins, id: \.self) { Text(DisplayNames.platformName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                // One tap cycles the size, so it's usable without looking for a slider.
                Button { hapticTap(); chatTextSize = (chatTextSize + 1) % Self.chatSizes.count } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Chat text size")
                TextField("Message", text: $chatText).textFieldStyle(.roundedBorder).onSubmit(sendChat)
                Button(action: sendChat) { Image(systemName: "paperplane.fill") }
                    .disabled(chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Typing "!" lists the saved commands with that prefix; otherwise a row of chips. Both send straight away.
    @ViewBuilder private var commandPicker: some View {
        let all = BotCommand.decode(commandsRaw)
        let typed = chatText.lowercased()
        let matches = typed.hasPrefix("!") ? all.filter { $0.text.lowercased().hasPrefix(typed) } : []
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(matches) { c in
                    Button { chatText = ""; run(c) } label: { Text(c.text).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        } else if !all.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(all) { c in Button(c.text) { run(c) }.buttonStyle(.bordered) } }
            }
        }
    }

    private func run(_ c: BotCommand) {
        hapticTap()
        Task {
            let note = await c.send(platforms, chat: chat)
            if !note.isEmpty { vm.slashNote = note }
        }
    }

    private func sendChat() {
        let text = chatText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatText = ""
        Task { await vm.sendChat(text, platforms: platforms, chat: chat) }
    }
}
