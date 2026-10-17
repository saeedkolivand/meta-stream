import SwiftUI
import UniformTypeIdentifiers

/// Settings › Scenes & widgets › Stinger: a built-in stinger (drawn live, so it follows these settings) or your own clip.
struct StingerSettingsView: View {
    @EnvironmentObject var platforms: Platforms
    @ObservedObject private var store = OverlayStore.shared
    @State private var style = StingerStyle.load()
    @State private var pickClip = false

    private var kind: StingerKind? { StingerKind(rawValue: store.stingerKind) }

    var body: some View {
        Form {
            Section {
                Picker("Stinger", selection: $store.stingerKind) {
                    ForEach(StingerKind.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    Text("Your video").tag("")
                }
            }
            if let kind {
                Section {
                    StingerPreview(kind: kind, style: style)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text("The scene switches underneath at the moment the screen is fully covered, exactly as on stream.")
                }
                Section("Motion") {
                    VStack(alignment: .leading) {
                        Text("Speed: \(style.speed, specifier: "%.1f")×")
                        Slider(value: $style.speed, in: 0.4...2, step: 0.1)
                    }
                    LabeledContent("Length", value: String(format: "%.1f s", kind.seconds(style)))
                }
                Section("Look") {
                    switch kind {
                    case .lens:
                        ColorPicker("Tally light", selection: argb(\.tally), supportsOpacity: false)
                    case .burn:
                        Picker("Tone", selection: $style.tone) {
                            Text("Warm").tag("warm"); Text("Cool").tag("cool"); Text("Accent").tag("accent")
                        }
                        if style.tone == "accent" { ColorPicker("Accent", selection: argb(\.accent), supportsOpacity: false) }
                    default:
                        ColorPicker("Accent", selection: argb(\.accent), supportsOpacity: false)
                        ColorPicker("Panel", selection: argb(\.ink), supportsOpacity: false)
                    }
                }
                Section("Name") {
                    Toggle("Show name", isOn: $style.showName)
                    if style.showName { TextField("Channel name", text: $style.name) }
                }
            } else {
                Section {
                    Button(store.stingerFile.isEmpty ? "Choose stinger video…" : "Change stinger video…") { pickClip = true }
                        .fileImporter(isPresented: $pickClip, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
                            if case .success(let url) = result { store.setStinger(from: url) }
                        }
                    VStack(alignment: .leading) {
                        Text("Cut point: \(Int(store.stingerCut * 100))% of the clip")
                        Slider(value: $store.stingerCut, in: 0.1...0.9)
                    }
                } footer: {
                    Text("Your clip plays over the change, which happens underneath it at the cut point.")
                }
            }
        }
        .onAppear { if style.name.isEmpty { style.name = platforms.kickUser } }
        .onChange(of: style) { style.save() }
        .navigationTitle("Stinger")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func argb(_ key: WritableKeyPath<StingerStyle, UInt32>) -> Binding<Color> {
        Binding {
            Color(uiColor: OverlayRaster.color(argb: style[keyPath: key]))
        } set: { c in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
            style[keyPath: key] = 0xFF00_0000 | byte(r) << 16 | byte(g) << 8 | byte(b)
        }
    }
}

/// Loops the stinger with the same drawing code the stream uses, over two stand-in scenes that swap at the cut.
private struct StingerPreview: View {
    let kind: StingerKind
    let style: StingerStyle
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            let total = kind.seconds(style)
            let period = total + 1.2                     // a short rest before and after each play
            let elapsed = tl.date.timeIntervalSince(start)
            let t = elapsed.truncatingRemainder(dividingBy: period) - 0.6
            let swapped = (Int(elapsed / period) + (t >= kind.cutSeconds(style) ? 1 : 0)) % 2 == 1
            ZStack {
                swapped ? Color(white: 0.07) : Color(red: 0.29, green: 0.33, blue: 0.38)
                Text(swapped ? "Next scene" : "Current scene")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Canvas { ctx, size in
                    guard t >= 0, t <= total else { return }
                    ctx.withCGContext { cg in
                        UIGraphicsPushContext(cg)
                        kind.draw(cg, size: size, t: t, style: style)
                        UIGraphicsPopContext()
                    }
                }
            }
        }
    }
}
