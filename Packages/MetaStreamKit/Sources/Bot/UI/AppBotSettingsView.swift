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

    var body: some View {
        Form {
            Section {
                Toggle("App bot on Kick", isOn: $kick)
                Toggle("App bot on Twitch", isOn: $twitch)
                Toggle("Test mode", isOn: $testMode)
                if !bot.status.isEmpty { Text(bot.status).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("Posts only while you are live, never as you. Test mode lets it answer you and your mods (no one else) "
                     + "and post notices while offline; turn it off when done.")
            }
            Section {
                if bot.twitchBotName.isEmpty {
                    Button("Connect bot account") { bot.connectTwitch() }
                } else {
                    Text("Connected as \(bot.twitchBotName)")
                    Button("Disconnect", role: .destructive) { bot.disconnectTwitch() }
                }
            } header: { Text("Twitch bot account") } footer: {
                Text("Kick: create the bot once in your Kick developer app settings. Twitch: connect a second account here "
                     + "(make it a mod of your channel).")
            }
            Section {
                ForEach(["Location", "Speed", "Distance", "Weather", "Battery", "Uptime", "Goal", "Donate", "Song", "Commands"],
                        id: \.self) { command in
                    CommandToggle(name: command)
                }
                Toggle("Hide location", isOn: $hideLocation)
            } header: { Text("Viewer commands") } footer: {
                Text("Once per 30 s per command and platform; mods and you skip that. !location says region and country only. "
                     + "!song posts the Spotify song with its link (Settings › Spotify). The !donate answer is in Messages.")
            }
            Section {
                NavigationLink { AppBotMessagesView() } label: { LabeledContent("Messages", value: messagesValue) }
                NavigationLink { AppBotTimersView() } label: { LabeledContent("Timers", value: timersValue) }
            } footer: {
                Text("What the bot posts for scene changes, donate questions and thank-yous, and repeating timers.")
            }
        }
        .navigationTitle("App bot")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var messagesValue: String {
        let count = [notices, thanks].filter { $0 }.count
        return count == 0 ? "Off" : "\(count) on"
    }

    private var timersValue: String {
        let count = AppTimer.decode(rawTimers).count
        return timersOn && count > 0 ? "\(count)" : "Off"
    }
}

private struct CommandToggle: View {
    let name: String
    @AppStorage private var on: Bool
    init(name: String) { self.name = name; _on = AppStorage(wrappedValue: true, "botCmd" + name) }
    var body: some View { Toggle("!" + name.lowercased(), isOn: $on) }
}
