import SwiftUI

/// "Share to Instagram story" while live: a 9:16 card (a frame from the stream, LIVE, the title and the Kick link) handed
/// to Instagram's story editor through the pasteboard, per Meta's Sharing to Stories (iOS). The tappable link can't be
/// pre-placed by an app, so the Kick URL also goes on the clipboard: Link sticker, paste, post. The card leaves the lower
/// third empty for that sticker.
@MainActor
enum InstagramStory {
    /// The Facebook App ID Instagram requires (developers.facebook.com, no review needed for sharing). Public, not a secret.
    static let facebookAppID = ""

    private static var scheme: URL? { URL(string: "instagram-stories://share?source_application=" + facebookAppID) }

    /// Configured and Instagram installed (needs `instagram-stories` in LSApplicationQueriesSchemes).
    static var available: Bool {
        guard !facebookAppID.isEmpty, let scheme else { return false }
        return UIApplication.shared.canOpenURL(scheme)
    }

    /// Grabs the outgoing frame (only while live and blur isn't stalled, like the Live post), renders the card and opens
    /// Instagram. Without a frame (glasses passthrough) the card is text on black.
    static func share(_ streamer: Streamer) async {
        guard available, let scheme else { return }
        var frame: UIImage?
        if let jpeg = await FrameGrab.shared.next(), streamer.live, streamer.privacy?.stalled != true {
            frame = UIImage(data: jpeg)
        }
        let post = LivePost.shared
        let link = post.slug.isEmpty ? "" : "https://kick.com/" + post.slug
        let renderer = ImageRenderer(content: StoryCard(frame: frame, title: post.title, link: link, template: .current, theme: .current))
        renderer.scale = 3
        guard let card = renderer.uiImage?.jpegData(compressionQuality: 0.9) else { return }
        var item: [String: Any] = ["com.instagram.sharedSticker.backgroundImage": card]
        // ponytail: the link rides the same pasteboard item as plain text, so pasting into the Link sticker works if
        // Instagram leaves the pasteboard alone; the card shows the link too, for typing it when it doesn't.
        if !link.isEmpty { item["public.utf8-plain-text"] = link }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date().addingTimeInterval(300)])
        _ = await UIApplication.shared.open(scheme)
        applog("reach", "instagram story card handed over (frame: \(frame != nil))")
    }
}
