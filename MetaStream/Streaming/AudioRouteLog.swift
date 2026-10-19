// Which microphone the app is really hearing: logged at launch, at go-live and whenever iOS changes the audio route
// (a DJI/USB receiver or Bluetooth mic plugged in or out), so "pull logs" shows what a stream used.
import AVFoundation

enum AudioRouteLog {
    @MainActor private static var observer: NSObjectProtocol?

    @MainActor static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { n in
            let raw = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            log("route changed: \(describe(AVAudioSession.RouteChangeReason(rawValue: raw)))")
        }
        log("at launch")
    }

    /// "mic go live: DJI Mic 3 [USBAudio], 48000 Hz, 2 ch, buffer 23 ms"
    static func log(_ why: String) {
        let s = AVAudioSession.sharedInstance()
        let inputs = s.currentRoute.inputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
        applog("audio", "mic \(why): \(inputs.isEmpty ? "none" : inputs), \(Int(s.sampleRate)) Hz, \(s.inputNumberOfChannels) ch, buffer \(Int((s.ioBufferDuration * 1000).rounded())) ms")
    }

    private static func describe(_ r: AVAudioSession.RouteChangeReason?) -> String {
        switch r {
        case .newDeviceAvailable: "plugged in"
        case .oldDeviceUnavailable: "unplugged"
        case .categoryChange: "category change"
        case .override: "override"
        case .wakeFromSleep: "wake"
        case .noSuitableRouteForCategory: "no suitable route"
        case .routeConfigurationChange: "configuration change"
        default: "other"
        }
    }
}
