// Stays in the app target: Info.plist names it as $(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate.
import CoreLogging
import Engine
import UIKit

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
