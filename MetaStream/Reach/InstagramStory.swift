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
        let renderer = ImageRenderer(content: StoryCard(frame: frame, title: post.title, link: link))
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

/// The story card, designed at 360x640 points (9:16), rendered at scale 3. Flat and minimal: black, the stream frame as a
/// 16:9 card, a red LIVE pill, title and link; the bottom third stays empty for the Link sticker.
private struct StoryCard: View {
    let frame: UIImage?
    let title: String
    let link: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("● LIVE on Kick")
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red, in: Capsule())
            if let frame {
                Image(uiImage: frame).resizable().aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: 312, height: 175.5).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if !title.isEmpty { Text(title).font(.system(size: 24, weight: .bold)).lineLimit(3) }
            if !link.isEmpty {
                Text(link.replacingOccurrences(of: "https://", with: "")).font(.system(size: 15)).foregroundStyle(.gray)
            }
            Spacer(minLength: 0)   // the Link sticker goes here
        }
        .foregroundStyle(.white)
        .padding(24)
        .padding(.top, 60)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background(Color.black)
        .environment(\.layoutDirection, .leftToRight)
    }
}
