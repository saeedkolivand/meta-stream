[← README](../README.md)

# Features

Everything here works on iOS/iPadOS and Android unless a row says otherwise. The two apps are separate native builds
with the same settings, names and layout; [iOS and Android](#ios-and-android) lists where they differ.

## Using it

1. **Settings → Ingest & protocol** → pick a destination, or open **Manage**, connect a platform and tap *Use for
   streaming* to fill the URL, key and chat for you.
2. **Settings → Scenes & widgets** → *Add Starting, BRB & Ending scenes*, then add your own scenes and widgets.
3. **GO LIVE.** The source button picks the camera, the record button records, the chat button slides chat over the preview.
   With Kick or Twitch connected, GO LIVE first shows a *Stream info* sheet (title, category, tags) so you can check
   them before you start; switch it off with *Ask before going live* at the bottom of that sheet.
4. **Glasses:** *Settings → Meta glasses → Use Meta glasses*, then register with Meta AI from the card that appears.
5. **Stream Deck:** *Settings → Remote control* → set a password, then add the app in your OBS plugin as an OBS
   instance at the address shown.

## What it does

### Cameras

| | |
|---|---|
| **Phone cameras** | Back or front, 720p or 1080p, portrait 9:16 or landscape 16:9, 24/30/60 fps, with lens, zoom, focus, exposure, HDR and stabilisation controls |
| **External camera** | A USB-C (UVC) camera such as a DJI Osmo Action shows up as a source on iPad and Android |
| **Dual camera** | One camera full frame and a second as a small window; tap to swap |
| **Looks** | Brightness, contrast, saturation, warmth and `.cube` LUTs per camera |
| **Meta glasses (optional)** | Ray-Ban / Oakley Meta video through Meta's Device Access Toolkit, with automatic phone fallback when they drop. Off by default: turn on *Settings → Meta glasses* to show the glasses controls |

### Scenes and widgets

| | |
|---|---|
| **Scenes** | Build as many as you like, each with its own layers and optionally its own camera. Switch with a tap, rotate on a timer, or edit the live scene as a draft and apply it when ready |
| **Widgets** | Chat, alerts, event list, text with live tokens (`{time}`, `{uptime}`, `{viewers}`, `{bitrate}`, `{speed}`, `{city}`, `{weather}`, `{follower}`, `{sub}`, `{countdown}`, …), QR code, image / GIF, slideshow, video, and any web widget (StreamElements, Streamlabs) |
| **Scene roles** | Starting (with a countdown after you go live), BRB (switched to on its own while the connection is weak) and Ending. Ready-made Mono and Ticker sets add all three at once |
| **Stingers** | A transition clip that covers the switch between scenes |
| **OBS import** | Bring a scene collection over from OBS on your PC; PC-only sources are skipped and listed |
| **Privacy blur** | Blurs the picture on demand |
| **External display** | A clean program feed on a USB-C monitor (iOS) |

### Audio

| | |
|---|---|
| **Donation alerts** | Pick a design for tips, Bits and KICKs in the Alerts widget (Coin burst, Neon sign, Receipt, Holo card, Shockwave, Goal surge): drawn live over the whole frame, with your colour and speed. Follows, subs and raids keep the Island banner |
| **Mix** | Mic, alert sounds, soundboard and clip audio as separate tracks with their own volume, through a limiter |
| **Meter and dead-air alert** | A level bar on screen, and a warning when the mic goes silent while live |
| **Soundboard** | Your own sound files, one tap each |
| **Read aloud** | Chat and alerts spoken in your ear, with priority lanes so stream warnings interrupt and chat never piles up |

### Going live and staying live

| | |
|---|---|
| **Destinations** | Presets for Kick, Twitch, YouTube and Restream, plus Instagram, TikTok and any RTMP, RTMPS or SRT server |
| **SRTLA bonding** | Use an `srtla://` ingest and the stream is split across Wi-Fi, Ethernet and cellular at once, so one link dropping doesn't drop the stream |
| **Adaptive bitrate** | Backs off when the uplink struggles and climbs back quickly once it clears |
| **Reconnects** | Retries with backoff, speaks "stream dropped" and "stream back", and keeps the timer honest |
| **Health warnings** | Battery, thermal, dead air and connection state, spoken once each |
| **Background** | Keeps streaming while you check a message or open Maps; on iOS, Picture in Picture keeps a re-encoded stream alive |
| **Recording** | Record to Photos (iOS) or the gallery (Android), with or without going live; saved in fragments on iOS so a crash keeps what was recorded |
| **Lock Screen** | iOS: a Live Activity on the Lock Screen and Dynamic Island. Android: an ongoing notification with the timer, mute and a bot command |
| **Android Auto** | Android: chat, stream state and the camera source on the car screen |

### Chat, moderation and bots

| | |
|---|---|
| **Chat** | Kick, Twitch, YouTube and Restream in one sheet over the preview, with 7TV / BTTV / FFZ emotes and badges |
| **Slash commands** | Type `/ban`, `/timeout`, `/clear`, `/slow`, `/followers`, `/emoteonly`, `/title`, `/category`, `/raid`, `/poll`, `/ad`, `/announce`, `/marker`, `/clip` and more, like in the platform's own chat |
| **Bot commands** | Saved commands for your chat bots as one-tap chips, also from the Lock Screen (Android: the notification) |
| **AI moderation** | An on-device model (Apple Intelligence on iOS, Gemini Nano on Android) holds back abusive chat before it reaches the stream; the in-app chat keeps it. Without a model, a word list does the job |
| **App bot** | The app's own bot posts scene notices, answers viewer commands such as `!location`, runs timers and thanks new followers and subs (Kick and Twitch) |
| **Stream Manager** | Edit title and category, watch viewers, pull your stream key and switch Restream destinations |

### Remote control and extras

| | |
|---|---|
| **obs-websocket** | The app speaks the obs-websocket v5 protocol on your local network, so Stream Deck, Touch Portal and Streamer.bot control it as if it were OBS: switch scenes, go live, record, mute. Password protected, local network only |
| **GPS from iPhone** | A Wi-Fi-only iPad borrows the iPhone's location over Personal Hotspot for speed, distance, city and weather widgets |
| **Logs** | Every API call and stream event lands in *Settings → Diagnostics* with a share button. Keys and tokens are masked |

## Codec per destination

Tested against each ingest, not taken from marketing pages:

| Destination | Takes HEVC | What the app sends |
|---|---|---|
| Your own RTMP server | yes, if your server decodes it | HEVC |
| YouTube | yes, over enhanced RTMP | HEVC |
| Kick | no | H.264 |
| Restream over RTMP | no, only over SRT | H.264 |
| Any `srt://` or `srtla://` ingest | yes | HEVC |
| Twitch | Affiliates and Partners only | H.264 |
| Instagram, TikTok | no | H.264 |

Auto follows this table, and Settings lets you override it per stream.

## Limits you should know

- **On iOS, screen share has no sound and starts from iOS's own sheet.** Pick *Screen* as the video source, tap the broadcast button, then *Start Broadcast*. It goes through a broadcast extension ([`adr/0003`](../adr/0003-screen-arrives-encoded-like-the-glasses.md)), up to 1080p. The face cam over it is iPad-only; on an iPhone the screen replaces the camera. Builds without the extension's profile hide the option. On Android it starts from the system's screen-capture prompt and can carry app audio.
- **Some Kick commands go through kick.com.** Kick's public API has no endpoint for `/clear`, `/slow`, `/poll` and a
  few others, so the app runs them through a signed-in kick.com page (*Settings → Chat commands*, [`adr/0005`](../adr/0005-kick-slash-commands-through-the-website.md)).
- **Glasses**: 720×1280 portrait at 30 fps is the most Meta's SDK gives any third-party app, the glasses pick their
  own bitrate, their video can't carry overlays or be recorded unless it is re-encoded, and their battery level isn't
  readable. The glasses keep one third-party app registered at a time.
- **Background streaming on iOS without Picture in Picture** works only when the video isn't re-encoded. Android streams from a foreground service.
- **A paid Apple Developer team** is required on iOS, for the glasses. See [Why a paid Apple team](build.md#why-a-paid-apple-team).
  Android needs no account.

## iOS and Android

Same features, settings pages and names on both ([`adr/0002`](../adr/0002-android-native-kotlin-port.md),
[`adr/0007`](../adr/0007-feature-modules-mirrored-across-platforms.md)). The differences come from the platforms:

| | iOS / iPadOS | Android |
|---|---|---|
| Requires | iOS 26.0+, paid Apple Developer team | Android 13 (API 33)+, no account |
| Lock Screen | Live Activity, Dynamic Island, three bot-command buttons | Ongoing notification with one command button |
| Screen share | Broadcast extension, up to 1080p, no sound | MediaProjection, with app audio |
| External display | Clean feed on a USB-C monitor | Not yet |
| In the car | | Android Auto: chat, stream state, camera source |
| Keyboard | Menu with ⌘1–9 scenes, ⌘M mute, ⌘R record (iPad) | |
| Encoder | [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) | [RootEncoder](https://github.com/pedroSG94/RootEncoder) |

## How it works

```mermaid
flowchart LR
  subgraph Sources
    P[Phone cameras]
    U[USB camera]
    G[Meta glasses<br/>optional]
    M[Mic + sounds]
  end
  P & U & G --> X[Mixer<br/>scenes · widgets · looks]
  M --> AM[Audio mix<br/>tracks · limiter]
  X & AM --> E[Encoder<br/>HEVC / H.264 + AAC]
  E --> O[RTMP / SRT]
  E --> B[SRTLA bonding<br/>Wi-Fi · Ethernet · cellular]
  E --> R[Recording → Photos]
  X --> D[External display]
  SD[Stream Deck · Touch Portal<br/>Streamer.bot] -- obs-websocket --> X
  API[Kick · Twitch · YouTube · Restream] <-- chat · title · bots --> X
```

Two native apps with the same modules: SwiftUI on [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) for iOS,
Jetpack Compose on [RootEncoder](https://github.com/pedroSG94/RootEncoder) for Android, with overlays drawn on the GPU
on both. There is no server: platform tokens stay on the device. The module layout is in
[`adr/0007`](../adr/0007-feature-modules-mirrored-across-platforms.md), the other design decisions in [`adr/`](../adr),
the vocabulary in [`CONTEXT.md`](../CONTEXT.md), and how to work on it in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Roadmap

Done: scenes and widgets, OBS import, audio mix and soundboard, recording, scene roles and stingers, obs-websocket
remote control, slash commands, App bot, Looks, SRTLA bonding, adaptive bitrate, read aloud, privacy blur, the
Android app, and the shared feature-module layout on both platforms.

Next: device testing of the Android app, animated stingers for the scene templates, an external display on Android.

