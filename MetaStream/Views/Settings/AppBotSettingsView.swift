import SwiftUI

/// Settings › App bot: the app's own chat account (never the streamer) on Kick and Twitch.
struct AppBotSettingsView: View {
    @ObservedObject var bot = AppBot.shared
    @AppStorage("botKick") var kick = false
    @AppStorage("botTwitch") var twitch = false
    @AppStorage("botTestMode") var testMode = false
    @AppStorage("botNotices") var notices = true
    @AppStorage("botThanks") var thanks = true
    @AppStorage("botHideLocation") var hideLocation = false
    @AppStorage("botTimersOn") var timersOn = false
    @AppStorage("botTimers") var rawTimers = "[]"
    @State private var timers: [AppTimer] = []

    var body: some View {
        Form {
            Section {
                Toggle("App bot on Kick", isOn: $kick)
                Toggle("App bot on Twitch", isOn: $twitch)
                Toggle("Test mode", isOn: $testMode)
                if !bot.status.isEmpty { Text(bot.status).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("Posts only while you are live, never as you. Test mode lets it answer you and your mods (no one else) and post notices while offline, so you can try it from your own chat (timers still wait for live); turn it off when done. Kick: create the bot once in your Kick developer app settings. Twitch: connect a second account below (make it a mod of your channel).")
            }
            Section("Twitch bot account") {
                if bot.twitchBotName.isEmpty {
                    Button("Connect bot account") { bot.connectTwitch() }
                } else {
                    Text("Connected as \(bot.twitchBotName)")
                    Button("Disconnect", role: .destructive) { bot.disconnectTwitch() }
                }
            }
            Section {
                Toggle("Scene notices", isOn: $notices)
                template("BRB starts", "botTplBrbOn")
                template("BRB ends", "botTplBrbOff")
                template("Starting scene", "botTplStartingOn")
                template("Ending scene", "botTplEndingOn")
            } footer: { Text("Empty = don't post.") }
            Section {
                ForEach(["Location", "Speed", "Distance", "Weather", "Battery", "Uptime", "Goal", "Commands"], id: \.self) { c in
                    CommandToggle(name: c)
                }
                Toggle("Hide location", isOn: $hideLocation)
            } header: { Text("Viewer commands") } footer: {
                Text("Once per 30 s per command and platform; mods and you skip that. !location says region and country only. !commands lists the ones switched on.")
            }
            Section {
                Toggle("Thank-yous", isOn: $thanks)
                template("Follow", "botTplFollow")
                template("Sub", "botTplSub")
                template("Gifted subs", "botTplGift")
                template("Raid", "botTplRaid")
                template("Donation", "botTplTip")
            } footer: { Text("{user}, {count} and (donations) {amount}. Empty = don't post.") }
            Section {
                Toggle("Timers", isOn: $timersOn)
                ForEach($timers) { $t in
                    VStack(alignment: .leading) {
                        TextField("Message", text: $t.text)
                        Stepper("Every \(t.minutes) min", value: $t.minutes, in: 5...120, step: 5)
                    }
                }
                .onDelete { timers.remove(atOffsets: $0) }
                Button("Add timer") { timers.append(AppTimer(text: "")) }
            } footer: {
                Text("A timer posts when its interval has passed and at least 5 viewers chatted since its last post; never more than one per 5 min per platform, and not during BRB.")
            }
        }
        .navigationTitle("App bot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { timers = AppTimer.decode(rawTimers) }
        .onChange(of: timers) { _, v in rawTimers = AppTimer.encode(v) }
    }

    /// One editable message; shows the default until it is changed.
    private func template(_ title: String, _ key: String) -> some View {
        TemplateField(title: title, key: key)
    }
}

private struct TemplateField: View {
    let title: String
    @AppStorage private var text: String
    init(title: String, key: String) { self.title = title; _text = AppStorage(wrappedValue: AppBot.defaults[key] ?? "", key) }
    var body: some View { TextField(title, text: $text) }
}

private struct CommandToggle: View {
    let name: String
    @AppStorage private var on: Bool
    init(name: String) { self.name = name; _on = AppStorage(wrappedValue: true, "botCmd" + name) }
    var body: some View { Toggle("!" + name.lowercased(), isOn: $on) }
}
