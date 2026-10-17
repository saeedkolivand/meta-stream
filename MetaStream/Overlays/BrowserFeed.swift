// One OBS browser source: a locked-down WKWebView that is snapshotted into an ImageScreenObject.
// WKWebView only renders inside a window hierarchy, so it lives in a hidden container behind the app's UI.
// Locked down: http(s) pages only, no message handlers (no JS <-> app bridge), non-persistent storage, and the
// URL never reaches the log (it carries the streamer's alert/chat tokens).
import HaishinKit
import UIKit
import WebKit

// OBS's default browser source css: transparent page, no scrollbars.
private let defaultCSS = "body { background-color: rgba(0, 0, 0, 0); margin: 0px auto; overflow: hidden; }"

/// The hidden parent for every browser source's web view.
@MainActor
private enum BrowserHost {
    private static var container: UIView?

    static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }

    static func add(_ web: WKWebView) -> Bool {
        guard let window else { return false }
        if container?.window !== window {
            container?.removeFromSuperview()
            // 1x1 and nearly transparent, behind the root view, no touches: invisible, but WebKit still paints into it.
            // Alpha 0 or isHidden would stop painting; positioning it off-screen would mark the views not visible.
            let c = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            c.alpha = 0.01
            c.isUserInteractionEnabled = false
            c.clipsToBounds = false
            window.insertSubview(c, at: 0)
            container = c
        }
        container?.addSubview(web)
        return true
    }

    static func releaseIfEmpty() {
        guard container?.subviews.isEmpty == true else { return }
        container?.removeFromSuperview()
        container = nil
    }
}

@MainActor
final class BrowserFeed: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private let box: CGRect         // output px; may hang off the canvas
    private let canvas: CGSize
    private let target: ImageScreenObject

    /// False until the app has a key window to host web views in.
    static var hostAvailable: Bool { BrowserHost.window != nil }

    /// Nil when the page can't load (not http(s), or no window to host the view yet).
    init?(layer: OverlayLayer, box: CGRect, canvas: CGSize, target: ImageScreenObject) {
        guard let url = URL(string: layer.data["url"] ?? ""), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let w = Int(layer.data["width"] ?? "") ?? 800
        let h = Int(layer.data["height"] ?? "") ?? 600
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = .audio   // alert sounds would play from the phone, not the stream
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let css = layer.data["css"].flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 } ?? defaultCSS
        let quoted = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        // Phone WebKit lays pages out at ~980 CSS px unless told otherwise; OBS lays out at exactly the source size.
        let js = """
        (function(){var s=document.createElement('style');s.textContent=\(quoted);document.head.appendChild(s);
        document.querySelectorAll('meta[name=viewport]').forEach(function(m){m.remove()});
        var m=document.createElement('meta');m.name='viewport';m.content='width=\(w),initial-scale=1,maximum-scale=1';document.head.appendChild(m)})();
        """
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: w, height: h), configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.underPageBackgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        self.web = web
        self.box = box
        self.canvas = canvas
        self.target = target
        super.init()
        web.navigationDelegate = self
        guard BrowserHost.add(web) else { return nil }
        web.load(URLRequest(url: url))
    }

    /// Only http(s) (and about:blank frames) may load; a page link to file:, tel:, javascript: etc. is dropped.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        ["http", "https", "about"].contains(navigationAction.request.url?.scheme?.lowercased() ?? "") ? .allow : .cancel
    }

    /// One frame: snapshot the page and hand it to the screen object (redrawn into the box only when it doesn't fit as is).
    func pump() async {
        let cfg = WKSnapshotConfiguration()
        cfg.snapshotWidth = NSNumber(value: Double(box.width / max(web.traitCollection.displayScale, 1)))   // points -> ~box.width px
        guard let img = try? await web.takeSnapshot(configuration: cfg),
              let piece = img.cgImage.flatMap({ OverlayRaster.direct($0, box: box, canvas: canvas) })
                ?? OverlayRaster.render(box, canvas: canvas, draw: { img.draw(in: $0) }) else { return }
        await OverlayScreen.setImage(target, piece.bitmap)
    }

    func close() {
        web.stopLoading()
        web.navigationDelegate = nil
        web.configuration.userContentController.removeAllUserScripts()
        web.removeFromSuperview()
        BrowserHost.releaseIfEmpty()
    }
}
