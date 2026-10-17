import SwiftUI
import UniformTypeIdentifiers

struct AudioSettingsView: View {
    @EnvironmentObject var streamer: Streamer
    @AppStorage("micUID") var micUID = ""
    @AppStorage("volMic") var volMic = 1.0
    @AppStorage("volAlert") var volAlert = 1.0
    @AppStorage("volClip") var volClip = 1.0
    @AppStorage("volSound") var volSound = 1.0
    @AppStorage("alertSound") var alertSound = ""      // file in Documents/sounds; "" = built-in chime
    @AppStorage("sounds") var soundsRaw = "[]"          // soundboard, JSON [Sound]
    @State private var sounds: [Sound] = []
    @State private var importing = false
    @State private var importingForAlert = false

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $micUID) {
                    Text("Default").tag("")
                    ForEach(streamer.mics) { Text($0.name).tag($0.id) }
                }
                Toggle("Mute microphone", isOn: Binding(get: { streamer.muted }, set: { streamer.setMuted($0) }))
            }
            Section {
                MicPickerButton().frame(height: 44)
            } footer: {
                Text("Voice Isolation cuts road and wind noise.")
            }
            Section {
                slider("Microphone", $volMic)
                slider("Alert sounds", $volAlert)
                slider("Clip audio", $volClip)
                slider("Sounds", $volSound)
            } header: { Text("Mix volume") } footer: {
                Text("The mix is what viewers hear. Alert sounds, clip audio and sounds play on stream only, never through the phone speaker, and a limiter keeps a loud file from drowning your voice. They go quiet while the microphone is muted.")
            }
            Section {
                LabeledContent("Alert sound", value: alertSound.isEmpty ? "Chime" : String(alertSound.dropFirst(9)))
                Button("Choose file…") { importingForAlert = true; importing = true }
                if !alertSound.isEmpty { Button("Use the chime") { alertSound = "" } }
            } header: { Text("Alert sound") }
            Section {
                ForEach($sounds) { $s in TextField("Name", text: $s.name) }
                    .onDelete { offsets in
                        for i in offsets { try? FileManager.default.removeItem(at: Sound.url(sounds[i].file)) }
                        sounds.remove(atOffsets: offsets)
                    }
                Button("Add sound…") { importingForAlert = false; importing = true }
                    .disabled(sounds.count >= Sound.maxCount)
            } header: { Text("Soundboard") } footer: {
                Text("Up to \(Sound.maxCount) short sounds. While live, a music note button appears in the controls; tap a name to play it into the mix. Swipe to delete.")
            }
        }
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { streamer.refreshMics(); sounds = Sound.decode(soundsRaw) }
        .onChange(of: sounds) { _, v in soundsRaw = Sound.encode(v) }
        .onChange(of: [volMic, volAlert, volClip, volSound]) { _, _ in
            SoundMix.shared.applyVolumes()
            Task { await streamer.applyAudioMix() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result, let file = Sound.importFile(url) else { return }
            if importingForAlert {
                if !alertSound.isEmpty { try? FileManager.default.removeItem(at: Sound.url(alertSound)) }
                alertSound = file
            } else {
                sounds.append(Sound(name: url.deletingPathExtension().lastPathComponent, file: file))
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...1)
        }
    }
}
