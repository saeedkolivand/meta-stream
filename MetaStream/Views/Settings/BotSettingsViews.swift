import SwiftUI

/// Settings › Chat commands: the saved !commands behind the chat chips, the ! menu and the Lock Screen buttons.
struct CommandsSettingsView: View {
    @AppStorage("botCommands") var raw = BotCommand.seed
    @AppStorage("lockScreenCommands") var lockScreen = false
    @State private var cmds: [BotCommand] = []

    var body: some View {
        Form {
            Section {
                ForEach($cmds) { $c in
                    VStack(alignment: .leading) {
                        TextField("!command", text: $c.text).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Picker("Send to", selection: $c.destination) {
                            Text("Kick").tag("kick"); Text("Twitch").tag("twitch"); Text("Both").tag("all")
                        }
                        .pickerStyle(.segmented)
                        Toggle("Lock Screen", isOn: $c.lockScreen)
                    }
                }
                .onDelete { cmds.remove(atOffsets: $0) }
                .onMove { cmds.move(fromOffsets: $0, toOffset: $1) }
                Button("Add command") { cmds.append(BotCommand(text: "!", destination: "all")) }
            } footer: {
                Text("Sent as your own account, so bots that obey only the broadcaster accept them. These are examples; check your bot's dashboard for its exact commands. Tap Edit to reorder.")
            }
            Section {
                Toggle("Commands on Lock Screen", isOn: $lockScreen)
            } footer: {
                Text("Shows up to 3 commands marked Lock Screen as buttons on the live card. A tap in your pocket could fire one.")
            }
            KickSessionSection()
        }
        .navigationTitle("Chat commands")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { cmds = BotCommand.decode(raw) }
        .onChange(of: cmds) { _, v in raw = BotCommand.encode(v) }
    }
}

/// Settings › Chat bots: who counts as a bot, and which bot messages are read aloud.
struct BotsSettingsView: View {
    @AppStorage("botNames") var names = BotList.defaultNames
    @AppStorage("botReadMode") var mode = "triggers"
    @AppStorage("botTriggers") var triggers = BotList.defaultTriggers

    var body: some View {
        Form {
            Section {
                TextField("Bot names", text: $names, axis: .vertical).autocorrectionDisabled().textInputAutocapitalization(.never)
            } header: { Text("Bots") } footer: {
                Text("Comma-separated. Names ending in “bot” always count. Bots are hidden from stream chat widgets when Hide bots is on.")
            }
            Section {
                Picker("Read bot messages", selection: $mode) {
                    Text("Never").tag("off"); Text("Announcements only").tag("triggers"); Text("All").tag("all")
                }
                TextField("Trigger words", text: $triggers).autocorrectionDisabled().textInputAutocapitalization(.never)
            } header: { Text("Announcements") } footer: {
                Text("A bot message with a trigger word (whole word, comma-separated) is an announcement: it buzzes your phone and is highlighted in chat, whatever the read setting.")
            }
        }
        .navigationTitle("Chat bots")
        .navigationBarTitleDisplayMode(.inline)
    }
}
