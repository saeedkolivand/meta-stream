// Sounds into the mix: alert chime, clip audio and the soundboard play through a private AVAudioEngine, and its
// output is fed to HaishinKit as mixer track 1 (the mic stays on track 0). The engine paces the audio in real time,
// which track 1's tiny ring buffer needs. Nothing is audible on the phone: the engine's main mixer is silent.
import Foundation
import AVFoundation
import AudioToolbox
import HaishinKit

/// A soundboard entry: a file copied into Documents/sounds. The list lives in AppStorage("sounds") as JSON.
struct Sound: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var file: String
    static let maxCount = 8

    static func decode(_ raw: String) -> [Sound] { (try? JSONDecoder().decode([Sound].self, from: Data(raw.utf8))) ?? [] }
    static func encode(_ s: [Sound]) -> String { (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }

    static var folder: URL {
        let d = URL.documentsDirectory.appending(path: "sounds")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ file: String) -> URL { folder.appending(path: file) }

    /// Copies a picked file in under a unique name; nil if the copy failed.
    static func importFile(_ src: URL) -> String? {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let name = "\(UUID().uuidString.prefix(8))-\(src.lastPathComponent)"
        do { try FileManager.default.copyItem(at: src, to: url(name)); return name } catch {
            applog("stream", "sound import failed: \(error.localizedDescription)", error: true)
            return nil
        }
    }
}

/// A tap buffer on its way to the mixer. Copied out of the engine's reused buffer first.
private struct Tapped: @unchecked Sendable { let buffer: AVAudioPCMBuffer; let when: AVAudioTime }

@MainActor
final class SoundMix {
    static let shared = SoundMix()

    /// The streamer's current mixer (it is rebuilt when dual camera flips); set in wireMixer().
    var mixer: MediaMixer?

    /// live && !muted. Sounds only exist on stream, so nothing plays (or runs) otherwise.
    /// ponytail: HaishinKit's mix is clocked by the mic track, so while the mic is muted (detached) the whole mix, sounds included, stops.
    var enabled = false {
        didSet {
            guard oldValue != enabled else { return }
            if enabled { startClip() } else { stopAll() }
        }
    }

    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let engine = AVAudioEngine()
    private let alerts = AVAudioPlayerNode(), clips = AVAudioPlayerNode(), board = AVAudioPlayerNode()
    private let bus = AVAudioMixerNode()
    private let feed: AsyncStream<Tapped>.Continuation
    private var pending = 0          // buffers scheduled and not yet played; the engine stops at 0
    private var generation = 0       // bumped by stopAll so late completions of stopped buffers are ignored
    private var clip: (url: URL, loop: Bool)?
    private lazy var chime = Self.makeChime(fmt)

    private init() {
        let (stream, cont) = AsyncStream.makeStream(of: Tapped.self, bufferingPolicy: .bufferingNewest(32))
        feed = cont
        // players -> pre -> peak limiter -> bus (tapped) -> main mixer (muted)
        let pre = AVAudioMixerNode()
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        for n in [alerts, clips, board, pre, limiter, bus] as [AVAudioNode] { engine.attach(n) }
        for p in [alerts, clips, board] { engine.connect(p, to: pre, format: fmt) }
        engine.connect(pre, to: limiter, format: fmt)
        engine.connect(limiter, to: bus, format: fmt)
        engine.connect(bus, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0
        // One consumer keeps the appends in tap order.
        Task { [weak self] in
            for await t in stream { await self?.mixer?.append(t.buffer, when: t.when, track: 1) }
        }
    }

    // MARK: play

    func playAlert() {
        let file = UserDefaults.standard.string(forKey: "alertSound") ?? ""
        guard !file.isEmpty else { play(chime, on: alerts); return }
        playFile(Sound.url(file), seconds: 10, on: alerts)
    }

    func playSound(_ s: Sound) { playFile(Sound.url(s.file), seconds: 20, on: board) }

    /// Starts a media layer's audio; a later clip replaces the earlier one (one clip audio at a time).
    /// ponytail: loose sync. It starts when the layer is built and loops by itself, while the video loop restarts on
    /// a 1 s poll, so they drift by up to a second per loop. Clips are decoded whole and capped at 60 s.
    func playClip(_ url: URL, loop: Bool) {
        clip = (url, loop)
        clips.stop()
        startClip()
    }

    func stopClips() { clip = nil; clips.stop() }

    private func startClip() {
        guard enabled, let c = clip else { return }
        playFile(c.url, seconds: 60, on: clips, loops: c.loop)   // no audio track plays nothing
    }

    /// Decodes off the main thread (a long file takes a noticeable moment), then plays. A clip that was replaced or
    /// stopped while decoding is dropped.
    private func playFile(_ url: URL, seconds: Double, on p: AVAudioPlayerNode, loops: Bool = false) {
        let fmt = fmt
        Task {
            let buf = await Task.detached { Self.load(url, fmt, seconds: seconds) }.value
            if p === clips, clip?.url != url { return }
            play(buf, on: p, loops: loops)
        }
    }

    private func play(_ buf: AVAudioPCMBuffer?, on p: AVAudioPlayerNode, loops: Bool = false) {
        guard enabled, let buf, start() else { return }
        applyVolumes()
        pending += 1
        let g = generation
        p.scheduleBuffer(buf, at: nil, options: loops ? .loops : [], completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in SoundMix.shared.done(g) }
        }
        p.play()   // also after the engine restarted; a no-op while already playing
    }

    /// Alert / clip / sound volumes from Settings (0...1 each). The mic's volume is a mixer track setting, see applyAudioMix().
    func applyVolumes() {
        func v(_ key: String) -> Float { AudioMath.gain(UserDefaults.standard.object(forKey: key) as? Double ?? 1) }
        alerts.volume = v("volAlert"); clips.volume = v("volClip"); board.volume = v("volSound")
    }

    // MARK: engine

    private func start() -> Bool {
        if engine.isRunning { return true }
        pending = 0
        bus.removeTap(onBus: 0)
        bus.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.tap(feed))
        do { try engine.start(); return true } catch {
            applog("stream", "sound engine: \(error.localizedDescription)", error: true)
            return false
        }
    }

    private func done(_ g: Int) {
        guard g == generation else { return }
        pending = max(0, pending - 1)
        if pending == 0 { stopEngine() }   // idle: no engine, no battery
    }

    private func stopEngine() {
        bus.removeTap(onBus: 0)
        engine.stop()
    }

    private func stopAll() {
        generation += 1
        pending = 0
        for p in [alerts, clips, board] { p.stop() }
        stopEngine()
    }

    /// Built outside the actor: the tap runs on an audio thread.
    private nonisolated static func tap(_ feed: AsyncStream<Tapped>.Continuation) -> AVAudioNodeTapBlock {
        { buf, when in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: buf.frameLength),
                  let src = buf.floatChannelData, let dst = copy.floatChannelData else { return }
            copy.frameLength = buf.frameLength
            for c in 0..<Int(buf.format.channelCount) { dst[c].update(from: src[c], count: Int(buf.frameLength)) }
            feed.yield(Tapped(buffer: copy, when: when))
        }
    }

    // MARK: buffers

    /// The file decoded and converted to the engine's format (players need buffers in their connection format).
    /// nil for an unreadable file or one without audio. ponytail: read whole, truncated at `seconds`.
    private nonisolated static func load(_ url: URL, _ fmt: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        guard let f = try? AVAudioFile(forReading: url), f.length > 0 else { return nil }
        let inFmt = f.processingFormat
        let frames = AVAudioFrameCount(min(Double(f.length), seconds * inFmt.sampleRate))
        guard let src = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: frames), (try? f.read(into: src, frameCount: frames)) != nil,
              let conv = AVAudioConverter(from: inFmt, to: fmt),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(src.frameLength) * fmt.sampleRate / inFmt.sampleRate) + 1024)
        else { return nil }
        let once = Box(false)
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if once.fire() { status.pointee = .haveData; return src }
            status.pointee = .endOfStream
            return nil
        }
        return err == nil && out.frameLength > 0 ? out : nil
    }

    /// Two-tone chime, ~0.6 s: A5 then E6, each a soft attack with an exponential decay, faded out at the end.
    private static func makeChime(_ fmt: AVAudioFormat) -> AVAudioPCMBuffer? {
        let n = Int(0.6 * fmt.sampleRate)
        guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)), let ch = b.floatChannelData else { return nil }
        b.frameLength = AVAudioFrameCount(n)
        func tone(_ t: Double, start: Double, hz: Double) -> Double {
            let x = t - start
            return x < 0 ? 0 : min(1, x / 0.01) * exp(-x * 7) * sin(2 * .pi * hz * x)
        }
        for i in 0..<n {
            let t = Double(i) / fmt.sampleRate
            let s = Float(0.4 * (tone(t, start: 0, hz: 880) + tone(t, start: 0.15, hz: 1318.5)) * min(1, (0.6 - t) / 0.05))
            for c in 0..<Int(fmt.channelCount) { ch[c][i] = s }
        }
        return b
    }
}

extension Streamer {
    /// Mixer track volumes: track 0 = mic (Settings volume), track 1 = the sounds engine (its volumes are applied inside it).
    func applyAudioMix() async {
        var s = await mixer.audioMixerSettings
        s.tracks[0] = AudioMixerTrackSettings(volume: AudioMath.gain(UserDefaults.standard.object(forKey: "volMic") as? Double ?? 1))
        s.tracks[1] = AudioMixerTrackSettings(volume: 1)
        await mixer.setAudioMixerSettings(s)
    }
}
