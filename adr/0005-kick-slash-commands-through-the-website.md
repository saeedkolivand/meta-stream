# Kick slash commands the public API lacks go through a signed-in kick.com page

Kick's public API covers ads, title, category, bans, timeouts and deleting a message, and those
slash commands use it. Everything else the kick.com chat offers (`/clear`, `/host`, `/poll`, `/prediction`,
`/clip`, `/slow`, `/emoteonly`, `/followers`, `/subscribers`) has no public endpoint, so the app
keeps a hidden kick.com web page that the streamer signs into once, and sends those commands from
it exactly as the website does. Cloudflare then sees a real browser.

## Considered Options

- **Public API only** -- rejected: the streamer wants native Kick chat, and the missing commands
  are the ones used mid-stream.
- **Calling the website's internal API directly with a copied session token** -- rejected:
  Cloudflare blocks requests that do not come from a browser.

## Consequences

The internal API is undocumented and can change any day: every command checks the website's
response and says plainly in chat when it failed, never silently. Automating the website is a grey
area under Kick's terms for the streamer's own account. Signed out of the page, `/clear` falls back
to deleting recent messages over the public API. `/marker` cannot exist on
Kick: the platform has no markers.
