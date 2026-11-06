[← README](../README.md)

# Troubleshooting

Rows marked iOS or Android apply to that app only; the rest apply to both.

| Symptom | Cause and fix |
|---|---|
| iOS: glasses pill stuck on *connecting*, 0 frames | The build was signed with a free Apple ID and has no Wi-Fi entitlements. See [Why a paid Apple team](build.md#why-a-paid-apple-team). |
| iOS: *Device unavailable* right after starting the glasses | An SDK bug ([#292](https://github.com/facebook/meta-wearables-dat-ios/issues/292)). The app retries three times on its own and usually connects on the second. If all three fail, toggle Bluetooth or reopen the Meta AI app. |
| iOS: *Internal error* during Meta registration | Reported on iPhone 17e with iOS 26.5.1 ([#205](https://github.com/facebook/meta-wearables-dat-ios/issues/205)). |
| Ingest accepts the connection, then closes it a second later | The destination refused the codec. Set the codec to H.264 in Settings, or leave it on Auto. |
| The channel stays offline although the app says live | Same cause. A server that finds no video while it probes the first seconds treats the session as audio only. |
| Your own relay or OBS shows nothing | Check the stream key is not empty, and that the server decodes HEVC. FFmpeg 6.1 and newer does. |
| iOS: the stream freezes when you leave the app | Only transcoded streams do this. Keep the Picture in Picture window open, or send HEVC to YouTube or your own relay. |
| Kick login opens the Kick app instead of the login page | A universal-link quirk. Long-press the link and open it in the browser, or try again. |
| Android: `adb install` fails with `INSTALL_FAILED_OLDER_SDK` | The phone runs an Android older than 14 (API 34), the minimum. |
| Android: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | The installed copy was signed with another debug key (a different runner or PC). `adb uninstall` it first; this clears its settings. |
| Android: `adb devices` lists nothing or *unauthorized* | Turn on USB debugging, accept the prompt on the phone, and use a data cable. |
