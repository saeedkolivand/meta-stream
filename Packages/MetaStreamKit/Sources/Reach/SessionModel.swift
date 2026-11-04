import Foundation

/// One minute of a stream session: what the Session report's timeline and the recap's peak/average read from.
public struct SessionSample: Codable {
    public var minute: Int
    public var viewers: Int
    public var chat: Int
    public var kbps: Int
    public var drops: Int
    public var downSeconds: Int
    /// Audio clock skew at this minute; nil in older files and when the mix reported none yet.
    public var skewMs: Int?
    /// Donations this minute in the session's goal currency, and Chatters first seen ever this minute. Nil in older files.
    public var donations: Double?
    public var newChatters: Int?
}

/// A point in a stream session worth coming back for: a chat spike, a big donation or a raid.
/// `detail`: the money display for a donation, the viewer count for a raid, messages per minute for a spike.
public struct Moment: Codable {
    public enum Kind: String, Codable { case chatSpike, donation, raid }
    public var at: Date
    public var kind: Kind
    public var user: String
    public var detail: String
    /// EUR for a donation, viewers for a raid, messages per minute for a chat spike. Nil in older files.
    public var value: Double?
}

/// Everything kept about one stream session. Chat text is never stored, only counts per Chatter key.
public struct SessionRecord: Codable {
    public var start: Date
    public var end: Date?
    public var title: String
    public var samples: [SessionSample] = []
    public var moments: [Moment] = []
    public var donationCount = 0
    public var donationTotal: Decimal = 0
    public var currency: String
    public var topDonor: String?
    public var topDonorDisplay: String?
    public var topDonorAmount: Decimal = 0
    public var chatterCounts: [String: Int] = [:]
    public var chatterNames: [String: String] = [:]
    public var newChatters = 0
    public var returningChatters = 0
    /// The Chatter registry was empty when the session began: the recap says counting started today.
    public var trackingStarted = false
    // Added after release 1, so Optional: older files decode them as nil.
    public var distanceMeters: Double?
    public var cities: [String]?
    /// Public donor name to total in `currency`; anonymous placeholders excluded.
    public var donors: [String: Decimal]?
    /// Ingest platform name ("Kick") and the camera that was live; nil in older files.
    public var platform: String?
    public var camera: String?

    public var peakViewers: Int { samples.map(\.viewers).max() ?? 0 }

    public var avgViewers: Int {
        let live = samples.map(\.viewers).filter { $0 > 0 }
        return live.isEmpty ? 0 : live.reduce(0, +) / live.count
    }

    public var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

extension SessionRecord: Identifiable { var id: Date { start } }
