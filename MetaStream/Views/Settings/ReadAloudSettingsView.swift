import AVFoundation
import SwiftUI

struct ReadAloudSettingsView: View {
    @EnvironmentObject var platforms: Platforms
    @AppStorage("chatOrigin") var chatOrigin = "kick"
    @AppStorage("chatChannel") var chatChannel = ""
    @AppStorage("ttsVoiceID") var ttsVoiceID = ""
    @AppStorage("ttsMessagesOn") var ttsMessagesOn = true
    @AppStorage("ttsTipsOn") var ttsTipsOn = true
    @AppStorage("ttsFollowsOn") var ttsFollowsOn = true
    @AppStorage("ttsSubsOn") var ttsSubsOn = true
    @AppStorage("ttsRaidsOn") var ttsRaidsOn = true
    @AppStorage("ttsRate") var ttsRate = 0.5
    @AppStorage("ttsMinTipCents") var ttsMinTipCents = 0
    @AppStorage("ttsIgnore") var ttsIgnore = ""
    @AppStorage("ttsBlocked") var ttsBlocked = ""
    @AppStorage("aiModeration") var aiModeration = true
    @AppStorage("voiceKick") var voiceKick = true
    @AppStorage("voiceTwitch") var voiceTwitch = true
    @AppStorage("voiceYouTube") var voiceYouTube = true

    init() { ChatOriginKey.migrate() }

    /// Every voice actually installed on THIS device/iOS version, grouped and sorted by language --
    /// AVSpeechSynthesisVoice.speechVoices() enumerates the real set rather than a hardcoded list, so a
    /// language iOS adds later just shows up. Computed once (static let): the installed set doesn't change
    /// mid-session and speechVoices() isn't cheap enough to call on every body evaluation.
    private static let voiceGroups: [(language: String, voices: [AVSpeechSynthesisVoice])] = {
        let grouped = Dictionary(grouping: AVSpeechSynthesisVoice.speechVoices(), by: \.language)
        return grouped.keys.sorted().map { lang in
            (lang, grouped[lang]!.sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) })   // best first
        }
    }()

    private static func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return " (Premium)"
        case .enhanced: return " (Enhanced)"
        default: return ""
        }
    }

    private static func languageLabel(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    var body: some View {
        Form {
            Section("Chat") {
                Picker("Chat origin", selection: $chatOrigin) { Text("Kick").tag("kick"); Text("Twitch").tag("twitch") }
                TextField("Channel name", text: $chatChannel).textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            Section {
                Picker("Voice", selection: $ttsVoiceID) {
                    Text("Best installed").tag("")
                    ForEach(Self.voiceGroups, id: \.language) { group in
                        Section(Self.languageLabel(group.language)) {
                            ForEach(group.voices, id: \.identifier) { voice in
                                Text(voice.name + Self.qualityLabel(voice.quality)).tag(voice.identifier)
                            }
                        }
                    }
                }
                // Its own page, not a pop-up menu: a menu of hundreds of voices is re-presented (scroll lost) each time
                // the screen refreshes for platform updates.
                .pickerStyle(.navigationLink)
            } footer: {
                Text("Premium voices sound the most human. Download one (e.g. Ava or Zoe, Premium) in Settings → Accessibility → "
                     + "Read & Speak (Spoken Content) → Voices, then reopen this app. Best installed picks it automatically.")
            }

            Section {
                Toggle("AI moderation (English)", isOn: $aiModeration).disabled(!ChatModerator.available)
            } footer: {
                Text("Uses Apple Intelligence on this device to hide hateful or harassing English messages from stream and speech. "
                     + "Held up to 1.5 s for review." + (ChatModerator.available ? "" : " Not available on this device."))
            }

            Section {
                TextField("Names, e.g. nightbot, spammer123", text: $ttsIgnore)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Blocked words, comma separated", text: $ttsBlocked)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("Don't read") } footer: {
                Text("Bots (names ending in bot, StreamElements, BotRix, Kicklet...) and !commands are skipped automatically. "
                     + "Messages with a slur, \"kys\" or a blocked word aren't read, even disguised as n1gg3r or n i g g e r; "
                     + "a name containing one is read as \"someone\". The same messages and names never show in on-stream chat, "
                     + "alert or event widgets. Add words in any language, Persian included.")
            }

            Section {
                Toggle("Chat messages", isOn: $ttsMessagesOn)
                Toggle("Tips and bits", isOn: $ttsTipsOn)
                Toggle("Follows", isOn: $ttsFollowsOn)
                Toggle("Subscriptions", isOn: $ttsSubsOn)
                Toggle("Raids", isOn: $ttsRaidsOn)
                VStack(alignment: .leading) {
                    Text("Speed").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $ttsRate, in: 0.35...0.65)
                }
                Stepper("Read tips from $\(ttsMinTipCents / 100)", value: $ttsMinTipCents, in: 0...5000, step: 100)
                Toggle("Kick chat", isOn: $voiceKick)
                Toggle("Twitch chat", isOn: $voiceTwitch)
                Toggle("YouTube chat", isOn: $voiceYouTube)
                if !platforms.twitchMissingScopeFeatures.isEmpty, platforms.twitchConnected {
                    Text("Reconnect Twitch in Manage to enable \(platforms.twitchMissingScopeFeatures.joined(separator: ", ")).")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Chat is spoken through whatever is playing audio, so the glasses' open-ear speakers when they are connected. The tts pill on the live screen silences chat and alerts; stream warnings such as a dropped connection always speak.\n\nWith the glasses microphone selected, the open-ear speakers can bleed back into your audio. Use the phone microphone if viewers hear an echo.")
            }
        }
        .navigationTitle("Chat & read aloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
