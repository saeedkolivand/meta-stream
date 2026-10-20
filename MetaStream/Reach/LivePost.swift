import Foundation

/// The Live post (CONTEXT.md "Reach"): the one Telegram channel message a stream session owns. Announced before the
/// stream (optional), adopted when the session starts, refreshed while it runs, turned into the recap when it ends.
/// Network work runs one job at a time on `chain`; the 1 s ticks skip while a job is still pending.
@MainActor
final class LivePost: ObservableObject {
    static let shared = LivePost()

    enum Phase: String, Codable { case announced, live }

    struct State: Codable {
        var messageId: Int
        var phase: Phase
        var announcedAt: Date?
        var hasPhoto: Bool
    }

    @Published private(set) var phase: Phase?
    weak var platforms: Platforms?

    private var state: State? {
        didSet {
            phase = state?.phase
            UserDefaults.standard.set(state.flatMap { try? JSONEncoder().encode($0) }, forKey: "livePost")
        }
    }
    private var chain: Task<Void, Never>?
    private var queued = 0
    private var closing = false
    private var lastEdit = Date.distantPast
    private var lastPhoto = Date.distantPast

    private static let announcementLife: TimeInterval = 3600

    private init() {
        state = UserDefaults.standard.data(forKey: "livePost").flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        phase = state?.phase
    }

    // MARK: settings

    private var defaults: UserDefaults { .standard }
    private var lang: String { defaults.string(forKey: "telegramLang") == "en" ? "en" : "fa" }
    private func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

    var enabled: Bool {
        let channel = defaults.string(forKey: "telegramChannel") ?? ""
        return flag("telegramOn", false) && !channel.isEmpty && KeychainTokenStore().string(forKey: "telegramToken") != nil
    }

    var title: String { platforms?.kickTitle ?? "" }

    private var slug: String {
        let chosen = (defaults.string(forKey: "chatChannel") ?? "").trimmingCharacters(in: .whitespaces)
        return chosen.isEmpty ? (platforms?.kickUser ?? "").lowercased() : chosen
    }

    private var viewers: Int { platforms.map { $0.kickViewers + $0.twitchViewers + $0.ytViewers } ?? 0 }

    // MARK: before the stream

    func announce() {
        guard enabled, state == nil, queued == 0 else { return }
        let text = LivePostText.announce(title: title, slug: slug, lang: lang)
        enqueue { [self] in
            let id = try await Telegram.sendMessage(text: LivePostText.fit(text, photo: false))
            state = State(messageId: id, phase: .announced, announcedAt: Date(), hasPhoto: false)
        }
    }

    func cancelAnnouncement() {
        guard let st = state, st.phase == .announced else { return }
        state = nil
        let text = LivePostText.cancelled(lang: lang)
        enqueue { try await Telegram.editText(st.messageId, text: text) }
    }

    /// An announcement nobody went live for within the hour is withdrawn.
    private func expireIfStale() {
        guard let st = state, st.phase == .announced, let at = st.announcedAt,
              Date().timeIntervalSince(at) > Self.announcementLife else { return }
        cancelAnnouncement()
    }

    // MARK: during the stream

    func sessionStarted(_ stream: Streamer) {
        guard enabled else { return }
        closing = false
        let text = LivePostText.live(liveInput(stream), lang: lang)
        enqueue { [self] in
            if var st = state, st.phase == .announced {
                st.phase = .live
                state = st
                try await push(text)
            } else {
                let id = try await Telegram.sendMessage(text: LivePostText.fit(text, photo: false))
                state = State(messageId: id, phase: .live, announcedAt: nil, hasPhoto: false)
            }
            lastEdit = Date()
            lastPhoto = Date()
            if let jpeg = safe(await FrameGrab.shared.next(), stream) { try await push(text, jpeg: jpeg) }
        }
    }

    /// The Streamer's 1 s tick: feeds the session log and the post while live, expires a stale announcement otherwise.
    func second(_ stream: Streamer) {
        guard stream.live else { expireIfStale(); return }
        SessionLog.shared.tick(stream, viewers: viewers)
        tick(stream)
    }

    /// Every 60 s the text is rebuilt and edited; every 5 min (every 15 s until the first one works) a frame goes with it.
    /// While the link is down the reconnecting line shows and the last good photo stays.
    private func tick(_ stream: Streamer) {
        guard let st = state, st.phase == .live, !closing, queued == 0 else { return }
        let now = Date()
        let wantPhoto = stream.connectedSince != nil && now.timeIntervalSince(lastPhoto) >= (st.hasPhoto ? 300 : 15)
        let textDue = now.timeIntervalSince(lastEdit) >= 60
        guard wantPhoto || textDue else { return }
        if textDue { lastEdit = now }
        if wantPhoto { lastPhoto = now }
        let text = LivePostText.live(liveInput(stream), lang: lang)
        enqueue { [self] in
            var jpeg: Data?
            if wantPhoto { jpeg = safe(await FrameGrab.shared.next(), stream) }
            // A photo retry that found no frame (glasses passthrough never reaches the mixer) edits nothing.
            guard jpeg != nil || textDue else { return }
            try await push(text, jpeg: jpeg)
        }
    }

    /// The session is over: the post becomes the recap and keeps the last photo taken while live. No new frame: by the
    /// time this job runs stopLive() has torn the session down (blur may be off), so a fresh grab could publish a
    /// picture viewers never saw, unblurred.
    func sessionEnded(_ record: SessionRecord?) {
        guard state != nil else { return }
        closing = true
        let text = record.map { LivePostText.recap(recapInput($0), lang: lang) } ?? LivePostText.endedBare(lang: lang)
        enqueue { [self] in
            defer { state = nil }
            try await push(text)
        }
    }

    /// A grabbed frame is only published if, when it arrives, the stream is still live and not ending, and privacy
    /// blur isn't reporting a stall: the photo stays in the channel, so it must be a frame viewers saw, as they saw it.
    private func safe(_ jpeg: Data?, _ stream: Streamer) -> Data? {
        guard stream.live, !closing, stream.privacy?.stalled != true else { return nil }
        return jpeg
    }

    /// Once at launch: an old announcement is withdrawn; a post still saying live belongs to a session that died with the app.
    func resume() {
        guard let st = state else { return }
        if st.phase == .announced { expireIfStale(); return }
        state = nil
        let text = LivePostText.endedBare(lang: lang)
        enqueue { [self] in try await edit(text, id: st.messageId, photo: st.hasPhoto) }
    }

    // MARK: sending

    private func enqueue(_ job: @escaping @MainActor () async throws -> Void) {
        let previous = chain
        queued += 1
        chain = Task { [self] in
            await previous?.value
            do { try await job() } catch { fail(error) }
            queued -= 1
        }
    }

    private func fail(_ error: Error) {
        if Telegram.isGone(error) { state = nil; return }   // the post was deleted by hand
        applog("telegram", "live post: \(error.localizedDescription)", error: true)
    }

    private func push(_ text: String, jpeg: Data? = nil) async throws {
        guard let st = state else { return }
        try await edit(text, id: st.messageId, photo: st.hasPhoto, jpeg: jpeg)
        if jpeg != nil, state?.messageId == st.messageId { state?.hasPhoto = true }
    }

    private func edit(_ text: String, id: Int, photo: Bool, jpeg: Data? = nil) async throws {
        let body = LivePostText.fit(text, photo: photo || jpeg != nil)
        if let jpeg { try await Telegram.editPhoto(id, jpeg: jpeg, caption: body) }
        else if photo { try await Telegram.editCaption(id, caption: body) }
        else { try await Telegram.editText(id, text: body) }
    }

    // MARK: text inputs

    private func goalLine() -> LivePostText.GoalLine? {
        let goal = GoalStore.shared, config = goal.config
        guard config.target > 0 else { return nil }
        return .init(pct: Int(goal.progress * 100), target: Money(config.target, config.currency).display, title: config.title)
    }

    private func liveInput(_ stream: Streamer) -> LivePostText.Live {
        let elapsed = stream.liveSince.map { Date().timeIntervalSince($0) } ?? 0
        var input = LivePostText.Live(title: title, slug: slug, viewers: viewers, elapsed: elapsed)
        if stream.roleActive == "starting", stream.countdownEnd != nil { input.countdown = stream.countdownText }
        input.reconnecting = stream.connectedSince == nil
        input.goal = goalLine()
        input.last = SessionLog.shared.lastDonation.map { "\($0.user) · \($0.display)" }
        let city = WidgetLocation.shared.cityText
        if flag("telegramShowCity", false), city != "--" { input.city = city }
        return input
    }

    private func recapInput(_ rec: SessionRecord) -> LivePostText.Recap {
        LivePostText.Recap(
            title: rec.title.isEmpty ? title : rec.title, slug: slug, duration: rec.duration, peak: rec.peakViewers, avg: rec.avgViewers,
            donationCount: rec.donationCount, total: Money(rec.donationTotal, rec.currency).display,
            showTotal: flag("telegramShowTotal", true),
            topName: rec.topDonor, topAmount: rec.topDonorDisplay, goal: goalLine(), moments: rec.moments,
            chatters: rec.trackingStarted ? rec.chatterCounts.count : rec.newChatters, trackingStarted: rec.trackingStarted)
    }

    #if DEBUG
    static func demo() {
        let encoded = try? JSONEncoder().encode(State(messageId: 7, phase: .live, announcedAt: nil, hasPhoto: true))
        let back = encoded.flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        assert(back?.messageId == 7 && back?.phase == .live && back?.hasPhoto == true)
        applog("reach", "LivePost.demo() passed")
    }
    #endif
}
