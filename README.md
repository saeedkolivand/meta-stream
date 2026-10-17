<p align="center">
  <img src="MetaStream/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="MetaStream icon">
</p>

<h1 align="center">MetaStream</h1>

<p align="center">
  A pocket OBS for IRL streamers. Scenes and widgets, a full audio mix, recording, bonded uplinks, chat with
  moderator commands and bots, and remote control from a Stream Deck, all on an iPhone or iPad.<br>
  Streams to Kick, Twitch, YouTube, Restream or any RTMP / SRT / SRTLA server. Meta glasses are an optional camera.<br>
  Built and signed from <b>Windows</b>. No Mac needed.
</p>

<p align="center">
  <a href="https://github.com/saeedkolivand/meta-stream/actions/workflows/build.yml"><img src="https://github.com/saeedkolivand/meta-stream/actions/workflows/build.yml/badge.svg" alt="build"></a>
  <img src="https://img.shields.io/badge/iOS-26.0%2B-black" alt="iOS 26.0+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/protocols-RTMP%20%C2%B7%20SRT%20%C2%B7%20SRTLA-purple" alt="RTMP, SRT, SRTLA">
</p>

<p align="center">
  <img src="docs/screenshots/live.png" width="220" alt="Live screen">
  <img src="docs/screenshots/settings.png" width="220" alt="Settings">
  <img src="docs/screenshots/manager.png" width="220" alt="Stream Manager">
</p>

---

## Why this exists

Desktop streamers get OBS: scenes, audio mixing, recording, a Stream Deck, bots. IRL streamers get a phone app that
pushes one camera and little else, plus a laptop-and-backpack rig for everything that app can't do. MetaStream puts
the OBS side of that rig on the phone: build scenes, mix sound, record, bond your connections and run chat from the
device you are already holding. It started as the missing app for Ray-Ban Meta glasses, which it still supports.

## Highlights

- **Scenes and widgets** with chat, alerts, live text tokens, QR codes, images and web widgets; Starting, BRB and Ending scenes switch on their own
- **Audio mix** with a soundboard, level meter and dead-air alert
- **Recording** to Photos, with or without going live
- **RTMP, SRT and SRTLA bonding** across Wi-Fi, Ethernet and cellular, with adaptive bitrate
- **Chat** for Kick, Twitch, YouTube and Restream, with `/slash` moderator commands and an app bot
- **Stream Deck control** over the obs-websocket protocol
- **Cameras**: phone, USB-C, dual camera, Looks and LUTs, and optional Meta glasses

## Docs

| | |
|---|---|
| [Features](guide/features.md) | Everything the app does, how to use it, codec per destination, limits |
| [Build your own copy](guide/build.md) | Fork, sign with a paid Apple team, build on GitHub Actions and install from Windows |
| [Troubleshooting](guide/troubleshooting.md) | Common problems and fixes |
| [Design decisions](adr) | Why things are built the way they are |
| [Glossary](CONTEXT.md) | The words the code and docs use |

## Credits

[HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) ·
[Meta Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios) ·
[BELABOX srtla](https://github.com/BELABOX/srtla) · [XcodeGen](https://github.com/yonaskolb/XcodeGen) ·
[pymobiledevice3](https://github.com/doronz88/pymobiledevice3) · [Vazirmatn](https://github.com/rastikerdar/vazirmatn).
Built by [Saeed Kolivand](https://iamsaeed.dev) with Claude Code.
