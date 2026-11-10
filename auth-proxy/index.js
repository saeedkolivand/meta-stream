// OAuth token proxy: adds the Kick/Restream client secrets server-side so they never ship in the apps.
// POST /kick/token or /restream/token with the usual form body, minus client_id/secret. Upstream reply is passed through.
const UPSTREAM = {
  kick: "https://id.kick.com/oauth/token",
  restream: "https://api.restream.io/oauth/token",
};

export default {
  async fetch(req, env) {
    const [, name, tail] = new URL(req.url).pathname.split("/");
    if (req.method !== "POST" || tail !== "token" || !UPSTREAM[name]) return new Response("not found", { status: 404 });
    const form = new URLSearchParams(await req.text());
    if (!["authorization_code", "refresh_token"].includes(form.get("grant_type"))) {
      return new Response('{"error":"unsupported_grant_type"}', { status: 400 });
    }
    const headers = { "content-type": "application/x-www-form-urlencoded" };
    if (name === "kick") {
      form.set("client_id", env.KICK_CLIENT_ID);
      form.set("client_secret", env.KICK_CLIENT_SECRET);
    } else {
      headers.authorization = "Basic " + btoa(`${env.RESTREAM_CLIENT_ID}:${env.RESTREAM_CLIENT_SECRET}`);
    }
    const r = await fetch(UPSTREAM[name], { method: "POST", headers, body: form });
    return new Response(r.body, { status: r.status, headers: { "content-type": r.headers.get("content-type") ?? "application/json" } });
  },
};
