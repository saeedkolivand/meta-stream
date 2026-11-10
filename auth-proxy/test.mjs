// node auth-proxy/test.mjs — checks routing, grant filter, and that each secret lands where its upstream expects it.
import assert from "node:assert";
import worker from "./index.js";

const env = { KICK_CLIENT_ID: "kid", KICK_CLIENT_SECRET: "ks", RESTREAM_CLIENT_ID: "rid", RESTREAM_CLIENT_SECRET: "rs" };
let sent;
globalThis.fetch = async (url, init) => ((sent = { url, ...init }), new Response("{}", { status: 200 }));
const post = (path, body, method = "POST") => worker.fetch(new Request(`https://x${path}`, { method, body: method === "POST" ? body : undefined }), env);

assert.equal((await post("/kick/token", "grant_type=authorization_code&code=c")).status, 200);
assert.equal(sent.url, "https://id.kick.com/oauth/token");
assert.equal(sent.body.get("client_secret"), "ks");
assert.equal(sent.body.get("code"), "c");

await post("/restream/token", "grant_type=refresh_token&refresh_token=r");
assert.equal(sent.headers.authorization, "Basic " + btoa("rid:rs"));
assert.equal(sent.body.get("client_secret"), null);

assert.equal((await post("/kick/token", "grant_type=client_credentials")).status, 400);
assert.equal((await post("/twitch/token", "grant_type=refresh_token")).status, 404);
assert.equal((await post("/kick/token", "", "GET")).status, 404);
console.log("ok");
