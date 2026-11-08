import SwiftUI

/// Settings › Telegram › Post texts: each post's template, its placeholders and a preview. A template left as the
/// built-in one is stored as "" so it keeps following the language setting.
struct PostTextsView: View {
    @AppStorage("telegramLang") private var lang = "fa"
    @State private var kind = LivePostText.Kind.live
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                Picker("Post", selection: $kind) {
                    ForEach(LivePostText.Kind.allCases) { Text($0.title).tag($0) }
                }
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } footer: {
                Text("An empty placeholder hides its line; put optional parts in [ ], like [ · {title}]. Goal, donations, "
                     + "moments and chatters come worded in the post language.")
            }
            if !kind.keys.isEmpty {
                Section("Placeholders") { Text(kind.keys.map { "{\($0)}" }.joined(separator: "  ")).textSelection(.enabled) }
            }
            Section {
                Text(LivePostText.preview(kind, lang: lang, template: text))
            } header: { Text("Preview") } footer: { Text("Made-up values; the real post fills in the stream's.") }
            Section {
                Button("Reset to default", role: .destructive) { text = defaultText }.disabled(text == defaultText)
            }
        }
        .navigationTitle("Post texts")
        .onAppear(perform: load)
        .onChange(of: kind) { load() }
        .onChange(of: text) { UserDefaults.standard.set(text == defaultText ? "" : text, forKey: kind.pref) }
    }

    private var defaultText: String { LivePostText.defaultTemplate(kind, lang) }

    private func load() { text = LivePostText.stored(kind) ?? defaultText }
}
