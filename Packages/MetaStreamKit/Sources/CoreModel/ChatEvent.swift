import Foundation

/// One chat or alert event, platform-agnostic. `origin` names the destination a viewer typed on
/// ("kick"/"twitch"/"youtube") and is only spoken when `Speaker.showOrigin` is set.
/// Two numeric fields cover everything: `amountCents` is money (tips), `count` is countable
/// things (raid viewers, cheered bits). ponytail: cents as Int, never Double — currency in
/// floating point is a rounding bug waiting to happen.
/// `subscribe` with count > 0 is a GIFT of `count` subs by `user`; count 0 is a normal (re)sub. Twitch Bits and Kick
/// KICKs are both `cheer` with `count` = how many; what any of it is worth: DonationPrices.money.
public struct ChatEvent: Sendable {
    public enum Kind: Equatable, Sendable { case message, tip, cheer, follow, subscribe, raid }
    public let kind: Kind
    public let user: String
    public var text: String
    public var amountCents: Int
    /// A tip's amount in the currency it was given in (donation sites, Super Chats); nil = `amountCents` US cents.
    public var money: Money?
    public var count: Int
    public var origin: String
    /// Twitch sub tier 1...3 (Prime counts as 1); other platforms have one tier.
    public var tier: Int
    /// Normalized role badges (see ChatBadges) and the sender's "#RRGGBB" name color; messages only.
    public var badges: [String]
    public var color: String?
    /// Platform message id and sender user id (Kick/Twitch chat messages only): what moderation slash commands act on.
    public var id: String
    public var userId: String
    public var at: Date
    /// Set by ChatModerator when the on-device model judged the message unsafe: kept in the in-app chat, nowhere else.
    public var flagged: Bool

    public init(
        kind: Kind, user: String, text: String = "", amountCents: Int = 0, money: Money? = nil, count: Int = 0,
        origin: String = "", tier: Int = 1, badges: [String] = [], color: String? = nil, id: String = "",
        userId: String = "", at: Date = Date(), flagged: Bool = false
    ) {
        self.kind = kind
        self.user = user
        self.text = text
        self.amountCents = amountCents
        self.money = money
        self.count = count
        self.origin = origin
        self.tier = tier
        self.badges = badges
        self.color = color
        self.id = id
        self.userId = userId
        self.at = at
        self.flagged = flagged
    }
}
