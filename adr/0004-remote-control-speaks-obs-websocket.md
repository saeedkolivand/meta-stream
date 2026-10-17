# Remote control speaks obs-websocket

The app is remote-controlled by pretending to be OBS: it serves a subset of the obs-websocket v5
protocol (scene list and switching, stream and recording start/stop, mute, sounds) on the local
network, behind a password. Stream Deck, Stream Deck Mobile, Touch Portal and Streamer.bot then
drive the phone with their existing OBS integrations, so the app writes no remote UI of its own.

## Considered Options

- **A web remote page served by the app** -- rejected: a second UI to build and keep in step.
- **Our own Stream Deck plugin** -- rejected: one controller only, while obs-websocket is shared
  by the whole desktop ecosystem.

## Consequences

Local network only (the iPhone hotspot, home Wi-Fi). Nobody can reach a phone on cellular
without a server, and the app has none, so a moderator at home cannot switch scenes. Requests
outside the subset answer "not supported" rather than being faked.
