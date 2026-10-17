//
//  Recording.swift
//  MetaStream
//
//  Local recording, independent of Go Live: HaishinKit's StreamRecorder is a permanent mixer output, so it
//  gets exactly what goes out (composited picture + final mix). Saved to Photos on stop.
//

import AVFoundation
import HaishinKit
import Photos

extension Streamer {
    private static let folder = URL.documentsDirectory.appending(path: "Recordings")

    func toggleRecording() {
        Task { recordingSince == nil ? await startRecording() : await stopRecording() }
    }

    func startRecording() async {
        guard recordingSince == nil else { return }
        // ponytail: glasses HEVC passthrough bypasses the mixer, so a recording would be audio-only; refuse it.
        // Upgrade path: tee the encoded HEVC from Hot.swift's passthrough append into a passthrough AVAssetWriterInput.
        guard phoneEncodes else {
            applog("stream", "recording refused: glasses passthrough has no mixer video")
            speaker?.speakSystem("Recording needs the phone camera or H.264")
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
            let url = Self.folder.appending(path: "MetaStream-\(f.string(from: .now)).mp4")
            await recorder.setMovieFragmentInterval(10)   // a crash keeps everything but the last ~10 s
            var settings = StreamRecorder.defaultSettings
            settings[.video] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoHeightKey: 0, AVVideoWidthKey: 0,
                                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000]]
            try await recorder.startRecording(url, settings: settings)
            recordingSince = .now
            applog("stream", "recording started \(url.lastPathComponent)")
            Task { [weak self, recorder] in
                for await e in await recorder.error {
                    applog("stream", "recording error: \(e)")
                    await self?.stopRecording()
                }
            }
        } catch {
            applog("stream", "recording start failed: \(error)")
        }
    }

    func stopRecording() async {
        guard recordingSince != nil else { return }
        recordingSince = nil
        do {
            let url = try await recorder.stopRecording()
            applog("stream", "recording stopped \(url.lastPathComponent)")
            guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized || PHPhotoLibrary.authorizationStatus(for: .addOnly) == .limited else {
                applog("stream", "recording kept in Documents/Recordings: no Photos access")
                return
            }
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
            try? FileManager.default.removeItem(at: url)
            speaker?.speakSystem("Recording saved to Photos")
        } catch {
            applog("stream", "recording save failed, file kept in Documents/Recordings: \(error)")
        }
    }

    /// Called from the 1 s tick: switching to glasses passthrough mid-recording would leave the file without video.
    func checkRecordingSource() {
        guard recordingSince != nil, !phoneEncodes else { return }
        speaker?.speakSystem("Recording stopped: glasses passthrough can't be recorded")
        Task { await stopRecording() }
    }
}
