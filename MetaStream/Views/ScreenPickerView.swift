import ReplayKit
import SwiftUI

/// System broadcast picker pre-pointed at the MetaStreamScreen extension: one tap opens iOS's "Start Broadcast" sheet
/// (it is also how a running broadcast is stopped). iOS offers no API to start one without that tap.
struct ScreenPickerView: UIViewRepresentable {
    var tint: UIColor = .black

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        v.preferredExtension = "com.saeedkolivand.metastream.Screen"
        v.showsMicrophoneButton = false   // no screen audio (adr/0003); the mic is the stream's own
        v.tintColor = tint
        return v
    }

    func updateUIView(_ v: RPSystemBroadcastPickerView, context: Context) { v.tintColor = tint }
}

/// Round button next to the source menu while Screen is the video source: white = start/stop the broadcast, green = broadcasting.
struct ScreenButton: View {
    @ObservedObject var screen: ScreenSource
    var size: CGFloat

    var body: some View {
        ScreenPickerView(tint: screen.screenLive ? .white : .black)
            .frame(width: size, height: size)
            .background(screen.screenLive ? Color.green : Color.white, in: Circle())
            .accessibilityLabel(screen.screenLive ? "Stop screen broadcast" : "Start screen broadcast")
    }
}
