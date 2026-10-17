import XCTest
import AVFoundation
@testable import MetaStream

final class AudioLevelTests: XCTestCase {
    func testDemoAudioLevelAndDeadAir() {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 1, interleaved: true)!
        let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4410)!
        b.frameLength = 4410
        XCTAssertEqual(AudioMath.dBFS(b), -120, "silence")
        for i in 0..<4410 { b.int16ChannelData![0][i] = Int16(32767 * sin(2 * Double.pi * 441 * Double(i) / 44100)) }   // 100 whole cycles
        XCTAssertEqual(AudioMath.dBFS(b), -3.01, accuracy: 0.1, "full-scale sine is -3 dBFS RMS")

        let t0 = Date(timeIntervalSince1970: 1000)
        var r = AudioMath.deadAir(quietSince: nil, level: -80, now: t0, live: true, muted: false)
        XCTAssertFalse(r.alert, "just went quiet")
        r = AudioMath.deadAir(quietSince: r.quietSince, level: -80, now: t0 + 19, live: true, muted: false)
        XCTAssertFalse(r.alert, "19 s is not yet 20")
        r = AudioMath.deadAir(quietSince: r.quietSince, level: -80, now: t0 + 20, live: true, muted: false)
        XCTAssertTrue(r.alert, "20 s quiet")
        r = AudioMath.deadAir(quietSince: r.quietSince, level: -20, now: t0 + 21, live: true, muted: false)
        XCTAssertFalse(r.alert, "audio is back")
        XCTAssertNil(r.quietSince, "and the clock resets")
        XCTAssertFalse(AudioMath.deadAir(quietSince: t0, level: -120, now: t0 + 60, live: true, muted: true).alert, "muted never alerts")
        XCTAssertFalse(AudioMath.deadAir(quietSince: t0, level: -120, now: t0 + 60, live: false, muted: false).alert, "not live never alerts")
        XCTAssertEqual(AudioMath.gain(1.7), 1, "gain clamps")
    }
}
