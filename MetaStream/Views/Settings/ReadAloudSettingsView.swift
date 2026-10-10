import AVFoundation
import SwiftUI

struct ReadAloudSettingsView: View {
    @EnvironmentObject var platforms: Platforms
    @AppStorage("ttsVoiceID") var ttsVoiceID = ""
    @AppStorage("ttsMessagesOn") var ttsMessagesOn = true
    @AppStorage("ttsTipsOn") var ttsTipsOn = true
    @AppStorage("ttsFollowsOn") var ttsFollowsOn = true
    @AppStorage("ttsSubsOn") var ttsSubsOn = true
    @AppStorage("ttsRaidsOn") var ttsRaidsOn = true
    @AppStorage("ttsRate") var ttsRate = 0.5
    @AppStorage("ttsMinTipCents") var ttsMinTipCents = 0
    @AppStorage("voiceKick") var voiceKick = true
    @AppStorage("voiceTwitch") var voiceTwitch = true
    @AppStorage("voiceYouTube") var voiceYouTube = true

    /// Every voice actually installed on THIS device/iOS version, grouped and sorted by language --
    /// AVSpeechSynthesisVoice.speechVoices() enumerates the real set rather than a hardcoded list, so a
    /// language iOS adds later just shows up. Computed once (static let): the installed set doesn't change
    /// mid-session and speechVoices() isn't cheap enough to call on every body evaluation.
    private static let voiceGroups: [(language: String, voices: [AVSpeechSynthesisVoice])] = {
        let grouped = Dictionary(grouping: AVSpeechSynthesisVoice.speechVoices(), by: \.language)
        return grouped.keys.sorted().map { lang in (lang, grouped[lang]!.sorted { $0.name < $1.name }) }
    }()

    private static func languageLabel(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    var body: some View {
        Form {
            Section {
                Picker("Voice", selection: $ttsVoiceID) {
                    Text("System default").tag("")
                    ForEach(Self.voiceGroups, id: \.language) { group in
                        Section(Self.languageLabel(group.language)) {
                            ForEach(group.voices, id: \.identifier) { voice in
                                Text(voice.name).tag(voice.identifier)
                            }
                        }
                    }
                }
            } footer: {
                Text("Voices installed on this iPhone (Settings → Accessibility → Spoken Content → Voices adds more).")
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
        .navigationTitle("Read aloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
