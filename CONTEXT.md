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
One socket carrying a session to its ingest. Drops and re-establishes within a session, so a
session is not a connection.
_Avoid_: stream, link, socket

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

**Layer**:
One item in a scene: a widget, image, text, color, clip or web page. Placed relative to the frame
(in-app) or by OBS transform (imported).
_Avoid_: source, item, element

**Widget**:
A native in-app layer (chat, alerts, event list, text, QR code) drawn as one bitmap that is
redrawn only when its content changes. Never a hidden web view.
_Avoid_: plugin, browser source, embed

### Chat

**Chat origin**:
The destination a viewer typed a message on. Chat is aggregated across destinations, so every
message carries one.
_Avoid_: chat source, chat site, chat platform

**Chat channel**:
A channel identified by slug or name, for chat purposes only. The only surviving sense of the
word "channel".
_Avoid_: room, chatroom

### Capture

**Video source**:
Where the picture comes from: the glasses, the back camera, or the front camera. The word
"source" is reserved for this and is never used for chat or audio.
_Avoid_: input, feed, camera

**Session recording**:
The local file for one session. A record of what was broadcast, not a pristine original — it
contains exactly what went out.
_Avoid_: VOD, master, capture

**Privacy blur**:
Obscuring faces, text, licence plates or chosen objects in the outgoing picture. Best-effort
per frame, never a guarantee.
_Avoid_: censor, redact, filter, anonymise
