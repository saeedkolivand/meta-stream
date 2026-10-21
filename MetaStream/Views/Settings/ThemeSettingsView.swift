import SwiftUI

/// Settings › Theme & story: the colour theme for scene templates and the Instagram story, and the story's layout.
struct ThemeSettingsView: View {
    @AppStorage("colorTheme") private var theme = ColorTheme.kick
    @AppStorage("igStoryTemplate") private var template = StoryTemplate.minimal

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(ColorTheme.allCases) { row($0).tag($0) }
                }
                .pickerStyle(.inline).labelsHidden()
            } header: { Text("Theme") } footer: {
                // Templates copy their colours into ordinary layers when added (SceneTemplate.scenes), so a new theme only
                // affects scenes made afterwards.
                Text("The theme colours the scene templates and the Instagram story. Changing it doesn't recolour "
                    + "scenes you already made from a template; re-apply the template for that.")
            }
            Section {
                Picker("Layout", selection: $template) {
                    ForEach(StoryTemplate.allCases) { Text($0.name).tag($0) }
                }
                VStack(spacing: 8) {
                    StoryCard(frame: nil, title: "Walking through Cologne", link: "https://kick.com/yourname",
                              template: template, theme: theme)
                        .scaleEffect(0.5)
                        .frame(width: 180, height: 320)
                    Text("Preview without a stream frame").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } header: { Text("Instagram story") }
        }
        .navigationTitle("Theme & story")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: ColorTheme) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.faName).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 3) {
                ForEach(Array([item.bg, item.surface, item.text, item.muted, item.accent].enumerated()), id: \.offset) { _, argb in
                    Circle().fill(item.color(argb)).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
                }
            }
        }
    }
}
