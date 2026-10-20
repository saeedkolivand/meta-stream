import AVFoundation
import CoreImage
import CoreMedia
import HaishinKit
import os
import UIKit

/// Hands out ONE JPEG of the final composited outgoing frame (after privacy blur and overlays) on request, for the
/// Live post's photo. Taps the mixer's final output like LayerSink (videoTrackId UInt8.max, see Hot.swift). Glasses
/// HEVC passthrough never reaches the mixer, so `next` then times out with nil. Idle cost is one lock check per frame.
final class FrameGrab: MediaMixerOutput, @unchecked Sendable {
    static let shared = FrameGrab()

    private struct Pending { var id: Int; var cont: CheckedContinuation<Data?, Never> }
    private struct State { var pending: Pending?; var nextId = 0 }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let context = CIContext()

    var videoTrackId: UInt8? { UInt8.max }
    var audioTrackId: UInt8? { nil }

    /// The next outgoing frame as a JPEG (long side at most 1280 px), or nil after `timeout`. One caller at a time:
    /// a second call while one waits gets nil at once.
    func next(timeout: Duration = .seconds(2)) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            let id: Int? = state.withLock { st in
                guard st.pending == nil else { return nil }
                st.nextId += 1
                st.pending = Pending(id: st.nextId, cont: cont)
                return st.nextId
            }
            guard let id else { cont.resume(returning: nil); return }
            Task {
                try? await Task.sleep(for: timeout)
                self.take(id)?.resume(returning: nil)
            }
        }
    }

    /// Removes and returns the waiter (only the one with `id`, when given): whoever gets it resumes it exactly once.
    private func take(_ id: Int? = nil) -> CheckedContinuation<Data?, Never>? {
        state.withLock { st -> CheckedContinuation<Data?, Never>? in
            guard let waiter = st.pending, id == nil || waiter.id == id else { return nil }
            st.pending = nil
            return waiter.cont
        }
    }

    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        guard state.withLock({ $0.pending != nil }), let cont = take() else { return }
        cont.resume(returning: jpeg(sampleBuffer))
    }

    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}

    private func jpeg(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        var image = CIImage(cvPixelBuffer: pixels)
        let longSide = max(image.extent.width, image.extent.height)
        if longSide > 1280 {
            let scale = 1280 / longSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }
}
