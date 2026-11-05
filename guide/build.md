[← README](../README.md)

# Build your own copy

MetaStream isn't in the App Store or on Google Play. You fork the repo, add your keys as GitHub secrets, and GitHub
Actions builds the app: `build-ipa` for iOS (on macOS runners, so no Mac needed) and `build-apk` for Android. You
install the result over USB from Windows, Linux or macOS.

| | iOS / iPadOS | Android |
|---|---|---|
| Device | iPhone or iPad on iOS 26.0+ | Phone on Android 16 (API 36)+ |
| Account | A **paid Apple Developer team** (yours, or a friend who exports a development certificate for you) | None |
| Workflow | `build-ipa` (`.github/workflows/build.yml`) | `build-apk` (`.github/workflows/build-apk.yml`) |
| Installs with | `pymobiledevice3` over USB | `adb` over USB |

Meta glasses and the Meta AI app are optional on both.

## Both platforms

### 1. Fork and rename

Fork this repo. Pick an app ID (**no hyphens**, Meta rejects them) and replace `com.saeedkolivand.metastream`:

- **iOS:** everywhere outside `android/` (`git grep -l com.saeedkolivand.metastream -- ':!android'` lists the files:
  `project.yml`, the plists, the app group and Keychain names).
- **Android:** only `applicationId` in `android/app/build.gradle.kts`. Leave `namespace` and the Kotlin packages alone.

Replace `metastream.iamsaeed.dev` with your redirect page host (step 3) in the files
`git grep -l metastream.iamsaeed.dev -- '*.swift' '*.kt'` lists.

### 2. Platform apps (optional, one per platform you want in Stream Manager)

One app per platform serves both builds.

| Platform | Where | Settings |
|---|---|---|
| Kick | kick.com → Settings → Developer (2FA required) | Redirect `https://<your-redirect-host>/oauth.html`, all scopes |
| Twitch | <https://dev.twitch.tv/console> | Redirect `http://localhost`, client type **Public** (device-code login, no secret) |
| Restream | <https://developers.restream.io/apps> | Redirect `https://<your-redirect-host>/oauth.html`, all permissions |
| YouTube | <https://console.cloud.google.com> | Enable *YouTube Data API v3*; OAuth consent screen (Testing, add yourself as test user); OAuth client of type **iOS** with your bundle ID (both apps sign in through its reversed-client-ID scheme) |

### 3. Redirect page

Kick and Restream require an `https` redirect. `docs/oauth.html` is a static page that sends the browser back
into the app. Serve it with GitHub Pages (*Settings → Pages → Deploy from branch → `main` `/docs`*), optionally
behind a custom domain (add a `CNAME` record → `<you>.github.io`, **DNS only**).

### 4. Meta Wearables Developer Center (only for glasses)

Skip this step if you won't use Meta glasses. Without a Meta app ID, the iOS build hides every glasses control,
and on Android the glasses stay off until you turn them on in Settings.

1. Sign up at <https://wearables.developer.meta.com> and create a project. Add an iOS app (bundle ID = yours,
   Apple Team ID = the paid team's ID, universal link = `metastream://`) and/or an Android app (package = your
   `applicationId`). Enable the **Camera** permission with a rationale.
2. Copy **MetaAppID** and **ClientToken** (shown under *Application ID*).
3. In the Meta AI app: *Settings → App Info → tap the version 5× → Developer Mode on*. Glasses firmware ≥ v126, Meta AI ≥ V282.

### 5. Secrets

*Settings → Secrets and variables → Actions* in your fork. Both workflows read the same secrets:

| Secret | Value | Used by |
|---|---|---|
| `KICK_CLIENT_ID`, `KICK_CLIENT_SECRET`, `TWITCH_CLIENT_ID`, `RESTREAM_CLIENT_ID`, `RESTREAM_CLIENT_SECRET`, `YOUTUBE_CLIENT_ID` | from step 2, only the ones you created | both |
| `META_APP_ID` | from step 4; leave out for a build without glasses | both |
| `CLIENT_TOKEN` | from step 4 | iOS |
| `IPA_PASSWORD` | any long random string; encrypts both build artifacts (the repo is public) | both |
| `TEAM_ID` | the paid team's 10-character Team ID | iOS |
| `P12_BASE64`, `P12_PASSWORD` | `base64 -w0 cert.p12`, and its export password (iOS step 1) | iOS |
| `PROVISIONING_PROFILE_BASE64` | `base64 -w0 profile.mobileprovision` (iOS step 1) | iOS |

Put the `IPA_PASSWORD` value in `signing/ipa-password.txt` too (gitignored); the install commands below read it.
Install the tools once (on Windows, run these in Git Bash, which ships `openssl`):

```bash
gh auth login
pip install pymobiledevice3        # iOS
# Android: install platform-tools (adb) from developer.android.com/tools/releases/platform-tools
```

## iOS and iPadOS

### 1. Apple signing (the paid-team part)

In <https://developer.apple.com/account> → Certificates, Identifiers & Profiles:

1. **Devices** → register your iPhone's UDID (`pymobiledevice3 usbmux list`).
2. **Identifiers** → App ID with your bundle ID; enable **Access Wi-Fi Information** and **Hotspot** (the glasses need both).
3. **Profiles** → *iOS App Development* profile for that App ID, your device, an Apple Development certificate → download.
4. Export that certificate **with its private key** from Keychain Access as a `.p12`.

### 2. Build and install

Push to `main` or run the *build-ipa* workflow. Then, from the repo root with every iPhone/iPad unlocked and on USB:

```bash
gh run list -w build-ipa -L 1                    # wait until the newest run says "completed success"
rm -f build/MetaStream.ipa.enc build/MetaStream.ipa
gh run download -n MetaStream-ipa -D build       # newest artifact
openssl enc -d -aes-256-cbc -pbkdf2 -in build/MetaStream.ipa.enc -out build/MetaStream.ipa -pass file:signing/ipa-password.txt
for udid in $(pymobiledevice3 usbmux list --usb --simple | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}'); do
  pymobiledevice3 apps install --udid "$udid" build/MetaStream.ipa && echo "OK $udid" || echo "FAILED $udid"
done
```

Each device must print `OK`; `pymobiledevice3` reports errors on stderr, so don't pipe it into `tail`. If a device
fails: unlock it, tap *Trust* on it, replug, and rerun only the loop. `bad decrypt` means the wrong password file.

First launch: *Settings → General → VPN & Device Management → trust the developer*. The development profile is valid
for a year; rebuilds install over the previous version and keep your settings. A device must be in the profile
(step 1) or the install fails with a provisioning error. Windows needs the *Apple Devices* app (or iTunes) for the
USB driver.

### Why a paid Apple team

Since DAT SDK 0.8 the glasses send video over a direct Wi-Fi link. Joining it needs two entitlements,
`com.apple.developer.networking.HotspotConfiguration` and `com.apple.developer.networking.wifi-info`, which Apple only
grants to paid teams. A build signed with a free Apple ID (Sideloadly, AltStore) registers the glasses and connects
over Bluetooth but never receives a frame. This is Apple's rule, and the app can't work around it.

## Android

### 1. Build and install

Push to `main` (changes under `android/`) or run the *build-apk* workflow. On the phone, turn on *Developer options →
USB debugging*, then from the repo root:

```bash
gh run list -w build-apk -L 1                    # wait until the newest run says "completed success"
rm -f build/MetaStream-*.apk*
gh run download -n MetaStream-apk -D build
openssl enc -d -aes-256-cbc -pbkdf2 -in build/MetaStream-arm64-v8a.apk.enc -out build/MetaStream.apk -pass file:signing/ipa-password.txt
adb install -r build/MetaStream.apk
```

The artifact has one APK per CPU: `arm64-v8a` (almost every phone), `armeabi-v7a` (old 32-bit phones), `x86_64`
(emulator). Not sure which one a phone needs? `adb shell getprop ro.product.cpu.abi`.

The APK is a debug build signed with the runner's debug key. If an update fails with a signature mismatch, uninstall
the old copy first (`adb uninstall <your applicationId>`), which also clears its settings.

### 2. Build locally (optional)

JDK 17 and the Android 37 SDK platform. Put the client IDs in `android/local.properties` under the same names as the
secrets (`KICK_CLIENT_ID=...`), plus `mwdat_application_id` and `mwdat_client_token` for the glasses, then:

```bash
cd android
./gradlew assembleDebug                          # app/build/outputs/apk/debug/app-<abi>-debug.apk (arm64-v8a for phones, x86_64 for the emulator)
./gradlew installDebug                           # straight onto the connected phone
```

## Security notes

- The `signing/` folder (certificate, profile, client-ID files, artifact password) and `android/local.properties`
  are gitignored. Never commit them.
- Build artifacts are encrypted because anyone with a GitHub account can download public-repo artifacts, and both
  the IPA and the APK embed OAuth client secrets. Development-signed IPAs only install on the UDIDs in the profile;
  APKs install anywhere, so keep the decrypted file to yourself.
- Platform tokens stay on the device: the iOS Keychain and Android's encrypted storage. There is no server.
