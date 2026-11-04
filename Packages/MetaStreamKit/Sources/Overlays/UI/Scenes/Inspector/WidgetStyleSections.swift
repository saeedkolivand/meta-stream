import SwiftUI

/// The Style tab: fonts, colours, box sizes and the look toggles of each widget type.
extension WidgetInspectorView {
    @ViewBuilder var styleTab: some View {
        switch layer.type {
        case .chat: chatStyle
        case .alerts: alertStyle
        case .events: eventStyle
        case .text: textStyle
        case .goal: goalStyle
        case .nowplaying: nowPlayingStyle
        case .qr: qrStyle
        case .browser: webStyle
        case .image, .media, .color, .slideshow: noOptions("Nothing to style here. Use Position to move and resize it.")
        }
    }

    @ViewBuilder private var chatStyle: some View {
        Section("Text") {
            fontPicker
            slider("Font size", num("fontSize"), 14...72, format: "%.0f")
            ColorPicker("Text color", selection: color("textColor"))
        }
        Section("Box") {
            slider("Box width", num("width"), 300...1200, format: "%.0f")
            slider("Box height", num("height"), 200...1200, format: "%.0f")
            ColorPicker("Background color", selection: color("backgroundColor"))
        }
        Section("Look") {
            ForEach([("Background", "background"), ("Shadow", "shadow"), ("Bold", "bold"), ("Badges", "badges"),
                     ("Platform dot", "platform"), ("Viewer name colors", "senderColors")], id: \.1) { Toggle($0.0, isOn: flag($0.1)) }
        }
    }

    @ViewBuilder private var alertStyle: some View {
        Section("Alerts") {
            fontPicker
            slider("Font size", num("fontSize"), 20...80, format: "%.0f")
            ColorPicker("Accent color", selection: color("accentColor"))
            ColorPicker("Text color", selection: color("textColor"))
        }
    }

    @ViewBuilder private var eventStyle: some View {
        Section("Event list") {
            fontPicker
            slider("Font size", num("fontSize"), 16...48, format: "%.0f")
            slider("Box width", num("width"), 300...900, format: "%.0f")
            slider("Box height", num("height"), 200...900, format: "%.0f")
            Toggle("Background", isOn: flag("background"))
            ColorPicker("Background color", selection: color("backgroundColor"))
            ColorPicker("Text color", selection: color("textColor"))
        }
    }

    @ViewBuilder private var goalStyle: some View {
        Section("Goal") {
            fontPicker
            slider("Font size", num("fontSize"), 16...64, format: "%.0f")
            if raw("design") == "bar" {   // the other designs have a fixed size; scale them with Size
                slider("Box width", num("width"), 300...1200, format: "%.0f")
                slider("Box height", num("height"), 80...300, format: "%.0f")
            }
            Toggle("Background", isOn: flag("background"))
            ColorPicker("Bar color", selection: color("barColor"))
            ColorPicker("Track color", selection: color("trackColor"))
            ColorPicker("Text color", selection: color("textColor"))
            ColorPicker("Background color", selection: color("backgroundColor"))
        }
    }

    @ViewBuilder private var nowPlayingStyle: some View {
        Section("Now playing") {
            fontPicker
            ColorPicker("Accent color", selection: color("accentColor"))
        }
    }

    @ViewBuilder private var textStyle: some View {
        Section("Text") {
            fontPicker
            slider("Font size", num("size"), 16...200, format: "%.0f")
            Toggle("Bold", isOn: flag("bold"))
            Toggle("Shadow", isOn: flag("shadow"))
            Toggle("Background", isOn: flag("background"))
            ColorPicker("Text color", selection: color("color"))
            ColorPicker("Background color", selection: color("backgroundColor"))
        }
    }

    @ViewBuilder private var qrStyle: some View {
        Section("QR code") {
            fontPicker
            ColorPicker("Code color", selection: color("foreground"))
            ColorPicker("Background color", selection: color("background"))
        }
    }

    @ViewBuilder private var webStyle: some View {
        Section("Page size") {
            slider("Page width", num("width"), 200...1920, format: "%.0f")
            slider("Page height", num("height"), 200...1920, format: "%.0f")
        }
    }
}
