import SwiftUI

/// Settings › App bot › Messages: what the bot posts for scene changes, viewer donate questions and thank-yous.
struct AppBotMessagesView: View {
    @AppStorage("botNotices") var notices = true
    @AppStorage("botThanks") var thanks = true

    var body: some View {
        Form {
            Section {
                Toggle("Scene notices", isOn: $notices)
                TemplateField(title: "BRB starts", key: "botTplBrbOn")
                TemplateField(title: "BRB ends", key: "botTplBrbOff")
                TemplateField(title: "Starting scene", key: "botTplStartingOn")
                TemplateField(title: "Starting ends (live)", key: "botTplStartingOff")
                TemplateField(title: "Ending scene", key: "botTplEndingOn")
            } footer: {
                Text("Empty = don't post. With no scene set to the BRB role, a weak connection only posts the BRB lines "
                     + "and the stream stays on camera. The BRB line goes out at most once per 2 min.")
            }
            Section {
                TemplateField(title: "Donate answer", key: "botTplDonate")
            } header: { Text("Viewer commands") } footer: {
                Text("!donate (also !tip, !support, !donation) answers with this: {title}, {total}, {target}, {percent} and {url}.")
            }
            Section {
                Toggle("Thank-yous", isOn: $thanks)
                TemplateField(title: "Follow", key: "botTplFollow")
                TemplateField(title: "Sub", key: "botTplSub")
                TemplateField(title: "Gifted subs", key: "botTplGift")
                TemplateField(title: "Raid", key: "botTplRaid")
                TemplateField(title: "Donation", key: "botTplTip")
            } footer: { Text("{user}, {count} and (donations) {amount}. Empty = don't post.") }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › App bot › Timers: repeating messages while live.
struct AppBotTimersView: View {
    @AppStorage("botTimersOn") var timersOn = false
    @AppStorage("botTimers") var rawTimers = "[]"
    @State private var timers: [AppTimer] = []

    var body: some View {
        Form {
            Section {
                Toggle("Timers", isOn: $timersOn)
                ForEach($timers) { $timer in
                    VStack(alignment: .leading) {
                        TextField("Message", text: $timer.text)
                        Stepper("Every \(timer.minutes) min", value: $timer.minutes, in: 5...120, step: 5)
                    }
                }
                .onDelete { timers.remove(atOffsets: $0) }
                Button("Add timer") { timers.append(AppTimer(text: "")) }
            } footer: {
                Text("A timer posts when its interval has passed and at least 5 viewers chatted since its last post; "
                     + "never more than one per 5 min per platform, and not during BRB. Timers wait for live, even in test mode.")
            }
        }
        .navigationTitle("Timers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { timers = AppTimer.decode(rawTimers) }
        .onChange(of: timers) { _, new in rawTimers = AppTimer.encode(new) }
    }
}

/// One editable message; shows the default until it is changed.
struct TemplateField: View {
    let title: String
    @AppStorage private var text: String
    init(title: String, key: String) { self.title = title; _text = AppStorage(wrappedValue: AppBot.defaults[key] ?? "", key) }
    var body: some View { TextField(title, text: $text) }
}
