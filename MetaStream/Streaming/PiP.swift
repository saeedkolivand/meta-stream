import AVKit
import CoreMedia

/// Picture in Picture for the glasses preview layer. Starts automatically when the app goes to the background while live
/// (armed by goLive). Besides the floating window, PiP keeps the app "playing" in iOS's eyes,
/// which is what lets media pipelines (the H.264 transcoder included) survive backgrounding.
final class PiPController: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    private var controller: AVPictureInPictureController?
    private var armed = false

    init(layer: AVSampleBufferDisplayLayer) {
        super.init()
        guard AVPictureInPictureController.isPictureInPictureSupported() else { applog("ui", "PiP not supported"); return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        // Off by default. Auto-start is what keeps the app "playing" in iOS's eyes while backgrounded, so
        // it must only be armed during a live session (goLive arms, stopLive disarms). Left on, an idle
        // backgrounded app never suspends and the camera, mixer and every timer keep running for nothing.
        c.canStartPictureInPictureAutomaticallyFromInline = false
        controller = c
        applog("ui", "PiP ready")
    }

    /// Arms/disarms background auto-start. Called once per session from Streamer.goLive/stopLive.
    func setArmed(_ on: Bool) {
        armed = on
        controller?.canStartPictureInPictureAutomaticallyFromInline = on
        controller?.invalidatePlaybackState()
        applog("ui", "PiP armed=\(on)")
    }

    // Live stream: no seeking. Idle reports "paused": iOS auto-started PiP for an idle "playing" layer even with
    // canStartPictureInPictureAutomaticallyFromInline false (seen with GPS sharing keeping the iPhone alive in the background).
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { !armed }
    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {}

    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        applog("ui", "PiP started armed=\(armed)")
        if !armed { c.stopPictureInPicture() }   // backstop if iOS still starts it while idle
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) { applog("ui", "PiP stopped") }
    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        applog("ui", "PiP failed: \(error.localizedDescription)", error: true)
    }
}
