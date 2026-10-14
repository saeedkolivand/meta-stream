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
/// Animated emotes play: 7TV's animated file (not `static_name`), Kick's and BTTV's GIF/WebP are decoded into all
/// frames + delays (ImageIO, capped at 60 frames) and `image(for:at:)` picks the frame for a given time. FFZ stays static.
@MainActor
final class Emotes: ObservableObject {
    @Published private(set) var byName: [String: URL] = [:]
    @Published private(set) var images: [URL: Image] = [:]   // decoded static frames, by emote URL

    private var animations: [URL: Animation] = [:]   // multi-frame emotes only; `images` holds frame 0 of everything
    private var loadedFor: String?   // "<twitch id>|<kick slug>" the current byName was built for; "|" = none
    private var loadingImages: Set<URL> = []

    /// Fetches every provider's global set, plus per-channel sets when `twitchLogin` is given and connected.
    /// No-ops if already loaded for this exact identity, so repeat calls from every `startChat()` re-run
    /// (voice toggle flips, channel edits) don't re-hit six APIs for nothing.
    func load(twitchID: String?, kickSlug: String? = nil) async {
        let key = twitchID ?? ""
        let slug = kickSlug ?? ""
        guard "\(key)|\(slug)" != loadedFor else { return }
        loadedFor = "\(key)|\(slug)"

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
        if !slug.isEmpty { map.merge(await Self.sevenTVKick(slug: slug)) { _, new in new } }
        byName = map
        applog("chat", "emotes loaded: \(map.count) names (twitch=\(key.isEmpty ? "none" : key), kick=\(slug.isEmpty ? "none" : slug))")
    }

    /// Decoded image for an emote URL, or nil while it's still loading (caller re-renders once it lands).
    /// With `at`, an animated emote returns the frame for that moment; without it (or while the phone is
    /// thermally serious) the first frame. URLSession's own URLCache handles the network-level cache; these
    /// dictionaries only avoid re-decoding the same bytes on every row re-render. ponytail: never evicted -
    /// emote vocabulary in one stream session is small, an LRU here would be solving a problem this app doesn't have.
    func image(for url: URL, at time: Date? = nil) -> Image? {
        if let anim = animations[url], let time, !Self.isHot {
            return anim.images[Self.frameIndex(delays: anim.delays, at: time.timeIntervalSinceReferenceDate)]
        }
        if let img = images[url] { return img }
        if loadingImages.insert(url).inserted {
            Task {
                defer { loadingImages.remove(url) }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let decoded = await Task.detached(priority: .utility, operation: { Self.decode(data) }).value
                else {
                    applog("chat", "emote image failed: \(url)", error: true)
                    return
                }
                let frames = decoded.frames.map { Image(decorative: $0, scale: Self.pixelScale) }
                if frames.count > 1 { animations[url] = Animation(images: frames, delays: decoded.delays) }
                images[url] = frames[0]   // last: this is the @Published write that re-renders the rows
            }
        }
        return nil
    }

    /// True when `url` decoded to more than one frame.
    func isAnimated(_ url: URL) -> Bool { animations[url] != nil }

    /// True when the message holds a loaded animated emote and the phone is cool enough to play it - the
    /// caller's cue to keep re-rendering on a 10 fps tick.
    func animates(_ text: String) -> Bool {
        guard !Self.isHot, !animations.isEmpty else { return false }
        return Self.tokenize(text, byName: byName).contains { run in
            if case .emote(let url) = run { return isAnimated(url) }
            return false
        }
    }

    /// Frames of one animated emote, already scaled to the inline height.
    private struct Animation {
        let images: [Image]
        let delays: [Double]
    }

    private nonisolated static let pointHeight: CGFloat = 22
    private nonisolated static let pixelScale: CGFloat = 3   // render px per point; plenty for any iPhone and the stream bitmap
    // ponytail: 60-frame ceiling per emote (evenly sampled beyond it) bounds memory; 10 fps is the callers' tick.
    private nonisolated static let maxFrames = 60

    private static var isHot: Bool { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }

    /// Frame to show `t` seconds into the loop: position of (t mod total) in the cumulative delays.
    nonisolated static func frameIndex(delays: [Double], at t: Double) -> Int {
        let total = delays.reduce(0, +)
        guard total > 0 else { return 0 }
        var rest = t.truncatingRemainder(dividingBy: total)
        if rest < 0 { rest += total }
        for (i, d) in delays.enumerated() {
            if rest < d { return i }
            rest -= d
        }
        return delays.count - 1
    }

    struct Decoded: @unchecked Sendable {   // CGImage is immutable; safe to hand across actors
        let frames: [CGImage]
        let delays: [Double]
    }

    /// All frames (evenly sampled down to maxFrames, skipped frames' time folded into the kept one) scaled to the
    /// inline height. Providers hand back wildly different native pixel sizes (7TV's 2x ~64px, BTTV's 2x ~56px,
    /// Kick's "fullsize" bigger still), so every frame is thumbnailed to the same height. Any failure after the
    /// first frame falls back to a static emote; nil only when not even frame 0 decodes.
    nonisolated static func decode(_ data: Data) -> Decoded? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        let targetPx = pointHeight * pixelScale
        // Thumbnail bounds the LONGER side, so scale it up by the aspect ratio to land on the target height.
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? Double) ?? 1
        let h = max((props?[kCGImagePropertyPixelHeight] as? Double) ?? 1, 1)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((targetPx * max(w / h, 1)).rounded(.up)),
        ]
        let picked = count > maxFrames ? (0..<maxFrames).map { Int(Double($0) * Double(count) / Double(maxFrames)) } : Array(0..<count)
        var frames: [CGImage] = []
        var delays: [Double] = []
        for (n, i) in picked.enumerated() {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) else { break }
            let next = n + 1 < picked.count ? picked[n + 1] : count
            frames.append(cg)
            delays.append((i..<next).reduce(0) { $0 + delay(src, $1) })
        }
        guard !frames.isEmpty else { return nil }
        if frames.count < picked.count { return Decoded(frames: [frames[0]], delays: [delays[0]]) }   // partial decode: static
        return Decoded(frames: frames, delays: delays)
    }

    /// Per-frame delay in seconds: unclamped GIF/WebP value, else the clamped one, default 0.1, never under 0.02.
    private nonisolated static func delay(_ src: CGImageSource, _ index: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let webp = props?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (webp?[kCGImagePropertyWebPUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? (webp?[kCGImagePropertyWebPDelayTime] as? Double)
            ?? 0.1
        return max(d, 0.02)
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

    /// 7TV serves Kick channels by Kick *user* id (`user_id` in kick.com's channel lookup), not the channel id.
    private static func sevenTVKick(slug: String) async -> [String: URL] {
        var req = URLRequest(url: URL(string: "https://kick.com/api/v2/channels/\(slug)")!)
        req.setValue(KickChatProvider.userAgent, forHTTPHeaderField: "User-Agent")
        guard let data = try? await URLSession.shared.data(for: req).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userID = chatInt(json["user_id"])
        else { return [:] }
        let seven: [String: Any]? = await fetchJSON("https://7tv.io/v3/users/kick/\(userID)")
        return sevenTVEmotes((seven?["emote_set"] as? [String: Any])?["emotes"])
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
            // Prefer 2x for a crisp inline glyph on Retina. Animated emotes use the animated file itself;
            // everything else keeps static_name (a genuinely non-animated WebP).
            let file = files.first { $0["name"] as? String == "2x.webp" } ?? files.first { $0["name"] as? String == "1x.webp" }
            let animated = (e["data"] as? [String: Any])?["animated"] as? Bool == true
            guard let fileName = animated ? file?["name"] as? String : file?["static_name"] as? String,
                  let url = URL(string: "https:" + hostURL + "/" + fileName) else { continue }
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

