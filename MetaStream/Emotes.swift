import Foundation
import SwiftUI
import UIKit

/// Third-party emote lookup for the native chat list: 7TV, BTTV and FFZ global + per-channel sets, fetched
/// once per chat connect into a flat name -> image URL map. Kick emotes need no fetch at all - they arrive
/// inline in message text as `[emote:12345:name]` and `tokenize` turns those into a CDN URL directly.
///
/// Response shapes below were verified live against the real APIs (curl), not guessed from memory:
///   7TV    GET 7tv.io/v3/emote-sets/global            -> {"emotes":[{"name","data":{"host":{"url","files":[...]}}}]}
///   7TV    GET 7tv.io/v3/users/twitch/{id}            -> {"emote_set":{"emotes":[...same shape...]}}
///   BTTV   GET api.betterttv.net/3/cached/emotes/global      -> [{"id","code",...}]
///   BTTV   GET api.betterttv.net/3/cached/users/twitch/{id}  -> {"channelEmotes":[...],"sharedEmotes":[...]}
///   FFZ    GET api.frankerfacez.com/v1/set/global      -> {"default_sets":[Int],"sets":{"<id>":{"emoticons":[{"name","urls":{"1","2","4"}}]}}}
///   FFZ    GET api.frankerfacez.com/v1/room/id/{id}    -> {"room":{"set":Int},"sets":{...same as above...}}
/// A 7TV emote's `host.files` always carries a `static_name` (equal to `name` itself when the emote isn't
/// animated) - that's a genuinely single-frame WebP, which is what makes the "static frame only" rule in
/// this file actually true for 7TV. BTTV/FFZ serve PNG/GIF/WebP with no separate static variant; ImageIO
/// only decodes the first frame of those anyway when built into a single UIImage, so the same rule holds
/// by accident rather than by API design.
@MainActor
final class Emotes: ObservableObject {
    @Published private(set) var byName: [String: URL] = [:]
    @Published private(set) var images: [URL: Image] = [:]   // decoded static frames, by emote URL

    private var loadedFor: String?   // twitch login (lowercased) the current byName was built for; "" = none
    private var loadingImages: Set<URL> = []

    /// Fetches every provider's global set, plus per-channel sets when `twitchLogin` is given and connected.
    /// No-ops if already loaded for this exact identity, so repeat calls from every `startChat()` re-run
    /// (voice toggle flips, channel edits) don't re-hit six APIs for nothing.
    func load(twitchID: String?) async {
        let key = twitchID ?? ""
        guard key != loadedFor else { return }
        loadedFor = key

        async let sevenGlobal = Self.sevenTV(id: nil)
        async let bttvGlobal = Self.bttv(id: nil)
        async let ffzGlobal = Self.ffz(id: nil)
        var map: [String: URL] = [:]
        map.merge(await sevenGlobal) { _, new in new }
        map.merge(await bttvGlobal) { _, new in new }
        map.merge(await ffzGlobal) { _, new in new }

        if !key.isEmpty {
            async let sevenUser = Self.sevenTV(id: key)
            async let bttvUser = Self.bttv(id: key)
            async let ffzRoom = Self.ffz(id: key)
            map.merge(await sevenUser) { _, new in new }
            map.merge(await bttvUser) { _, new in new }
            map.merge(await ffzRoom) { _, new in new }
        }
        byName = map
        applog("chat", "emotes loaded: \(map.count) names (twitch=\(key.isEmpty ? "none" : key))")
    }

    /// Decoded image for an emote URL, or nil while it's still loading (caller re-renders once it lands).
    /// URLSession's own URLCache handles the network-level cache; this dictionary only avoids re-decoding
    /// the same WebP/PNG bytes on every row re-render. ponytail: never evicted - emote vocabulary in one
    /// stream session is small, an LRU here would be solving a problem this app doesn't have.
    func image(for url: URL) -> Image? {
        if let img = images[url] { return img }
        if loadingImages.insert(url).inserted {
            Task {
                defer { loadingImages.remove(url) }
                guard let (data, _) = try? await URLSession.shared.data(from: url), let raw = UIImage(data: data) else {
                    applog("chat", "emote image failed: \(url)", error: true)
                    return
                }
                images[url] = Image(uiImage: Self.resized(raw, toHeight: 22))
            }
        }
        return nil
    }

    /// Providers hand back wildly different native pixel sizes (7TV's 2x ~64px, BTTV's 2x ~56px, FFZ's "2" ~56px,
    /// Kick's "fullsize" bigger still) and a plain `UIImage(data:)` has scale 1.0, so dropped straight into Text
    /// it would render at its raw pixel size - way too large inline. Redrawing at a fixed point height keeps
    /// every emote the same visual size next to body text, regardless of source.
    private static func resized(_ image: UIImage, toHeight height: CGFloat) -> UIImage {
        let scale = height / max(image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: height)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: - Tokenizer

    enum Run: Equatable, Sendable { case text(String), emote(URL) }

    /// Splits a chat message into text/emote runs: Kick's inline `[emote:id:name]` tokens (unambiguous,
    /// checked first) and any whitespace-delimited word that exactly matches a name in `byName`. Matching
    /// is case-sensitive and whole-word only, same as every other chat client's emote rendering - "POGGERS"
    /// mid-word doesn't light up. ponytail: splits on a single space; a message with double spaces gets an
    /// extra empty text run between words, which renders as nothing - harmless, not worth a real tokenizer.
    static func tokenize(_ text: String, byName: [String: URL]) -> [Run] {
        var runs: [Run] = []
        let nsText = text as NSString
        var lastEnd = text.startIndex
        for match in SharedPatterns.kickEmote.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            if lastEnd < range.lowerBound {
                runs.append(contentsOf: wordRuns(String(text[lastEnd..<range.lowerBound]), byName: byName))
            }
            let id = nsText.substring(with: match.range(at: 1))
            if let url = URL(string: "https://files.kick.com/emotes/\(id)/fullsize") { runs.append(.emote(url)) }
            lastEnd = range.upperBound
        }
        if lastEnd < text.endIndex {
            runs.append(contentsOf: wordRuns(String(text[lastEnd...]), byName: byName))
        }
        return runs
    }

    private static func wordRuns(_ text: String, byName: [String: URL]) -> [Run] {
        guard !text.isEmpty else { return [] }
        var runs: [Run] = []
        var buffer = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if let url = byName[w] {
                if !buffer.isEmpty { runs.append(.text(buffer)); buffer = "" }
                runs.append(.emote(url))
            } else if !w.isEmpty {
                buffer += buffer.isEmpty ? w : " " + w
            }
        }
        if !buffer.isEmpty { runs.append(.text(buffer)) }
        return runs
    }

    // MARK: - 7TV

    /// Global set when `id` is nil, per-channel set otherwise. One function covers both callers.
    private static func sevenTV(id: String?) async -> [String: URL] {
        if let id {
            let json: [String: Any]? = await fetchJSON("https://7tv.io/v3/users/twitch/\(id)")
            guard let json, let set = json["emote_set"] as? [String: Any] else { return [:] }
            return sevenTVEmotes(set["emotes"])
        } else {
            let json: [String: Any]? = await fetchJSON("https://7tv.io/v3/emote-sets/global")
            guard let json else { return [:] }
            return sevenTVEmotes(json["emotes"])
        }
    }

    private static func sevenTVEmotes(_ raw: Any?) -> [String: URL] {
        guard let emotes = raw as? [[String: Any]] else { return [:] }
        var out: [String: URL] = [:]
        for e in emotes {
            guard let name = e["name"] as? String,
                  let host = (e["data"] as? [String: Any])?["host"] as? [String: Any],
                  let hostURL = host["url"] as? String,
                  let files = host["files"] as? [[String: Any]]
            else { continue }
            // Prefer 2x for a crisp inline glyph on Retina; static_name is a genuinely non-animated WebP.
            let file = files.first { $0["name"] as? String == "2x.webp" } ?? files.first { $0["name"] as? String == "1x.webp" }
            guard let staticName = file?["static_name"] as? String, let url = URL(string: "https:" + hostURL + "/" + staticName) else { continue }
            out[name] = url
        }
        return out
    }

    // MARK: - BTTV

    private static func bttv(id: String?) async -> [String: URL] {
        if let id {
            let json: [String: Any]? = await fetchJSON("https://api.betterttv.net/3/cached/users/twitch/\(id)")
            guard let json else { return [:] }
            var out = bttvEmotes(json["channelEmotes"] as? [[String: Any]] ?? [])
            out.merge(bttvEmotes(json["sharedEmotes"] as? [[String: Any]] ?? [])) { _, new in new }
            return out
        } else {
            let arr: [[String: Any]]? = await fetchJSON("https://api.betterttv.net/3/cached/emotes/global")
            return bttvEmotes(arr ?? [])
        }
    }

    /// BTTV's CDN serves the image straight off `/emote/{id}/{size}` with no extension - content type comes
    /// from the response header, ImageIO doesn't need the extension either.
    private static func bttvEmotes(_ arr: [[String: Any]]) -> [String: URL] {
        var out: [String: URL] = [:]
        for e in arr {
            guard let code = e["code"] as? String, let id = e["id"] as? String,
                  let url = URL(string: "https://cdn.betterttv.net/emote/\(id)/2x")
            else { continue }
            out[code] = url
        }
        return out
    }

    // MARK: - FFZ

    private static func ffz(id: String?) async -> [String: URL] {
        if let id {
            let json: [String: Any]? = await fetchJSON("https://api.frankerfacez.com/v1/room/id/\(id)")
            guard let json, let setID = (json["room"] as? [String: Any])?["set"] as? Int else { return [:] }
            return ffzEmotes(json, setIDs: [setID])
        } else {
            let json: [String: Any]? = await fetchJSON("https://api.frankerfacez.com/v1/set/global")
            guard let json, let sets = json["default_sets"] as? [Int] else { return [:] }
            return ffzEmotes(json, setIDs: sets)
        }
    }

    private static func ffzEmotes(_ json: [String: Any], setIDs: [Int]) -> [String: URL] {
        guard let sets = json["sets"] as? [String: Any] else { return [:] }
        var out: [String: URL] = [:]
        for id in setIDs {
            guard let emoticons = (sets["\(id)"] as? [String: Any])?["emoticons"] as? [[String: Any]] else { continue }
            for e in emoticons {
                guard let name = e["name"] as? String, let urls = e["urls"] as? [String: String],
                      let urlString = urls["2"] ?? urls["1"] ?? urls.values.first, let url = URL(string: urlString)
                else { continue }
                out[name] = url
            }
        }
        return out
    }

    // MARK: - shared HTTP

    private static func fetchJSON<T>(_ urlString: String) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? T
        } catch {
            applog("chat", "emote fetch failed \(urlString): \(error.localizedDescription)", error: true)
            return nil
        }
    }
}

