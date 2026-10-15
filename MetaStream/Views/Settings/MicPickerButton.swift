import AVFoundation
import AVKit
import SwiftUI

/// "Microphone and mic mode…" row: opens the system input picker (iOS 26), which also offers
/// Voice Isolation / Wide Spectrum / Standard for the selected mic.
struct MicPickerButton: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        // The picker lists inputs only under a record category -- same options as Streamer.refreshMics.
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
        let picker = AVInputPickerInteraction()
        picker.delegate = context.coordinator
        var config = UIButton.Configuration.plain()
        config.title = "Microphone and mic mode…"
        config.baseForegroundColor = .tintColor
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addInteraction(picker)
        button.addAction(UIAction { _ in picker.present() }, for: .touchUpInside)
        context.coordinator.picker = picker   // the button doesn't retain the interaction's delegate chain on its own
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}

    final class Coordinator: NSObject, AVInputPickerInteraction.Delegate {
        var picker: AVInputPickerInteraction?

        // iOS 26 can revert the choice; log what actually stuck.
        func inputPickerInteractionDidEndDismissing(_ inputPickerInteraction: AVInputPickerInteraction) {
            let s = AVAudioSession.sharedInstance()
            applog("stream", "mic picker closed: input=\(s.preferredInput?.portName ?? "default") mode=\(AVCaptureDevice.preferredMicrophoneMode.rawValue)")
        }
    }
}
