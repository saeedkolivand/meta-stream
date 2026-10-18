import SwiftUI

/// Settings of the selected layer. Edits mutate the editor's working copy (the canvas follows live); the editor saves
/// them debounced, and slider releases call `commit` to save at once.
/// Styles are read and written by their string keys, not struct fields: the keys are the stored contract, so this
/// stays correct whatever numeric type a style field uses. Missing keys read the style's defaults.
struct WidgetInspectorView: View {
    @Binding var layer: OverlayLayer
    let canMoveForward: Bool
    let canMoveBack: Bool
    let commit: () -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    private var defaults: [String: String] {
        switch layer.type {
        case .chat: ChatWidgetStyle().data
        case .alerts: AlertWidgetStyle().data
        case .events: EventListStyle().data
        case .goal: GoalWidgetStyle().data
        case .qr: QRWidgetStyle().data
        case .text: TextWidgetStyle().data
        default: [:]
        }
    }

    var body: some View {
        Group {
            Section("Layer") {
                TextField("Name", text: $layer.name)
                Toggle("Visible", isOn: $layer.visible)
                slider("Size", sizeBinding, 0.05...4, format: "%.2f×")
                HStack {
                    Button { move(1) } label: { Label("Forward", systemImage: "square.2.layers.3d.top.filled") }.disabled(!canMoveForward)
                    Spacer()
                    Button { move(-1) } label: { Label("Back", systemImage: "square.2.layers.3d.bottom.filled") }.disabled(!canMoveBack)
                }
                .buttonStyle(.borderless)
                Button("Delete layer", role: .destructive, action: delete)
            }
            switch layer.type {
            case .chat: chatSection
            case .alerts: alertSection
            case .events: eventSection
            case .text: textSection
            case .goal: goalSection
            case .qr: qrSection
            case .browser: webSection
            case .image, .media, .color, .slideshow: EmptyView()
            }
        }
    }

    // MARK: per type

    @ViewBuilder private var chatSection: some View {
        Section("Chat") {
            fontPicker
            slider("Font size", num("fontSize"), 14...72, format: "%.0f")
            slider("Messages", num("maxMessages"), 3...20, format: "%.0f")
            Picker("Fade out after", selection: int("fadeSeconds")) {
                Text("Never").tag(0)
                ForEach([10, 20, 30, 60], id: \.self) { Text("\($0) s").tag($0) }
            }
            slider("Box width", num("width"), 300...1200, format: "%.0f")
            slider("Box height", num("height"), 200...1200, format: "%.0f")
        }
        Section("Look") {
            ForEach([("Background", "background"), ("Shadow", "shadow"), ("Bold", "bold"), ("Badges", "badges"),
                     ("Platform dot", "platform"), ("Viewer name colors", "senderColors")], id: \.1) { Toggle($0.0, isOn: flag($0.1)) }
            ColorPicker("Text color", selection: color("textColor"))
            ColorPicker("Background color", selection: color("backgroundColor"))
        }
        Section {
            Toggle("Hide !commands", isOn: flag("hideCommands"))
            Toggle("Hide bots", isOn: flag("hideBots"))
            Toggle("Show follows, subs and tips", isOn: flag("showEvents"))
            TextField("Highlight words", text: str("highlight")).autocorrectionDisabled().textInputAutocapitalization(.never)
            ColorPicker("Highlight color", selection: color("highlightColor"))
        } header: { Text("Filters") } footer: {
            Text("Highlight words are comma-separated; the bot list is in Settings → Chat bots. A message with a highlight word, or your channel name, gets a border.")
        }
    }

    @ViewBuilder private var alertSection: some View {
        Section("Alerts") {
            kindToggles
            slider("Show for", num("holdSeconds"), 3...15, format: "%.0f s")
            fontPicker
            slider("Font size", num("fontSize"), 20...80, format: "%.0f")
            ColorPicker("Accent color", selection: color("accentColor"))
            ColorPicker("Text color", selection: color("textColor"))
        }
    }

    @ViewBuilder private var eventSection: some View {
        Section("Event list") {
            kindToggles
            slider("Entries", num("maxEvents"), 3...10, format: "%.0f")
            fontPicker
            slider("Font size", num("fontSize"), 16...48, format: "%.0f")
            slider("Box width", num("width"), 300...900, format: "%.0f")
            slider("Box height", num("height"), 200...900, format: "%.0f")
            Toggle("Background", isOn: flag("background"))
            ColorPicker("Background color", selection: color("backgroundColor"))
            ColorPicker("Text color", selection: color("textColor"))
        }
    }

    @ViewBuilder private var goalSection: some View {
        Section {
            fontPicker
            slider("Font size", num("fontSize"), 16...64, format: "%.0f")
            slider("Box width", num("width"), 300...1200, format: "%.0f")
            slider("Box height", num("height"), 80...300, format: "%.0f")
            Toggle("Show percent", isOn: flag("showPercent"))
            Toggle("Show other currencies", isOn: flag("showOther"))
            Toggle("Background", isOn: flag("background"))
            ColorPicker("Bar color", selection: color("barColor"))
            ColorPicker("Track color", selection: color("trackColor"))
            ColorPicker("Text color", selection: color("textColor"))
            ColorPicker("Background color", selection: color("backgroundColor"))
        } header: { Text("Goal") } footer: {
            Text("Title, target and currency are set in Settings.")
        }
    }

    private var kindToggles: some View {
        ForEach([("Follows", "follow"), ("Subscriptions", "subscribe"), ("Raids", "raid"), ("Tips", "tip"), ("Cheers", "cheer")], id: \.1) {
            Toggle($0.0, isOn: flag($0.1))
        }
    }

    @ViewBuilder private var textSection: some View {
        Section {
            TextField("Text", text: str("text"), axis: .vertical)
            Menu("Insert live value") {
                ForEach(WidgetVariables.tokens, id: \.token) { t in
                    Button(t.label) { layer.data["text"] = (layer.data["text"] ?? "") + t.token }
                }
            }
            fontPicker
            slider("Font size", num("size"), 16...200, format: "%.0f")
            Toggle("Bold", isOn: flag("bold"))
            Toggle("Shadow", isOn: flag("shadow"))
            Toggle("Background", isOn: flag("background"))
            Toggle("Rotate lines", isOn: flag("rotate"))
            slider("Seconds per line", num("rotateSeconds"), 3...15, format: "%.0f")
            ColorPicker("Text color", selection: color("color"))
            ColorPicker("Background color", selection: color("backgroundColor"))
        } header: { Text("Text") } footer: {
            Text("Values like {time} or {viewers} update on stream every second. Speed, distance, city and weather ask for location "
                 + "access. Rotate lines shows one line at a time, for socials.")
        }
    }

    @ViewBuilder private var qrSection: some View {
        Section("QR code") {
            TextField("Text or link", text: str("text")).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("Caption", text: str("caption"))
            fontPicker
            ColorPicker("Code color", selection: color("foreground"))
            ColorPicker("Background color", selection: color("background"))
        }
    }

    @ViewBuilder private var webSection: some View {
        Section {
            TextField("Link", text: str("url")).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            slider("Page width", num("width"), 200...1920, format: "%.0f")
            slider("Page height", num("height"), 200...1920, format: "%.0f")
        } header: { Text("Web widget") } footer: {
            Text("The link can carry account tokens. It stays on this device, and is never logged.")
        }
    }

    private var fontPicker: some View {
        Picker("Font", selection: str("face")) {
            ForEach(Array(WidgetFonts.faces.enumerated()), id: \.offset) { Text($0.element.label).tag($0.element.id) }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range) { editing in if !editing { commit() } }
        }
    }

    // MARK: bindings

    private var sizeBinding: Binding<Double> {
        Binding {
            Double(layer.layout?.scale ?? layer.sx)
        } set: { v in
            if layer.layout != nil {
                layer.layout?.scale = CGFloat(v)
            } else {
                // OBS layers: scale both axes by the same ratio so the aspect holds
                let r = layer.sx > 0 ? CGFloat(v) / layer.sx : 1
                layer.sx *= r; layer.sy *= r
            }
        }
    }

    private func raw(_ key: String) -> String? { layer.data[key] ?? defaults[key] }

    private func str(_ key: String) -> Binding<String> {
        Binding { raw(key) ?? "" } set: { layer.data[key] = $0 }
    }

    private func num(_ key: String) -> Binding<Double> {
        Binding { Double(raw(key) ?? "") ?? 0 } set: { layer.data[key] = String(Int($0.rounded())) }
    }

    private func int(_ key: String) -> Binding<Int> {
        Binding { Int(Double(raw(key) ?? "") ?? 0) } set: { layer.data[key] = String($0) }
    }

    private func flag(_ key: String) -> Binding<Bool> {
        Binding { raw(key) == "true" } set: { layer.data[key] = $0 ? "true" : "false" }
    }

    /// ARGB UInt32 in the data, a SwiftUI Color in the picker.
    private func color(_ key: String) -> Binding<Color> {
        Binding {
            Color(uiColor: OverlayRaster.color(argb: UInt32(raw(key) ?? "") ?? 0xFFFFFFFF))
        } set: { c in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
            layer.data[key] = String(byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b))
        }
    }
}
