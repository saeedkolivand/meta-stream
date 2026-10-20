import SwiftUI

/// Settings › Telegram: the bot and channel behind the Live post, and what the post may show.
struct TelegramSettingsView: View {
    @AppStorage("telegramOn") private var on = false
    @AppStorage("telegramChannel") private var channel = ""
    @AppStorage("telegramLang") private var lang = "fa"
    @AppStorage("telegramShowCity") private var showCity = false
    @AppStorage("telegramShowTotal") private var showTotal = true
    @AppStorage("telegramPings") private var pings = true
    @AppStorage("momentDonationEUR") private var bigDonation = 20.0
    @State private var token = ""
    @State private var hasToken = false
    @State private var status = ""
    @State private var checking = false

    private let keychain = KeychainTokenStore()

    var body: some View {
        Form {
            Section {
                Toggle("Live post", isOn: $on)
                // Never loaded back into the field: the saved token stays in the Keychain, the field only takes a new one.
                SecureField(hasToken ? "Key saved (enter a new one to replace)" : "Bot token", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save") {
                    keychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "telegramToken")
                    token = ""
                    hasToken = keychain.string(forKey: "telegramToken") != nil
                }.buttonStyle(.borderless).disabled(token.isEmpty)
                TextField("Channel", text: $channel, prompt: Text("@yourchannel"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(checking ? "Checking…" : "Check bot") {
                    checking = true
                    Task { status = await Telegram.check(); checking = false }
                }.buttonStyle(.borderless).disabled(checking)
                if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Telegram") } footer: {
                Text("1. Message @BotFather, send /newbot, paste the token above.\n2. Add the bot as an admin of your channel "
                     + "with only Post, Edit and Delete messages.\n3. Enter the channel and tap Check bot.")
            }
            Section {
                Picker("Language", selection: $lang) {
                    Text("فارسی").tag("fa")
                    Text("English").tag("en")
                }
                Toggle("Show donation total in recap", isOn: $showTotal)
                Stepper(value: $bigDonation, in: 1...1000, step: 5) { Text("Big donation moment (€\(Int(bigDonation)))") }
            } header: { Text("Post") } footer: {
                Text("The language only changes the labels; titles and names stay as you typed them.")
            }
            Section {
                Toggle("Moment pings", isOn: $pings)
            } footer: {
                Text("A short reply to the live post when chat spikes, a big donation lands or a raid comes in; "
                     + "at most one per 15 min and 4 per stream, deleted when the stream ends.")
            }
            Section {
                Toggle("Show city", isOn: $showCity)
            } footer: {
                Text("Adds your city to the live post. The post stays in the channel after the stream, so the city does too.")
            }
        }
        .navigationTitle("Telegram")
        .onAppear { hasToken = keychain.string(forKey: "telegramToken") != nil }
    }
}
