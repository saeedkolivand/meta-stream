import Foundation

/// One minute of a stream session: what the Session report's timeline and the recap's peak/average read from.
struct SessionSample: Codable {
    var minute: Int
    var viewers: Int
    var chat: Int
    var kbps: Int
    var drops: Int
    var downSeconds: Int
    /// Audio clock skew at this minute; nil in older files and when the mix reported none yet.
    var skewMs: Int?
    /// Donations this minute in the session's goal currency, and Chatters first seen ever this minute. Nil in older files.
    var donations: Double?
    var newChatters: Int?
}

/// A point in a stream session worth coming back for: a chat spike, a big donation or a raid.
/// `detail`: the money display for a donation, the viewer count for a raid, messages per minute for a spike.
struct Moment: Codable {
    enum Kind: String, Codable { case chatSpike, donation, raid }
    var at: Date
    var kind: Kind
    var user: String
    var detail: String
    /// EUR for a donation, viewers for a raid, messages per minute for a chat spike. Nil in older files.
    var value: Double?
}

/// Everything kept about one stream session. Chat text is never stored, only counts per Chatter key.
struct SessionRecord: Codable {
    var start: Date
    var end: Date?
    var title: String
    var samples: [SessionSample] = []
    var moments: [Moment] = []
    var donationCount = 0
    var donationTotal: Decimal = 0
    var currency: String
    var topDonor: String?
    var topDonorDisplay: String?
    var topDonorAmount: Decimal = 0
    var chatterCounts: [String: Int] = [:]
    var chatterNames: [String: String] = [:]
    var newChatters = 0
    var returningChatters = 0
    /// The Chatter registry was empty when the session began: the recap says counting started today.
    var trackingStarted = false
    // Added after release 1, so Optional: older files decode them as nil.
    var distanceMeters: Double?
    var cities: [String]?
    /// Public donor name to total in `currency`; anonymous placeholders excluded.
    var donors: [String: Decimal]?
    /// Ingest platform name ("Kick") and the camera that was live; nil in older files.
    var platform: String?
    var camera: String?

    var peakViewers: Int { samples.map(\.viewers).max() ?? 0 }

    var avgViewers: Int {
        let live = samples.map(\.viewers).filter { $0 > 0 }
        return live.isEmpty ? 0 : live.reduce(0, +) / live.count
    }

    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

extension SessionRecord: Identifiable { var id: Date { start } }
