// Broadcast Upload Extension (adr/0003): hardware-encodes the screen and hands the encoded frames to the app
// through a ring of files in the App Group folder, one Darwin notification per frame. Capped at ~50 MB by iOS,
// so nothing here queues: a frame that finds the encoder busy is dropped. No screen audio.
import CoreMedia
import Foundation
import ReplayKit
import VideoToolbox
import os

private let screenLog = Logger(subsystem: "com.saeedkolivand.metastream.Screen", category: "screen")

private func post(_ name: String) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
}

final class ScreenEncoder: @unchecked Sendable {
    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var inSize = (w: 0, h: 0)
    private var inflight = 0
    private var seq: UInt32 = 0
    private var hevc = true
    private let dir = ScreenIPC.folder

    func start() {
        guard let dir else { screenLog.error("no app group container"); return }
        try? FileManager.default.removeItem(at: dir)   // stale frames from a previous broadcast
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        seq = 0
    }

    func stop() {
        lock.lock()
        let old = session
        session = nil; inSize = (0, 0)
        lock.unlock()
        if let old { VTCompressionSessionInvalidate(old) }   // outside the lock: it may wait for output handlers
    }

    func encode(_ sb: CMSampleBuffer) {
        guard let pb = sb.imageBuffer else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        lock.lock()
        var old: VTCompressionSession?
        if session == nil || inSize.w != w || inSize.h != h { old = session; makeSession(w, h) }
        guard let session, inflight < 2 else {   // behind: drop, never queue
            lock.unlock()
            if let old { VTCompressionSessionInvalidate(old) }
            return
        }
        inflight += 1
        let hevc = self.hevc
        lock.unlock()
        if let old { VTCompressionSessionInvalidate(old) }   // outside the lock, see stop()
        // ReplayKit tags the frame with how the screen was held; the app rotates, the pixels stay as captured.
        let orientation = (CMGetAttachment(sb, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber)?.uint8Value ?? 1
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: pb, presentationTimeStamp: sb.presentationTimeStamp,
                                                     duration: .invalid, frameProperties: nil, infoFlagsOut: nil) { [self] status, _, out in
            lock.lock(); inflight -= 1; lock.unlock()
            if status == noErr, let out { write(out, hevc: hevc, orientation: orientation) }
        }
        if status != noErr { lock.lock(); inflight -= 1; lock.unlock() }
    }

    /// Long side capped at 1920 (1080p), even dimensions; the session scales the captured frame itself.
    /// Under the lock; the caller invalidates the previous session after unlocking.
    private func makeSession(_ w: Int, _ h: Int) {
        session = nil; inSize = (w, h)
        let scale = min(1, 1920 / Double(max(w, h)))
        let ow = Int(Double(w) * scale) & ~1, oh = Int(Double(h) * scale) & ~1
        for codec in [kCMVideoCodecType_HEVC, kCMVideoCodecType_H264] {   // H.264 only if no HEVC encoder
            var s: VTCompressionSession?
            guard VTCompressionSessionCreate(allocator: nil, width: Int32(ow), height: Int32(oh), codecType: codec, encoderSpecification: nil,
                                             imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                             compressionSessionOut: &s) == noErr, let s else { continue }
            hevc = codec == kCMVideoCodecType_HEVC
            func set(_ key: CFString, _ value: CFTypeRef) { VTSessionSetProperty(s, key: key, value: value) }
            set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
            set(kVTCompressionPropertyKey_ProfileLevel, hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
            set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
            set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 2))
            set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: 30))
            set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: min(ow * oh * 3, 8_000_000)))
            VTCompressionSessionPrepareToEncodeFrames(s)
            session = s
            screenLog.info("encoder \(ow)x\(oh) \(self.hevc ? "hevc" : "h264")")
            return
        }
        screenLog.error("no encoder available")
    }

    private func write(_ sb: CMSampleBuffer, hevc: Bool, orientation: UInt8) {
        guard let dir, let fd = sb.formatDescription, let bb = sb.dataBuffer else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]]
        let key = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        var sets: [Data] = []
        if key {
            var count = 0
            func ps(_ i: Int, _ p: inout UnsafePointer<UInt8>?, _ n: inout Int, _ c: UnsafeMutablePointer<Int>?) {
                if hevc { _ = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fd, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &n, parameterSetCountOut: c, nalUnitHeaderLengthOut: nil) }
                else { _ = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fd, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &n, parameterSetCountOut: c, nalUnitHeaderLengthOut: nil) }
            }
            var p0: UnsafePointer<UInt8>?, n0 = 0
            ps(0, &p0, &n0, &count)
            for i in 0..<count {
                var p: UnsafePointer<UInt8>?, n = 0
                ps(i, &p, &n, nil)
                if let p { sets.append(Data(bytes: p, count: n)) }
            }
        }
        let total = CMBlockBufferGetDataLength(bb)
        var payload = Data(count: total)
        let copied = payload.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: total, destination: $0.baseAddress!) }
        guard copied == kCMBlockBufferNoErr else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(fd)
        lock.lock(); defer { lock.unlock() }   // frames are written one at a time, in order
        seq += 1
        let header = ScreenIPC.Header(hevc: hevc, key: key, orientation: orientation, sets: UInt8(sets.count),
                                      ptsMicros: Int64(sb.presentationTimeStamp.seconds * 1_000_000),
                                      width: UInt32(dims.width), height: UInt32(dims.height), seq: seq)
        // .atomic = write to a temp file, then rename: the app never reads half a frame.
        try? ScreenIPC.pack(header, sets: sets, payload: payload).write(to: ScreenIPC.frameFile(seq, in: dir), options: .atomic)
        try? Data(String(seq).utf8).write(to: ScreenIPC.latestFile(in: dir), options: .atomic)
        post(ScreenIPC.frameNote)
    }
}

class SampleHandler: RPBroadcastSampleHandler {
    private let encoder = ScreenEncoder()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        encoder.start()
        post(ScreenIPC.startedNote)
    }

    override func broadcastFinished() {
        encoder.stop()
        post(ScreenIPC.stoppedNote)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }   // ponytail: no screen audio (adr/0003)
        encoder.encode(sampleBuffer)
    }
}
