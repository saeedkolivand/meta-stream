// Screen share, app side (adr/0003): the MetaStreamScreen broadcast extension writes hardware-encoded frames into a
// ring of files in the App Group folder and posts a Darwin notification per frame. This reads them, rebuilds
// CMSampleBuffers and decodes them with the glasses' Transcoder; the decoded frames go to the mixer through `sink`.
import CoreImage
import CoreMedia
import Foundation
import ImageIO

@MainActor
final class ScreenSource: ObservableObject {
    /// A broadcast is running (the extension said so, or its frames are arriving).
    @Published private(set) var screenLive = false

    /// The extension is embedded in this build; without its profile the Screen video source is hidden everywhere.
    nonisolated static let available: Bool = {
        let plugins = Bundle.main.builtInPlugInsURL.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }
        return plugins?.contains("MetaStreamScreen.appex") ?? false
    }()

    /// Where decoded frames go (Streamer points it at the current mixer while Screen is the video source).
    var sink: (@Sendable (CMSampleBuffer) -> Void)? { didSet { ScreenPump.shared.sink.value = sink } }

    init() {
        guard Self.available else { return }
        ScreenPump.shared.onLive = { [weak self] live in
            Task { @MainActor in
                guard let self, self.screenLive != live else { return }
                self.screenLive = live
                applog("screen", live ? "broadcast live" : "broadcast stopped")
            }
        }
        ScreenPump.shared.observe()
    }
}

/// Everything off the main thread: Darwin callbacks only enqueue; reading and decoding run on one serial queue.
final class ScreenPump: @unchecked Sendable {
    static let shared = ScreenPump()
    let sink = Box<(@Sendable (CMSampleBuffer) -> Void)?>(nil)
    /// Decode only while Screen is the video source (Streamer.syncHot); otherwise frames are ignored.
    let active = Box(false)
    var onLive: (@Sendable (Bool) -> Void)?

    private let queue = DispatchQueue(label: "metastream.screen")
    private let orientation = Box<UInt32>(1)   // of the frame being decoded; rotate() reads it
    private let ci = CIContext()
    private var lastSeq: UInt32 = 0            // queue-confined from here down
    private var announced = false
    private var format: CMVideoFormatDescription?
    private lazy var transcoder: Transcoder = Transcoder(transform: { [unowned self] pb in self.rotate(pb) },
                                                         sink: { [unowned self] sb in self.sink.value?(sb) })

    func observe() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [ScreenIPC.frameNote, ScreenIPC.startedNote, ScreenIPC.stoppedNote] {
            // C function pointer: no captures, it reaches the shared instance.
            CFNotificationCenterAddObserver(center, nil, { _, _, note, _, _ in
                guard let raw = note?.rawValue else { return }
                let n = raw as String
                ScreenPump.shared.queue.async { ScreenPump.shared.notified(n) }
            }, name as CFString, nil, .deliverImmediately)
        }
    }

    private func notified(_ name: String) {
        switch name {
        case ScreenIPC.startedNote:
            reset()
            announce(true)
        case ScreenIPC.stoppedNote:
            reset()
            announce(false)
        default:
            pull()
        }
    }

    private func reset() {
        lastSeq = 0; format = nil
        transcoder.invalidate()
    }

    private func announce(_ live: Bool) {
        guard announced != live else { return }
        announced = live
        onLive?(live)
    }

    /// Frames in order up to the newest. Behind by more than the ring (or the extension restarted): jump to the
    /// newest and let the decoder wait for its next keyframe, never replay old frames. ponytail: no watchdog for an
    /// extension killed without its "stopped" notification; screenLive then stays true until the next broadcast.
    private func pull() {
        guard let dir = ScreenIPC.folder,
              let latest = (try? Data(contentsOf: ScreenIPC.latestFile(in: dir))).flatMap({ UInt32(String(decoding: $0, as: UTF8.self)) }) else { return }
        announce(true)
        guard active.value else { return }
        if latest < lastSeq { reset() }
        if latest == lastSeq { return }
        var next = lastSeq + 1
        if latest - lastSeq > UInt32(ScreenIPC.ring) - 1 { transcoder.invalidate(); format = nil; next = latest }
        while next <= latest {
            guard let data = try? Data(contentsOf: ScreenIPC.frameFile(next, in: dir)),
                  case let (h, sets, payload)? = ScreenIPC.unpack(data), h.seq == next else {
                transcoder.invalidate(); format = nil   // overwritten under us: resync on the newest
                lastSeq = latest
                return
            }
            feed(h, sets, payload)
            lastSeq = next
            next += 1
        }
    }

    private func feed(_ h: ScreenIPC.Header, _ sets: [Data], _ payload: Data) {
        if h.key, !sets.isEmpty { format = Self.makeFormat(hevc: h.hevc, sets: sets) }
        guard let format, !payload.isEmpty else { return }   // deltas before the first keyframe have no format yet
        var block: CMBlockBuffer?
        let n = payload.count
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n, blockAllocator: nil, customBlockSource: nil,
                                           offsetToData: 0, dataLength: n, flags: 0, blockBufferOut: &block)
        guard let block else { return }
        let filled = payload.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: n) }
        guard filled == kCMBlockBufferNoErr else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: h.ptsMicros, timescale: 1_000_000), decodeTimeStamp: .invalid)
        var size = n
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                                  sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sb)
        guard let sb else { return }
        if !h.key {   // Transcoder starts decoding at the first sample that is not marked NotSync
            if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
                let d = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        orientation.value = UInt32(h.orientation)
        transcoder.decode(sb)
    }

    private static func makeFormat(hevc: Bool, sets: [Data]) -> CMVideoFormatDescription? {
        let bufs = sets.map { s -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: s.count)
            s.copyBytes(to: p, count: s.count)
            return p
        }
        defer { bufs.forEach { $0.deallocate() } }
        let ptrs = bufs.map { UnsafePointer($0) }
        let sizes = sets.map(\.count)
        var fd: CMVideoFormatDescription?
        _ = ptrs.withUnsafeBufferPointer { pp in
            sizes.withUnsafeBufferPointer { sp in
                hevc
                    ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: pp.baseAddress!,
                                                                          parameterSetSizes: sp.baseAddress!, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &fd)
                    : CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: pp.baseAddress!,
                                                                          parameterSetSizes: sp.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
            }
        }
        return fd
    }

    /// ReplayKit hands over the screen as captured and says how it was held (CGImagePropertyOrientation); turn it
    /// upright here, since the mixer takes pixels as they come. Upright frames pass through untouched.
    private func rotate(_ pb: CVPixelBuffer) -> CVPixelBuffer? {
        guard let o = CGImagePropertyOrientation(rawValue: orientation.value), o != .up else { return pb }
        let img = CIImage(cvPixelBuffer: pb).oriented(o)
        let e = img.extent
        var out: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(e.width), Int(e.height), kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &out)
        guard let out else { return nil }
        ci.render(img.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y)), to: out)
        return out
    }
}
