import SwiftUI
import WebKit

/// Kick slash commands the public API lacks, run from a hidden signed-in kick.com page (adr/0005).
/// Endpoints captured from kick.com's own requests on 2026-10-17; unofficial, can change any day.
/// Never logs cookies, tokens or response bodies.
@MainActor
final class KickWeb: ObservableObject {
    static let shared = KickWeb()
    static let commands = ["slow", "emoteonly", "followers", "followonly", "subscribers", "raid", "clip", "clear", "poll", "polldelete",
                           "mod", "unmod", "vip", "unvip", "prediction"]
    @Published private(set) var user = ""     // signed-in username; "" = not signed in
    var signedIn: Bool { !user.isEmpty }
    private var slug = ""
    private var channelId: Int?
    private var web: WKWebView?

    // MARK: pure parts -- see Self.demo()

    /// PATCH body for /slow, /emoteonly, /followonly (/followers); nil for anything else.
    static func modeBody(_ name: String, _ a: [String]) -> String? {
        let off = a.first?.lowercased() == "off", n = a.compactMap { Int($0) }.first
        switch name {
        case "slow": return #"{"slow_mode":{"enabled":\#(!off),"duration_seconds":\#(off ? 1 : max(n ?? 5, 1))}}"#
        case "emoteonly": return #"{"emotes_only_mode":{"enabled":\#(!off)}}"#
        case "followonly", "followers": return #"{"followers_only_mode":{"enabled":\#(!off),"duration_seconds":\#(off ? 1 : max((n ?? 0) * 60, 1))}}"#
        default: return nil
        }
    }

    /// "/poll Question? | a | b": 2...6 options of at least 2 characters (kick.com's rule). nil = invalid.
    static func poll(_ a: [String]) -> (title: String, options: [String])? {
        let p = a.joined(separator: " ").split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let title = p.first, !title.isEmpty, (2...6).contains(p.count - 1), p.dropFirst().allSatisfy({ $0.count >= 2 }) else { return nil }
        return (title, Array(p.dropFirst()))
    }

    // MARK: session

    /// Reads the signed-in user from the page, loading kick.com first if needed.
    func refresh() async {
        guard let w = await page("/") else { return }
        let r = await fetch(w, "GET", "/api/v1/user", nil)
        let j = Self.json(r.text)
        user = (r.status == 200 ? j["username"] as? String : nil) ?? ""
        slug = user.isEmpty ? "" : (j["streamer_channel"] as? [String: Any])?["slug"] as? String ?? ""
    }

    func ready() async -> Bool {
        if !signedIn { await refresh() }
        return signedIn
    }

    func signOut() async {
        let s = WKWebsiteDataStore.default(), types = WKWebsiteDataStore.allWebsiteDataTypes()
        await s.removeData(ofTypes: types, for: await s.dataRecords(ofTypes: types).filter { $0.displayName.contains("kick.com") })
        web?.removeFromSuperview()
        web = nil
        channelId = nil
        user = ""
        slug = ""
        applog("chat", "kick.com session removed")
    }

    // MARK: commands

    /// One-line note for the streamer.
    func run(_ cmd: String, _ a: [String]) async -> String {
        let name = cmd == "followers" ? "followonly" : cmd   // kick.com's own name
        guard await ready() else { return "Sign in to kick.com in Settings to use /\(cmd)" }
        if name == "prediction" { return "Kick predictions open a dialog on kick.com; not supported yet" }
        if name == "subscribers" { return "Kick has no subscriber-only mode" }
        guard let w = await page("/popout/\(slug)/chat") else { return "kick.com chat isn't ready; try again" }
        let typed = "/" + ([name] + a).joined(separator: " ")
        let api = "https://kick.com/api/v2/channels/\(slug)/polls"
        let req: (method: String, url: String, body: String?)
        switch name {
        case "poll":
            guard let p = Self.poll(a) else { return "Usage: /poll Question? | option 1 | option 2 (2-6 options, each at least 2 characters)" }
            // ponytail: fixed 30 s duration, the only value verified.
            let body: [String: Any] = ["title": p.title, "options": p.options, "duration": 30, "result_display_duration": 15]
            req = ("POST", api, (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) })
        case "polldelete":
            req = ("DELETE", api, nil)   // UNVERIFIED: the captured test poll had already expired
        case "slow", "emoteonly", "followonly":
            guard let id = await channel(w), let body = Self.modeBody(name, a) else { return "Couldn't find your kick.com channel" }
            req = ("PATCH", "https://web.kick.com/api/v1/channels/\(id)/chat/settings", body)
        default:   // clear, raid, clip, mod, unmod, vip, unvip: no known endpoint, type it like a person
            return await type(w, typed)
        }
        let r = await fetch(w, req.method, req.url, req.body)
        applog("chat", "kick.com /\(name) -> HTTP \(r.status)")
        if (200..<300).contains(r.status) { return "Done: \(typed)" }
        if r.status == 401 || r.status == 403 { return "kick.com session expired — sign in again in Settings" }
        return await type(w, typed)
    }

    /// The channel id (not the user id), cached.
    private func channel(_ w: WKWebView) async -> Int? {
        if channelId == nil { channelId = Self.json((await fetch(w, "GET", "/api/v2/channels/\(slug)", nil)).text)["id"] as? Int }
        return channelId
    }

    /// Types the command into the page's chat box and presses Enter. No confirmation is available.
    private func type(_ w: WKWebView, _ text: String) async -> String {
        let js = """
        const els = [...document.querySelectorAll('[contenteditable="true"]')].filter(e => e.offsetParent !== null);
        const el = els[els.length - 1];
        if (!el) return 'none';
        el.focus();
        document.execCommand('insertText', false, text);
        el.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
        return 'ok';
        """
        for _ in 0..<5 {   // the popout may still be loading
            if (try? await w.callAsyncJavaScript(js, arguments: ["text": text], in: nil, contentWorld: .page)) as? String == "ok" {
                return "Sent \(text) through kick.com"
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return "kick.com chat isn't ready; try again"
    }

    // MARK: page

    private func fetch(_ w: WKWebView, _ method: String, _ url: String, _ body: String?) async -> (status: Int, text: String) {
        let js = """
        const tok = decodeURIComponent((document.cookie.match(/(?:^|; )session_token=([^;]*)/) || [])[1] || '');
        const headers = {Authorization: 'Bearer ' + tok, Accept: 'application/json', 'Content-Type': 'application/json'};
        try {
            const r = await fetch(url, {method, credentials: 'include', headers, body});
            return {status: r.status, text: await r.text()};
        } catch (e) { return {status: 0, text: String(e)}; }
        """
        let args: [String: Any] = ["url": url, "method": method, "body": body ?? NSNull()]
        let r = (try? await w.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .page)) as? [String: Any]
        return (r?["status"] as? Int ?? 0, r?["text"] as? String ?? "")
    }

    private static func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    /// The hidden web view, on a kick.com page ("/" = any kick.com page, else the popout chat).
    // ponytail: attached to the key window like BrowserFeed's hosts (1x1, alpha 0.01) so WebKit keeps running its timers.
    private func page(_ path: String) async -> WKWebView? {
        if web == nil {
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: WKWebViewConfiguration())   // default persistent store
            w.alpha = 0.01
            w.isUserInteractionEnabled = false
            window.insertSubview(w, at: 0)
            web = w
        }
        guard let w = web else { return nil }
        let there = w.url?.host == "kick.com" && (path == "/" || w.url?.path.hasPrefix("/popout/") == true)
        if !there, let u = URL(string: "https://kick.com" + path) {
            w.load(URLRequest(url: u))
            for _ in 0..<75 where w.isLoading || w.url == nil { try? await Task.sleep(for: .milliseconds(200)) }
        }
        return w
    }

    #if DEBUG
    static func demo() {
        assert(modeBody("slow", ["on"]) == #"{"slow_mode":{"enabled":true,"duration_seconds":5}}"#)
        assert(modeBody("slow", ["30"]) == #"{"slow_mode":{"enabled":true,"duration_seconds":30}}"#)
        assert(modeBody("slow", ["off"]) == #"{"slow_mode":{"enabled":false,"duration_seconds":1}}"#)
        assert(modeBody("emoteonly", []) == #"{"emotes_only_mode":{"enabled":true}}"#)
        assert(modeBody("emoteonly", ["off"]) == #"{"emotes_only_mode":{"enabled":false}}"#)
        assert(modeBody("followonly", ["on", "10"]) == #"{"followers_only_mode":{"enabled":true,"duration_seconds":600}}"#)
        assert(modeBody("followers", ["on", "0"]) == #"{"followers_only_mode":{"enabled":true,"duration_seconds":1}}"#)
        assert(modeBody("followers", ["off"]) == #"{"followers_only_mode":{"enabled":false,"duration_seconds":1}}"#)
        assert(modeBody("subscribers", []) == nil)
        let p = poll(["Best?", "|", "Cats", "|", "Dogs"])
        assert(p?.title == "Best?" && p?.options == ["Cats", "Dogs"])
        assert(poll(["Q?", "|", "a", "|", "bb"]) == nil && poll(["Q?", "|", "aa"]) == nil && poll(["|", "aa", "|", "bb"]) == nil)
        assert(poll(["Q", "|", "1a", "|", "2b", "|", "3c", "|", "4d", "|", "5e", "|", "6f", "|", "7g"]) == nil)
        applog("chat", "KickWeb.demo() passed")
    }
    #endif
}

/// Settings row: the kick.com session the unofficial commands run through.
struct KickSessionSection: View {
    @ObservedObject var kick = KickWeb.shared
    @State private var signingIn = false

    var body: some View {
        Section {
            Text(kick.signedIn ? "Signed in as \(kick.user)" : "Not signed in")
                .task { await kick.refresh() }
            // On the row, not the Section: a Section hands its modifiers to every row, and two sheets on one binding
            // dismissed each other the moment the login page opened.
            Button("Sign in to kick.com") { signingIn = true }
                .sheet(isPresented: $signingIn, onDismiss: { Task { await kick.refresh() } }) {
                    NavigationStack {
                        LoginWeb().ignoresSafeArea().navigationTitle("kick.com").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { signingIn = false } } }
                    }
                }
            if kick.signedIn { Button("Sign out", role: .destructive) { Task { await kick.signOut() } } }
        } header: { Text("kick.com session (unofficial)") } footer: {
            Text("Used for /poll, /raid, /clear, /clip and chat modes, which Kick's API doesn't offer. Unofficial: Kick can change it any time.")
        }
    }
}

/// Visible kick.com login page; the user signs in themselves. Shares the default (persistent) data store.
private struct LoginWeb: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.load(URLRequest(url: URL(string: "https://kick.com/login")!))
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {}
}
