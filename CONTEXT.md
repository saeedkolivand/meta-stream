# MetaStream

An iOS app that broadcasts video from Ray-Ban Meta glasses to live streaming services, with
chat, a stream manager and a phone-camera fallback. Everything runs on the phone; there is no
server.

## Language

### Streaming

**Ingest**:
The single URL and key the phone publishes to. Exactly one per stream session.
_Avoid_: RTMP URL, server, destination

**Destination**:
A place a viewer actually watches. Streaming direct means one ingest and one destination;
streaming through a relay means one ingest and many destinations.
_Avoid_: channel, output, platform

**Relay**:
An ingest that fans a single stream out to several destinations. A relay is a platform but
never a destination — nobody watches a relay.
_Avoid_: multistreamer, restreamer

**Platform**:
A service the Stream Manager talks to over an API. Orthogonal to whether that service is a
destination or a relay.
_Avoid_: service, site, provider

**Stream session**:
One broadcast, from going live to ending. Survives reconnects.
_Avoid_: stream, run, broadcast

**Connection**:
One publish to the ingest, carrying a session. Drops and re-establishes within a session, so a
session is not a connection. With bonding, one connection runs over several links at once.
_Avoid_: stream, link, socket

**Bonding**:
Splitting one connection's packets across several internet links (Wi-Fi, cellular, wired) and
merging them again at a receiver, so the session survives one link dipping. The receiver is the
ingest; bonding is on exactly when the ingest is a bonding receiver.
_Avoid_: multipath, aggregation, link combining

**Downtime**:
Time within a session during which no connection was publishing.
_Avoid_: outage, dropout, lag

**Passthrough**:
Sending the glasses' own encoded video onward untouched, without decoding it.
_Avoid_: direct, copy, native

**Transcode**:
Decoding video and re-encoding it, which is what any modification to the picture requires.
_Avoid_: convert, process

### Overlays

**Scene**:
A named set of layers shown over the stream, optionally with a camera to switch to when it is
selected. Built in the app or imported from OBS.
_Avoid_: overlay pack, collection, profile

**Scene role**:
A job a scene is given so the app can switch to it on its own: Starting (shown with a countdown
after going live), BRB (while the link is too weak) and Ending (held briefly after stopping).
A scene has at most one role; a manual switch always wins.
_Avoid_: auto scene, special scene, preset

**Layer**:
One item in a scene: a widget, image, text, color, clip or web page. Placed relative to the frame
(in-app) or by OBS transform (imported).
_Avoid_: source, item, element

**Stinger**:
A short video played over a scene change, which happens underneath it at the cut point. One
stinger serves every scene change; it hides the hitch of a camera switch.
_Avoid_: transition video, wipe, animation

**Widget**:
A native in-app layer (chat, alerts, event list, text, QR code) drawn as one bitmap that is
redrawn only when its content changes. Never a hidden web view.
_Avoid_: plugin, browser source, embed

### Chat

**Chat origin**:
The destination a viewer typed a message on. Chat is aggregated across destinations, so every
message carries one.
_Avoid_: chat source, chat site, chat platform

**Bot**:
A chat account that posts automated messages on the streamer's behalf (BotRix, StreamElements,
Nightbot, ...). Known only by its name; no platform marks bots, and the app has no access to a
bot beyond what it says and hears in chat.
_Avoid_: chatbot, integration, service

**App bot**:
The app's own chat account on Kick and Twitch, which posts automatic messages and answers
viewers. Unlike a bot, the app controls it. Automatic messages never post as the streamer.
_Avoid_: our bot, MetaStream bot, auto-chat

**Timer**:
A message the app bot repeats in chat on a schedule while live, e.g. a social link.
_Avoid_: scheduled message, auto message, reminder

**Bot announcement**:
A bot message containing one of the streamer's trigger words (e.g. "won", "winner"), so it is
worth the streamer's attention while live. Every other bot message is noise.
_Avoid_: bot alert, bot event, notification

**Command**:
A chat message starting with `!` that a bot or the app bot acts on, e.g. `!giveaway start`,
`!location`.
_Avoid_: action, trigger, macro

**Slash command**:
A chat-input instruction starting with `/` (e.g. `/clear`, `/ban name`, `/slow 30`) that the app
carries out through the platform's own moderation tools, as the platform's website does. Never
sent as a message, and never seen by a bot. Unlike a command, which a bot carries out.
_Avoid_: mod command, chat command, action

**Chat channel**:
A channel identified by slug or name, for chat purposes only. The only surviving sense of the
word "channel".
_Avoid_: room, chatroom

### Capture

**Video source**:
Where the picture comes from: the glasses, the back camera, the front camera, an external
(USB) camera, or the screen. The word "source" is reserved for this and is never used for chat
or audio.
_Avoid_: input, feed, camera

**Face cam**:
A second video source shown as a small window over the main one. Either can be the big picture;
the window is hidden while privacy blur is on.
_Avoid_: dual camera, PiP, overlay camera

**Look**:
A video source's color treatment: brightness, contrast, saturation, warmth and an optional LUT.
A neutral look leaves the picture untouched; any other look needs a transcode.
_Avoid_: filter, grade, preset, color correction

**Recording**:
A local file the streamer chose to make, started and stopped independently of streaming: one
session may hold several recordings, and a recording may exist with no session at all. While
live it contains exactly what went out, not a pristine original.
_Avoid_: session recording, VOD, master, capture

**Mix**:
Everything viewers hear: the mic plus alert sounds, clip audio and sounds. Heard only on
stream, never through the phone's speaker.
_Avoid_: audio, output, master

**Sound**:
A short audio file the streamer plays into the mix on a tap, from the soundboard.
_Avoid_: sound effect, SFX, sample

### Money

**Donation**:
Money a viewer gives the streamer, from any source: a donation site, a platform tip, KICKs, Bits,
a Super Chat, a subscription or a gifted subscription. It has an amount and the currency it was
given in, counted at what the viewer paid, before any platform or site takes its cut. A
subscription's amount is its set price, since platforms don't say what one paid. Only a paid
donation counts; one refunded later is taken back out of the goal at the value it added.
_Avoid_: tip (as the general word), dono, support, payment

**Goal**:
A target sum of donations the stream works toward, counted in one goal currency and shown as
progress. A donation in another currency is converted into it once, at the rate when it
arrives, and keeps that value; later rate changes never move the goal. One goal runs at a time and
lasts across streams until the streamer resets it, counting on past its target.
_Avoid_: donation goal bar, target, milestone

**Donation source**:
Where the app learns of a donation: a platform's own event, a donation site's API, the streamer
entering it by hand (cash, a bank transfer), or (only where nothing more direct exists) a bot's
chat announcement. Every donation has exactly one, so nothing is counted twice.
_Avoid_: integration, provider, feed

**Missed donation**:
A donation made while the app wasn't listening (closed, or reconnecting), found afterwards on the
donation site. It counts toward the goal but is never announced: no alert, read-aloud or thank-you.
_Avoid_: backfilled, offline donation, catch-up

**Pending donation**:
A donation the app knows about but can't convert yet because no recent enough rate is known. It
is listed but doesn't move the goal until a rate arrives.
_Avoid_: unconverted, queued, waiting tip

**Market rate**:
The free-market toman rate (what toman actually trades at), never the far lower official rial
rate. A streamer-set rate replaces it when given.
_Avoid_: official rate, bank rate, exchange price

**Goal currency**:
The one currency a goal is counted in (toman, US dollar or euro). Other currencies may be shown
beside it as conversions, never counted separately.
_Avoid_: base currency, unit

**Privacy blur**:
Obscuring faces, text, licence plates or chosen objects in the outgoing picture. Best-effort
per frame, never a guarantee.
_Avoid_: censor, redact, filter, anonymise
