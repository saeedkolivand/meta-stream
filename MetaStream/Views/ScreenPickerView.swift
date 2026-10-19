import ReplayKit
import SwiftUI

/// iOS's broadcast picker, pre-pointed at the MetaStreamScreen extension. It draws its own glyph at its own size and
/// offset, so it sits invisible behind ScreenButton, which taps its inner button. iOS offers no other way to open the
/// "Start Broadcast" sheet (that sheet is also how a running broadcast is stopped).
@MainActor
final class BroadcastPickerHolder {
    let view: RPSystemBroadcastPickerView = {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        v.preferredExtension = "com.saeedkolivand.metastream.Screen"
        v.showsMicrophoneButton = false   // no screen audio (adr/0003); the mic is the stream's own
        return v
    }()

    func open() {
        (view.subviews.first { $0 is UIButton } as? UIButton)?.sendActions(for: .touchUpInside)
    }
}

struct ScreenPickerView: UIViewRepresentable {
    let holder: BroadcastPickerHolder
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView { holder.view }
    func updateUIView(_ v: RPSystemBroadcastPickerView, context: Context) {}
}

/// Round button next to the source menu while Screen is the video source, styled like its neighbours:
/// white = start the broadcast, green = broadcasting (tap to stop).
struct ScreenButton: View {
    @ObservedObject var screen: ScreenSource
    var size: CGFloat
    @State private var holder = BroadcastPickerHolder()

    var body: some View {
        Button { holder.open() } label: {
            Image(systemName: screen.screenLive ? "stop.fill" : "record.circle")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(screen.screenLive ? .white : .black)
                .frame(width: size, height: size)
                .background(screen.screenLive ? Color.green : Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .background { ScreenPickerView(holder: holder).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false) }
        .accessibilityLabel(screen.screenLive ? "Stop screen broadcast" : "Start screen broadcast")
    }
}
