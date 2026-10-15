import AVFoundation
import UIKit

/// Clean program feed on a USB-C display. Hot.enqueue feeds `layer` from the same taps as the on-device preview
/// (LayerSink / glasses frames), so no second mixer output is needed and mixer rewires can't orphan it.
// ponytail: unsynchronised weak static; the frame thread may read a layer one frame after disconnect, which is harmless.
enum ExternalDisplay {
    nonisolated(unsafe) static weak var layer: AVSampleBufferDisplayLayer?
}

/// Wired up in Info.plist (UIWindowSceneSessionRoleExternalDisplayNonInteractive). Black window, aspect-fit preview.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.displayLayer.videoGravity = .resizeAspect
        let vc = UIViewController()
        vc.view = view
        let w = UIWindow(windowScene: ws)
        w.backgroundColor = .black
        w.rootViewController = vc
        w.isHidden = false
        window = w
        ExternalDisplay.layer = view.displayLayer
        applog("ui", "external display connected")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplay.layer = nil
        window = nil
        applog("ui", "external display disconnected")
    }
}
