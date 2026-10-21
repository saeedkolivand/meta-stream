// Spotify "now playing" for the Now playing widget and the {song} / {artist} tokens. PKCE login (no client secret),
// then GET /me/player/currently-playing every 3 s while something on screen uses it (retain / release, like
// WidgetLocation). Spotify reports whatever the account plays on any device, so the phone's Spotify app is enough.
// Since Feb 2026 a Development Mode app only works while the account that owns it has Premium.
import Foundation
import UIKit

struct NowPlayingTrack: Equatable, Sendable {
    var id: String            // Spotify item id; a change of id is a song change
    var title: String
    var artist: String
    var artURL: String
    var durationMs: Int
    var progressMs: Int
    var at: Date              // when progressMs was read

    /// Playback position now, extrapolated from the last poll (the poll only says where it was).
    func elapsedMs(_ now: Date = Date()) -> Int { min(durationMs, progressMs + Int(now.timeIntervalSince(at) * 1000)) }
    func progress(_ now: Date = Date()) -> Double { durationMs > 0 ? Double(elapsedMs(now)) / Double(durationMs) : 0 }
}

@MainActor
final class SpotifyNowPlaying: ObservableObject {
    static let shared = SpotifyNowPlaying()

    /// nil while nothing plays (paused, stopped, an ad, not connected): widgets hide.
    @Published private(set) var track: NowPlayingTrack?
    /// Cover of `track`, nil until downloaded (designs draw their placeholder until then).
    @Published private(set) var art: UIImage?
    @Published private(set) var connected: Bool
    @Published var status = ""

    // ponytail: public PKCE client id (no secret exists), so it lives in code rather than a CI secret.
    static let clientID = "b8b8964ddeab49809d9f9ae1cf9b468e"
    private let store = KeychainTokenStore()
    private let auth = AuthPresenter()
    private var users = 0
    private var poll: Task<Void, Never>?
    private var artFor = ""

    private init() { connected = store.string(forKey: "spotifyRefresh") != nil }

    func retain() {
        users += 1
        if users == 1 { poll = Task { await loop() } }
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { poll?.cancel(); poll = nil }
    }

    // MARK: login

    func connect() {
        Task {
            let verifier = PlatformNet.random(64)
            var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
            c.queryItems = [
                .init(name: "response_type", value: "code"), .init(name: "client_id", value: Self.clientID),
                .init(name: "redirect_uri", value: PlatformConfig.webRedirect),
                .init(name: "scope", value: "user-read-currently-playing user-read-playback-state"),
                .init(name: "code_challenge", value: PlatformNet.s256(verifier)), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: PlatformNet.random(16)),
            ]
            await PlatformFlow.codeFlow(name: "Spotify", authURL: c.url!, scheme: "metastream",
                authorize: auth.authorize,
                exchange: { code in try await PlatformNet.form("https://accounts.spotify.com/api/token", [
                    "grant_type": "authorization_code", "client_id": Self.clientID, "redirect_uri": PlatformConfig.webRedirect,
                    "code_verifier": verifier, "code": code]) },
                prefix: "spotify", store: store,
                status: { self.status = $0 },
                after: {
                    self.connected = true
                    if self.users > 0 { self.poll?.cancel(); self.poll = Task { await self.loop() } }
                })
        }
    }

    func disconnect() {
        store.forget("spotify")
        connected = false
        track = nil; art = nil; artFor = ""
        status = "Spotify disconnected"
    }

    // MARK: polling

    private func loop() async {
        while !Task.isCancelled, users > 0 {
            var wait = 3.0
            if connected {
                do {
                    wait = try await fetch()
                } catch {
                    applog("spotify", "now playing failed: \(error.localizedDescription)", error: true)
                    status = error.localizedDescription
                    wait = 15
                }
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    /// One poll; returns seconds until the next. Near the end of a song it polls right after it ends, so the
    /// widget changes with the music instead of up to 3 s late.
    private func fetch() async throws -> Double {
        let (data, code, retryAfter) = try await get("https://api.spotify.com/v1/me/player/currently-playing")
        if code == 429 { return max(5, retryAfter ?? 30) }
        guard code == 200, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if code != 204 { throw PlatformNet.err("Spotify → HTTP \(code)") }
            set(nil)   // 204: nothing playing
            return 3
        }
        let t = Self.parse(json, at: Date())
        set(t)
        guard let t else { return 3 }
        let left = Double(t.durationMs - t.progressMs) / 1000
        return left > 0.5 && left < 3 ? left + 0.4 : 3
    }

    private func set(_ t: NowPlayingTrack?) {
        if t?.id != track?.id { applog("spotify", t.map { "now playing: \($0.title) · \($0.artist)" } ?? "nothing playing") }
        track = t
        guard let url = t?.artURL, url != artFor else { return }
        artFor = url; art = nil
        Task {
            guard let u = URL(string: url), let r = try? await URLSession.shared.data(from: u), artFor == url else { return }
            art = UIImage(data: r.0)
        }
    }

    /// GET with the access token, one refresh + retry on 401. Successful polls are not logged (one every 3 s).
    private func get(_ url: String, retried: Bool = false) async throws -> (Data, Int, Double?) {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(store.string(forKey: "spotifyAccess") ?? "")", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code == 401, !retried {
            let json = try await PlatformNet.form("https://accounts.spotify.com/api/token", [
                "grant_type": "refresh_token", "client_id": Self.clientID, "refresh_token": store.string(forKey: "spotifyRefresh") ?? ""])
            try store.saveTokens(json, prefix: "spotify")
            return try await get(url, retried: true)
        }
        if code >= 400 { applog("spotify", "HTTP \(code): \(String(decoding: data.prefix(300), as: UTF8.self))", error: true) }
        return (data, code, (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init))
    }

    /// nil unless a track is actually playing (paused, podcast episodes without artists and ads all hide the widget).
    nonisolated static func parse(_ json: [String: Any], at: Date) -> NowPlayingTrack? {
        guard json["is_playing"] as? Bool == true, json["currently_playing_type"] as? String == "track",
              let item = json["item"] as? [String: Any], let id = item["id"] as? String ?? item["uri"] as? String,
              let name = item["name"] as? String else { return nil }
        let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let images = ((item["album"] as? [String: Any])?["images"] as? [[String: Any]] ?? [])
            .sorted { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        // The smallest cover that is still sharp at widget size (Spotify sends 64, 300 and 640 px).
        let cover = images.first { ($0["width"] as? Int ?? 0) >= 300 } ?? images.last
        return NowPlayingTrack(id: id, title: name, artist: artists.joined(separator: ", "), artURL: cover?["url"] as? String ?? "",
                               durationMs: item["duration_ms"] as? Int ?? 0, progressMs: json["progress_ms"] as? Int ?? 0, at: at)
    }

    #if DEBUG
    static func demo() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let json: [String: Any] = ["is_playing": true, "currently_playing_type": "track", "progress_ms": 1000,
            "item": ["id": "x", "name": "Song", "duration_ms": 10000, "artists": [["name": "A"], ["name": "B"]],
                     "album": ["images": [["url": "big", "width": 640], ["url": "mid", "width": 300], ["url": "small", "width": 64]]]]]
        let t = parse(json, at: t0)
        assert(t?.artist == "A, B" && t?.artURL == "mid" && t?.title == "Song")
        assert(t?.elapsedMs(t0.addingTimeInterval(2)) == 3000 && t?.elapsedMs(t0.addingTimeInterval(60)) == 10000)
        var paused = json; paused["is_playing"] = false
        assert(parse(paused, at: t0) == nil)
        var ad = json; ad["currently_playing_type"] = "ad"
        assert(parse(ad, at: t0) == nil)
        applog("spotify", "SpotifyNowPlaying.demo() passed")
    }
    #endif
}
