import SwiftUI

/// "Share to Instagram story" while live: a 9:16 card (a frame from the stream, LIVE, the title and the Kick link) handed
/// to Instagram's story editor through the pasteboard, per Meta's Sharing to Stories (iOS). The tappable link can't be
/// pre-placed by an app, so the Kick URL also goes on the clipboard: Link sticker, paste, post. The card leaves the lower
/// third empty for that sticker.
@MainActor
enum InstagramStory {
    /// The Facebook App ID Instagram requires (developers.facebook.com, no review needed for sharing). Public, not a secret.
    /// ponytail: the Meta Wearables app's ID, on trial as Instagram's source app (Meta's developer SMS never arrived): the
    /// same META_APP_ID secret CI bakes into Info.plist's MWDAT dict. If Instagram says the app doesn't support sharing
    /// to Stories, a dedicated Facebook app's ID is needed instead.
    static let facebookAppID: String = {
        let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any]
        return mwdat?["MetaAppID"] as? String ?? ""
    }()

    private static var scheme: URL? { URL(string: "instagram-stories://share?source_application=" + facebookAppID) }

    /// Configured and Instagram installed (needs `instagram-stories` in LSApplicationQueriesSchemes).
    static var available: Bool {
        guard !facebookAppID.isEmpty, let scheme else { return false }
        return UIApplication.shared.canOpenURL(scheme)
    }

    /// Grabs the outgoing frame (only while live and blur isn't stalled, like the Live post), renders the card and opens
    /// Instagram. Without a frame (glasses passthrough) the card is text on black.
    static func share(_ streamer: Streamer) async {
        var frame: UIImage?
        if let jpeg = await FrameGrab.shared.next(), streamer.live, streamer.privacy?.stalled != true {
            frame = UIImage(data: jpeg)
        }
        await handOver(frame: frame)
    }

    /// Settings' test button: the same hand-over without a stream frame, so the App ID and the pasted link can be
    /// checked without going live.
    static func shareTest() async { await handOver(frame: nil) }

    private static func handOver(frame: UIImage?) async {
        guard available, let scheme else { return }
        let post = LivePost.shared
        let link = post.slug.isEmpty ? "" : "https://kick.com/" + post.slug
        let story = StoryCard(frame: frame, title: post.title, link: link, template: .current, theme: .current)
        let renderer = ImageRenderer(content: story)
        renderer.scale = 3
        guard let card = renderer.uiImage?.jpegData(compressionQuality: 0.9) else { return }
        // Sent as a sticker on a background layer of the card's own edge colour: Instagram places a shared image as a
        // resizable layer either way, and a matching background makes the margin around it disappear.
        let edge = ColorTheme.hex(story.edge)
        let item: [String: Any] = ["com.instagram.sharedSticker.stickerImage": card,
                                   "com.instagram.sharedSticker.backgroundTopColor": edge,
                                   "com.instagram.sharedSticker.backgroundBottomColor": edge]
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date().addingTimeInterval(300)])
        _ = await UIApplication.shared.open(scheme)
        applog("reach", "instagram story card handed over (frame: \(frame != nil))")
        guard !link.isEmpty else { return }
        // FOUND BUG: a link on the pasteboard at hand-over got pasted into the story by Instagram itself. It's copied
        // once Instagram has taken the card instead, for the Link sticker (a background task keeps this app awake).
        let task = UIApplication.shared.beginBackgroundTask(withName: "story link", expirationHandler: nil)
        try? await Task.sleep(for: .seconds(3))
        UIPasteboard.general.string = link
        UIApplication.shared.endBackgroundTask(task)
    }
}
