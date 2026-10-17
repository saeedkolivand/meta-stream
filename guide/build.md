[← README](../README.md)

# Build your own copy


You need an iPhone or iPad on iOS 26.0+, a GitHub account, and access to a **paid Apple Developer team** (yours, or a
friend who exports a development certificate for you). Meta glasses and the Meta AI app are optional. No Mac is
required at any point: GitHub's macOS runners do the compiling.

## 1. Fork and rename

Fork this repo. Pick a bundle ID (**no hyphens**, Meta rejects them) and replace `com.saeedkolivand.metastream` in
`project.yml`, `MetaStream/Info.plist` and `MetaStream/Platforms/Platforms.swift`. Replace `metastream.iamsaeed.dev` in
`Platforms.swift` with your redirect page host (step 5).

## 2. Meta Wearables Developer Center (only for glasses)

Skip this step if you will not use Meta glasses: with no `META_APP_ID` the build hides every glasses control.


1. Sign up at <https://wearables.developer.meta.com> and create a project. Bundle ID = yours, Apple Team ID = the paid
   team's ID, Universal link = `metastream://`. Enable the **Camera** permission with a rationale.
2. Copy **MetaAppID** and **ClientToken** (shown under *Application ID*).
3. In the Meta AI app: *Settings → App Info → tap the version 5× → Developer Mode on*. Glasses firmware ≥ v126, Meta AI ≥ V282.

## 3. Apple signing (the paid-team part)

In <https://developer.apple.com/account> → Certificates, Identifiers & Profiles:

1. **Devices** → register your iPhone's UDID (`pip install pymobiledevice3` → `pymobiledevice3 usbmux list`).
2. **Identifiers** → App ID with your bundle ID; enable **Access Wi-Fi Information** and **Hotspot** (the glasses need both).
3. **Profiles** → *iOS App Development* profile for that App ID, your device, an Apple Development certificate → download.
4. Export that certificate **with its private key** from Keychain Access as a `.p12`.

## 4. Platform apps (optional, one per platform you want in Stream Manager)

| Platform | Where | Settings |
|---|---|---|
| Kick | kick.com → Settings → Developer (2FA required) | Redirect `https://<your-redirect-host>/oauth.html`, all scopes |
| Twitch | <https://dev.twitch.tv/console> | Redirect `http://localhost`, client type **Public** (device-code login, no secret) |
| Restream | <https://developers.restream.io/apps> | Redirect `https://<your-redirect-host>/oauth.html`, all permissions |
| YouTube | <https://console.cloud.google.com> | Enable *YouTube Data API v3*; OAuth consent screen (Testing, add yourself as test user); OAuth client of type **iOS** with your bundle ID |

## 5. Redirect page

Kick and Restream require an `https` redirect. `docs/oauth.html` is a static page that sends the browser back
into the app. Serve it with GitHub Pages (*Settings → Pages → Deploy from branch → `main` `/docs`*), optionally
behind a custom domain (add a `CNAME` record → `<you>.github.io`, **DNS only**).

## 6. Secrets

*Settings → Secrets and variables → Actions* in your fork:

| Secret | Value |
|---|---|
| `META_APP_ID`, `CLIENT_TOKEN` | from step 2; leave out for a build without glasses |
| `TEAM_ID` | the paid team's 10-character Team ID |
| `P12_BASE64`, `P12_PASSWORD` | `base64 -w0 cert.p12`, and its export password |
| `PROVISIONING_PROFILE_BASE64` | `base64 -w0 profile.mobileprovision` |
| `IPA_PASSWORD` | any long random string; encrypts the build artifact (public repo) |
| `KICK_CLIENT_ID`, `KICK_CLIENT_SECRET`, `TWITCH_CLIENT_ID`, `RESTREAM_CLIENT_ID`, `RESTREAM_CLIENT_SECRET`, `YOUTUBE_CLIENT_ID` | from step 4, only the ones you created |

## 7. Build and install (from Windows, Linux or macOS)

Push to `main` or run the *build-ipa* workflow. Once (Windows: run these in Git Bash, which ships `openssl`; the
*Apple Devices* app or iTunes provides the USB driver):

```bash
pip install pymobiledevice3
gh auth login
```

Then, every time, from the repo root with every phone/iPad unlocked and on USB:

```bash
gh run list -w build-ipa -L 1                    # wait until the newest run says "completed success"
rm -f build/MetaStream.ipa.enc build/MetaStream.ipa
gh run download -n MetaStream-ipa -D build       # newest artifact
openssl enc -d -aes-256-cbc -pbkdf2 -in build/MetaStream.ipa.enc -out build/MetaStream.ipa -pass file:signing/ipa-password.txt
for udid in $(pymobiledevice3 usbmux list --usb --simple | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}'); do
  pymobiledevice3 apps install --udid "$udid" build/MetaStream.ipa && echo "OK $udid" || echo "FAILED $udid"
done
```

`signing/ipa-password.txt` holds the `IPA_PASSWORD` secret (or use `-pass pass:'<IPA_PASSWORD>'`). Each device must
print `OK`; `pymobiledevice3` reports errors on stderr, so don't pipe it into `tail`. If a device fails: unlock it,
tap *Trust* on it, replug, and rerun only the loop. `bad decrypt` means the wrong password file.

First launch: *Settings → General → VPN & Device Management → trust the developer*. The development profile is valid
for a year; rebuilds install over the previous version and keep your settings. A device must be in the profile
(step 3) or the install fails with a provisioning error.

## Why a paid Apple team

Since DAT SDK 0.8 the glasses send video over a direct Wi-Fi link. Joining it needs two entitlements,
`com.apple.developer.networking.HotspotConfiguration` and `com.apple.developer.networking.wifi-info`, which Apple only
grants to paid teams. A build signed with a free Apple ID (Sideloadly, AltStore) registers the glasses and connects
over Bluetooth but never receives a frame. This is Apple's rule, and the app can't work around it.

## Security notes

- The `signing/` folder (certificate, profile, client-ID files, IPA password) is gitignored. Never commit it.
- Build artifacts are encrypted because anyone with a GitHub account can download public-repo artifacts and the IPA
  embeds OAuth client secrets. Development-signed IPAs only install on the UDIDs in the profile anyway.
- Platform tokens and stream keys are stored in `UserDefaults` on the phone (single-user app). Move them to the
  Keychain if you share the device.

