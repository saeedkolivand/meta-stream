import SwiftUI

/// The inspector's three tabs: what the widget shows, how it looks, where it sits.
enum InspectorTab: String, CaseIterable {
    case content = "Content", style = "Style", position = "Position"
}

/// Settings of the selected layer, one tab at a time (Form sections; the caller wraps them in a Form). Edits mutate the
/// editor's working copy (the canvas follows live); the editor saves them debounced, and slider releases call `commit`
/// to save at once. Content holds the data, text and design pickers; Style the fonts, colours, sizes and look toggles
/// (WidgetStyleSections.swift); Position the anchor grid, size, order and delete (WidgetPositionSections.swift).
/// Styles are read and written by their string keys, not struct fields: the keys are the stored contract, so this
/// stays correct whatever numeric type a style field uses. Missing keys read the style's defaults.
struct WidgetInspectorView: View {
    @Binding var layer: OverlayLayer
    let tab: InspectorTab
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
        case .nowplaying: NowPlayingWidgetStyle().data
        case .qr: QRWidgetStyle().data
        case .text: TextWidgetStyle().data
        default: [:]
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .content: contentTab
            case .style: styleTab
            case .position: positionTab
            }
        }
    }

    // MARK: content

    @ViewBuilder private var contentTab: some View {
        switch layer.type {
        case .chat: chatContent
        case .alerts: alertContent
        case .events: eventContent
        case .text: textContent
        case .goal: goalContent
        case .nowplaying: nowPlayingContent
        case .qr: qrContent
        case .browser: webContent
        case .image, .media, .color, .slideshow: noOptions("Nothing to set here. Use Position to move and resize it.")
        }
    }

    func noOptions(_ text: String) -> some View {
        Section { Text(text).foregroundStyle(.secondary) }
    }

    @ViewBuilder private var chatContent: some View {
        Section("Chat") {
            slider("Messages", num("maxMessages"), 3...20, format: "%.0f")
            Picker("Fade out after", selection: int("fadeSeconds")) {
                Text("Never").tag(0)
                ForEach([10, 20, 30, 60], id: \.self) { Text("\($0) s").tag($0) }
            }
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

    @ViewBuilder private var alertContent: some View {
        Section("Alerts") {
            kindToggles
            slider("Show for", num("holdSeconds"), 3...15, format: "%.0f s")
        }
        Section {
            DonationAlertPreview(style: AlertWidgetStyle(layer.data)).listRowInsets(EdgeInsets())
                .fullScreenPreview { DonationAlertPreview(style: AlertWidgetStyle(layer.data)) }
        }
        Section {
            Picker("Donation style", selection: str("design")) {
                ForEach(DonationAlertKind.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            if raw("design") != "island" {
                designColor("designAccent", "Colour")
                if raw("design") == "neon" { designColor("designSecond", "Second colour") }
                Picker("Speed", selection: str("designSpeed")) {
                    Text("Slow").tag("slow")
                    Text("Normal").tag("normal")
                    Text("Quick").tag("quick")
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Donations")
        } footer: {
            Text("Donations (tips, Bits, KICKs) use this design; follows, subs and raids keep the Island banner. Donation designs play where the Alerts widget sits; drag and resize it to move them.")
        }
    }

    /// "Design colour" on = 0, the design's own colour; off shows a picker.
    @ViewBuilder private func designColor(_ key: String, _ title: String) -> some View {
        let own = Binding<Bool> {
            (UInt32(raw(key) ?? "") ?? 0) == 0
        } set: { layer.data[key] = $0 ? "0" : String(0xFFFF_FFFF as UInt32) }
        Toggle("Design colour", isOn: own)
        if !own.wrappedValue { ColorPicker(title, selection: color(key)) }
    }

    @ViewBuilder private var eventContent: some View {
        Section("Event list") {
            kindToggles
            slider("Entries", num("maxEvents"), 3...10, format: "%.0f")
        }
    }

    @ViewBuilder private var goalContent: some View {
        Section {
            GoalPreview(style: GoalWidgetStyle(layer.data)).listRowInsets(EdgeInsets())
                .fullScreenPreview { GoalPreview(style: GoalWidgetStyle(layer.data)) }
        }
        Section {
            Picker("Design", selection: str("design")) {
                Text("Bar").tag("bar")
                Text("Liquid").tag("liquid")
                Text("Road trip").tag("road")
                Text("Segments").tag("segments")
                Text("Hairline").tag("hairline")
                Text("Island pill").tag("island")
                Text("Mini ring").tag("miniring")
                Text("Dot wave").tag("dots")
                Text("Spark").tag("spark")
            }
            Toggle("Show percent", isOn: flag("showPercent"))
            Toggle("Show other currencies", isOn: flag("showOther"))
        } header: { Text("Goal") } footer: {
            Text("Title, target and currency are set in Settings.")
        }
    }

    @ViewBuilder private var nowPlayingContent: some View {
        Section {
            Picker("Design", selection: str("design")) {
                ForEach(NowPlayingDesign.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            if raw("design") == NowPlayingDesign.popup.rawValue {
                slider("Show for", num("popupSeconds"), 2...30, format: "%.0f s")
            }
        } header: { Text("Now playing") } footer: {
            Text("Connect your account in Settings › Spotify.")
        }
    }

    private var kindToggles: some View {
        ForEach([("Follows", "follow"), ("Subscriptions", "subscribe"), ("Raids", "raid"), ("Tips", "tip"), ("Cheers", "cheer")], id: \.1) {
            Toggle($0.0, isOn: flag($0.1))
        }
    }

    @ViewBuilder private var textContent: some View {
        Section {
            TextField("Text", text: str("text"), axis: .vertical)
            Menu("Insert live value") {
                ForEach(WidgetVariables.tokens, id: \.token) { t in
                    Button(t.label) { layer.data["text"] = (layer.data["text"] ?? "") + t.token }
                }
            }
            Menu("Icon") {
                ForEach(TextRuns.palette, id: \.self) { name in
                    Button { layer.data["text"] = (layer.data["text"] ?? "") + "{i:\(name)}" } label: { Label(name, systemImage: name) }
                }
            }
            Toggle("Rotate lines", isOn: flag("rotate"))
            slider("Seconds per line", num("rotateSeconds"), 3...15, format: "%.0f")
        } header: { Text("Text") } footer: {
            Text("Values like {time} or {viewers} update on stream every second. Speed, distance, city and weather ask for location "
                 + "access. Rotate lines shows one line at a time, for socials. "
                 + "Icon adds an {i:symbol} token that draws an SF Symbol inline.")
        }
    }

    @ViewBuilder private var qrContent: some View {
        Section("QR code") {
            TextField("Text or link", text: str("text")).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("Caption", text: str("caption"))
        }
    }

    @ViewBuilder private var webContent: some View {
        Section {
            TextField("Link", text: str("url")).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
        } header: { Text("Web widget") } footer: {
            Text("The link can carry account tokens. It stays on this device, and is never logged.")
        }
    }

    // MARK: shared controls and bindings (internal: the Style and Position tabs live in extensions in other files)

    var fontPicker: some View {
        Picker("Font", selection: str("face")) {
            ForEach(Array(WidgetFonts.faces.enumerated()), id: \.offset) { Text($0.element.label).tag($0.element.id) }
        }
    }

    func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range) { editing in if !editing { commit() } }
        }
    }

    func raw(_ key: String) -> String? { layer.data[key] ?? defaults[key] }

    func str(_ key: String) -> Binding<String> {
        Binding { raw(key) ?? "" } set: { layer.data[key] = $0 }
    }

    func num(_ key: String) -> Binding<Double> {
        Binding { Double(raw(key) ?? "") ?? 0 } set: { layer.data[key] = String(Int($0.rounded())) }
    }

    func int(_ key: String) -> Binding<Int> {
        Binding { Int(Double(raw(key) ?? "") ?? 0) } set: { layer.data[key] = String($0) }
    }

    func flag(_ key: String) -> Binding<Bool> {
        Binding { raw(key) == "true" } set: { layer.data[key] = $0 ? "true" : "false" }
    }

    /// ARGB UInt32 in the data, a SwiftUI Color in the picker.
    func color(_ key: String) -> Binding<Color> {
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
