import CoreMedia
import VideoToolbox

/// Decodes the glasses' compressed HEVC frames into pixel buffers so HaishinKit can re-encode them as H.264.
/// Needed for Kick (rejects H.265) and Twitch without Affiliate. Runs on the SDK's frame thread, decodes synchronously
/// to keep frame order. ponytail: hardware decode may be refused while backgrounded; then frames simply stop.
final class Transcoder: @unchecked Sendable {
    private var session: VTDecompressionSession?
    private var format: CMFormatDescription?
    private let sink: @Sendable (CMSampleBuffer) -> Void
    /// Runs on the decoded frame before it becomes a sample buffer — this is where privacy blur sits.
    /// Returning nil means "do not publish this frame", which is how the blur pass fails closed.
    private let transform: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)?
    private var failures = 0
    private var callbackFailures = 0
    private(set) var decoded = 0
    private var synced = false        // HEVC decoding can only begin on a keyframe
    private var skipped = 0

    init(transform: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)? = nil, sink: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.transform = transform
        self.sink = sink
    }

    func decode(_ sb: CMSampleBuffer) {
        guard let fd = sb.formatDescription else { return }
        // Frames arrive mid-GOP, so feeding the decoder before a keyframe returns -17694 on every one.
        if !synced {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]]
            let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            guard !notSync else { skipped += 1; return }
            synced = true
            applog("stream", "keyframe found after \(skipped) skipped frames")
        }
        if session == nil || format.map({ !CMFormatDescriptionEqual($0, otherFormatDescription: fd) }) ?? true {
            invalidate()
            var s: VTDecompressionSession?
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: fd, decoderSpecification: nil,
                                                      imageBufferAttributes: attrs as CFDictionary, outputCallback: nil,
                                                      decompressionSessionOut: &s)
            guard status == noErr, let s else { applog("stream", "HEVC decoder create failed: \(status)", error: true); return }
            session = s
            format = fd
            applog("stream", "HEVC decoder ready (transcoding to H.264)")
        }
        guard let session else { return }
        let pts = sb.presentationTimeStamp
        let dur = sb.duration
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sb, flags: [], infoFlagsOut: nil) { [weak self] status, _, image, ipts, _ in
            guard let self else { return }
            guard status == noErr, let image else {
                self.callbackFailures += 1
                if self.callbackFailures == 1 || self.callbackFailures % 100 == 0 {
                    applog("stream", "HEVC decode callback empty: status=\(status) image=\(image != nil) (x\(self.callbackFailures))", error: true)
                }
                return
            }
            self.decoded += 1
            if self.decoded == 1 { applog("stream", "first frame decoded \(CVPixelBufferGetWidth(image))x\(CVPixelBufferGetHeight(image))") }
            // Privacy blur, when enabled. nil = the pass could not obscure this frame, so it is dropped
            // rather than published in the clear; Streamer separately cuts to black while that persists.
            var frame = image
            if let transform = self.transform {
                guard let obscured = transform(frame) else { return }
                frame = obscured
            }
            var fdOut: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: frame, formatDescriptionOut: &fdOut)
            guard let fdOut else { return }
            var timing = CMSampleTimingInfo(duration: dur, presentationTimeStamp: ipts.isValid ? ipts : pts, decodeTimeStamp: .invalid)
            var out: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: frame, formatDescription: fdOut,
                                                     sampleTiming: &timing, sampleBufferOut: &out)
            if let out { self.sink(out) } else { applog("stream", "decoded frame -> CMSampleBuffer failed", error: true) }
        }
        if status != noErr {
            failures += 1
            if failures == 1 || failures % 100 == 0 { applog("stream", "HEVC decode failed: \(status) (x\(failures))", error: true) }
            // -12903 kVTInvalidSessionErr: iOS killed the hardware decoder because the app went to the background.
            // Drop the session so the next frame recreates it; that fails while backgrounded and succeeds on return.
            if status == kVTInvalidSessionErr { invalidate() }
        } else if failures > 0 {
            applog("stream", "HEVC decoder recovered after \(failures) failed frames"); failures = 0
        }
    }

    func invalidate() {
        if let s = session { VTDecompressionSessionInvalidate(s) }
        session = nil
        format = nil
        synced = false        // after a teardown the decoder needs a fresh keyframe again
        skipped = 0
    }
}
