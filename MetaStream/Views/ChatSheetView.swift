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
    @State private var atBottom = true

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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(chat.recent.enumerated()), id: \.offset) { _, event in
                            chatRow(event)
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

    /// `.message` gets full weight — badge, username, message with inline emotes. Everything else
    /// (tips/cheers/follows/subs/raids) is already spoken aloud by Speaker, so it renders smaller here.
    @ViewBuilder
    private func chatRow(_ event: ChatEvent) -> some View {
        if event.kind == .message {
            HStack(alignment: .top, spacing: 10) {
                originBadge(event.origin)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.user).font(.subheadline.weight(.semibold))
                    messageText(event).font(.body)
                }
            }
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 8) {
                originBadge(event.origin)
                Text(DisplayNames.eventSummary(event)).font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
        }
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
    private func messageText(_ event: ChatEvent) -> Text {
        Emotes.tokenize(event.text, byName: emotes.byName).reduce(Text("")) { partial, run in
            switch run {
            case .text(let s): return partial + Text(s)
            case .emote(let url):
                if let img = emotes.image(for: url) { return partial + Text(img) }
                return partial + Text("")
            }
        }
    }

    private var composeBar: some View {
        VStack(spacing: 8) {
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

    private func sendChat() {
        let text = chatText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatText = ""
        Task { await vm.sendChat(text, platforms: platforms) }
    }
}
