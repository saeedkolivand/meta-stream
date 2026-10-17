# The screen reaches the app encoded, exactly like the glasses

iOS only lets a separate broadcast extension capture the screen, capped at roughly 50 MB, so its
frames have to cross a process boundary to reach the mixer. The extension hardware-encodes them
and writes the encoded stream into a ring of files in a shared App Group folder, waking the app
with a Darwin notification per frame; the app decodes it the same way
it decodes the glasses' HEVC and feeds the result to the mixer. The screen is then just another
encoded video source, and the camera window, overlays and widgets apply to it unchanged.

## Considered Options

- **Raw frames through shared memory** -- rejected: a 1080p frame is ~8 MB, so a few queued
  frames would get the extension killed mid-stream, and it is more code than reusing the decoder.
- **A TCP connection on 127.0.0.1** -- needs no App Group, but rejected in favour of the file
  ring: nothing listens on a port, and a frame survives the app being briefly busy.
- **The extension streams to the ingest on its own** -- rejected: the stream would lose the
  camera window, overlays and widgets, which are why the screen goes through the app at all.

## Consequences

Signing: the extension needs its own App ID and profile, and both App IDs need the same App
Group, so the main app's profile is regenerated too. Screen share is built only when the
extension's profile is present, as with the Live Activity widget.

Screen audio (a game's sound) is not carried at first; mixing it with the mic raises echo and
level problems worth solving on their own. Camera plus a screen window is iPad-only: an iPhone
stops the camera while another app is in front, so there the screen can only replace the camera.
