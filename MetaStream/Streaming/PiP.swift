import AVKit
import CoreMedia

/// Picture in Picture for the glasses preview layer. Starts automatically when the app goes to the background
/// while the preview is on screen. Besides the floating window, PiP keeps the app "playing" in iOS's eyes,
/// which is what lets media pipelines (the H.264 transcoder included) survive backgrounding.
final class PiPController: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    private var controller: AVPictureInPictureController?

    init(layer: AVSampleBufferDisplayLayer) {
        super.init()
        guard AVPictureInPictureController.isPictureInPictureSupported() else { applog("ui", "PiP not supported"); return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = true
        controller = c
        applog("ui", "PiP ready")
    }

    // Live stream: no seeking, never paused.
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {}

    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) { applog("ui", "PiP started") }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) { applog("ui", "PiP stopped") }
    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        applog("ui", "PiP failed: \(error.localizedDescription)", error: true)
    }
}
