import CoreUI
import Reach
import SwiftUI

/// Settings › Theme & story: the colour theme for scene templates and the Instagram story, and the story's layout.
struct ThemeSettingsView: View {
    @AppStorage("colorTheme") private var theme = ColorTheme.kick
    @AppStorage("igStoryTemplate") private var template = StoryTemplate.minimal
    @AppStorage("igStoryLive") private var liveLabel = ""
    @AppStorage("igStorySoon") private var soonLabel = ""
    @AppStorage("igStoryTitle") private var storyTitle = ""
    @AppStorage("igStoryCaption") private var caption = ""

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
                TextField("Live label", text: $liveLabel, prompt: Text("Live label (default LIVE)"))
                TextField("Live soon label", text: $soonLabel, prompt: Text("Live soon label (default LIVE SOON)"))
                TextField("Title", text: $storyTitle, prompt: Text("Title (default: the Kick title)"))
                TextField("Caption", text: $caption, prompt: Text("Caption under the title"))
                VStack(spacing: 8) {
                    StoryCard(frame: nil, title: "Walking through Cologne", link: "https://kick.com/yourname",
                              template: template, theme: theme,
                              words: StoryText(live: liveLabel, soon: soonLabel, title: storyTitle, caption: caption))
                        .scaleEffect(0.5)
                        .frame(width: 180, height: 320)
                    Text("Preview without a stream frame").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Button("Test share to Instagram") { Task { await InstagramStory.shareTest() } }
                    .disabled(!InstagramStory.available)
            } header: { Text("Instagram story") } footer: {
                Text("Empty texts keep the layout's own wording. " + (InstagramStory.available
                     ? "Test share opens Instagram with this card, without going live; add the Link sticker there."
                     : "Sharing needs Instagram installed and a Meta app ID in the build."))
            }
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
