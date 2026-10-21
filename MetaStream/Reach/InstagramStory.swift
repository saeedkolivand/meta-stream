import SwiftUI

/// "Share to Instagram story" while live: a 9:16 card (a frame from the stream, LIVE, the title and the Kick link) handed
/// to Instagram's story editor through the pasteboard, per Meta's Sharing to Stories (iOS). The tappable link can't be
/// pre-placed by an app, so the card shows the Kick URL and leaves the lower third empty for the Link sticker.
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
    /// Instagram. Without a frame (glasses passthrough) the card is text on black. Before GO LIVE it says "live soon".
    static func share(_ streamer: Streamer) async {
        guard streamer.live else { await handOver(frame: nil, soon: true); return }
        var frame: UIImage?
        if let jpeg = await FrameGrab.shared.next(), streamer.live, streamer.privacy?.stalled != true {
            frame = UIImage(data: jpeg)
        }
        await handOver(frame: frame)
    }

    /// Settings' test button: the same hand-over without a stream frame, to check it without going live.
    static func shareTest() async { await handOver(frame: nil) }

    private static func handOver(frame: UIImage?, soon: Bool = false) async {
        guard available, let scheme else { return }
        let post = LivePost.shared
        let link = post.slug.isEmpty ? "" : "https://kick.com/" + post.slug
        let story = StoryCard(frame: frame, title: post.title, link: link, template: .current, theme: .current, soon: soon)
        let renderer = ImageRenderer(content: story)
        renderer.scale = 3
        guard let image = renderer.uiImage, let card = image.jpegData(compressionQuality: 0.9) else { return }
        // The full-screen background (Meta: >= 720x1280, 9:16), plus the background layer in the card's own edge colour:
        // where Instagram shows the image as a shrunken, resizable layer instead (seen on the iPad app), the margin
        // around it then matches the card. Spotify and X send a sticker on purpose; a live card should fill the story.
        let edge = ColorTheme.hex(story.edge)
        let item: [String: Any] = ["com.instagram.sharedSticker.backgroundImage": card,
                                   "com.instagram.sharedSticker.backgroundTopColor": edge,
                                   "com.instagram.sharedSticker.backgroundBottomColor": edge]
        applog("reach", "instagram story card \(Int(image.size.width * image.scale))x\(Int(image.size.height * image.scale)) px")
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date().addingTimeInterval(300)])
        _ = await UIApplication.shared.open(scheme)
        applog("reach", "instagram story card handed over (frame: \(frame != nil))")
        // No link on the clipboard, by experiment: one in the shared item got pasted into the story by Instagram (and
        // shrank the card into a layer), and iOS drops writes from an app in the background (logged hasStrings false
        // after copies at 6 and 15 s, iPad and iPhone). The link is printed on the card; the Link sticker is typed.
    }
}
