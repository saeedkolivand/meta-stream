#!/usr/bin/env bash
# Free cloud relay for MetaStream: phone --(SRT, HEVC)--> this server --(RTMPS, H.264)--> Kick.
# Kick rejects HEVC, so the server transcodes; HEVC only pays off on the phone's uplink (~30-50% fewer bits).
#
# Target: Oracle Cloud "Always Free" Ampere A1 VM (arm64), Ubuntu 22.04/24.04. Also works on any Ubuntu/Debian box.
# Run on the server:   sudo KICK_KEY='sk_us-west-2_...' bash setup-oracle.sh
# Optional env: KICK_URL (default Kick's ingest), VIDEO_KBPS (6000), MAX_HEIGHT (1080), PRESET (veryfast).
# Re-run any time to change the key/settings; it keeps the SRT password unless you delete /etc/mediamtx/relay.env.
#
# ALSO open UDP 8890 in the Oracle console (this script can't): Networking > Virtual cloud networks > your VCN >
# Security Lists > Default > Add Ingress Rule: source 0.0.0.0/0, protocol UDP, destination port 8890.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
: "${KICK_KEY:?set KICK_KEY to your Kick stream key}"
KICK_URL="${KICK_URL:-rtmps://fa723fc1b171.global-contribute.live-video.net/app}"
VIDEO_KBPS="${VIDEO_KBPS:-6000}"
MAX_HEIGHT="${MAX_HEIGHT:-1080}"
PRESET="${PRESET:-veryfast}"
MTX_VERSION="v1.21.2"

case "$(uname -m)" in
  aarch64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) echo "unsupported arch $(uname -m)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive   # iptables-persistent otherwise stops at a debconf prompt
apt-get update -qq
apt-get install -y -qq ffmpeg curl iptables-persistent >/dev/null

# MediaMTX: receives SRT (H.265 ok), auth-gated.
if ! /usr/local/bin/mediamtx --version 2>/dev/null | grep -q "$MTX_VERSION"; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/bluenviron/mediamtx/releases/download/${MTX_VERSION}/mediamtx_${MTX_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C "$tmp"
  install -m 755 "$tmp/mediamtx" /usr/local/bin/mediamtx
  rm -rf "$tmp"
fi

mkdir -p /etc/mediamtx
id -u mediamtx >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin mediamtx

# Secrets live in one root/mediamtx-only env file, never in the world-readable config or the process list.
ENV=/etc/mediamtx/relay.env
SRT_PASS=$(grep -s '^SRT_PASS=' "$ENV" | cut -d= -f2- || true)
SRT_PASS="${SRT_PASS:-$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)}"
cat > "$ENV" <<EOF
SRT_PASS=$SRT_PASS
KICK_URL=$KICK_URL
KICK_KEY=$KICK_KEY
VIDEO_KBPS=$VIDEO_KBPS
MAX_HEIGHT=$MAX_HEIGHT
PRESET=$PRESET
EOF
chown root:mediamtx "$ENV"
chmod 640 "$ENV"

# Pusher: reads the local SRT stream, transcodes video to H.264 (Kick's only codec), copies the phone's AAC audio.
# scale caps the height (a 4K phone stream would melt 4 ARM cores); keyframe every 2 s is what Kick asks for.
cat > /usr/local/bin/kick-push <<'EOF'
#!/usr/bin/env bash
set -a; . /etc/mediamtx/relay.env; set +a
exec ffmpeg -hide_banner -loglevel warning \
  -i "srt://127.0.0.1:8890?streamid=read:live" \
  -vf "scale=-2:'min(${MAX_HEIGHT},ih)'" \
  -c:v libx264 -preset "$PRESET" -tune zerolatency -pix_fmt yuv420p \
  -b:v "${VIDEO_KBPS}k" -maxrate "${VIDEO_KBPS}k" -bufsize "$((VIDEO_KBPS * 2))k" \
  -force_key_frames "expr:gte(t,n_forced*2)" \
  -c:a copy \
  -f flv "${KICK_URL}/${KICK_KEY}"
EOF
chmod 755 /usr/local/bin/kick-push

# Only what this needs: SRT in, everything else off. Publishing needs the password; reading only from localhost.
cat > /etc/mediamtx/mediamtx.yml <<EOF
logLevel: info
authInternalUsers:
  - user: phone
    pass: $SRT_PASS
    ips: []
    permissions:
      - action: publish
        path: live
  - user: any
    pass:
    ips: ["127.0.0.1", "::1"]
    permissions:
      - action: read
        path: live
rtsp: false
rtmp: false
hls: false
webrtc: false
srt: true
srtAddress: :8890
paths:
  live:
    runOnReady: /usr/local/bin/kick-push
    runOnReadyRestart: true
EOF
chown root:mediamtx /etc/mediamtx/mediamtx.yml
chmod 640 /etc/mediamtx/mediamtx.yml

cat > /etc/systemd/system/mediamtx.service <<'EOF'
[Unit]
Description=MediaMTX SRT relay to Kick
After=network-online.target
Wants=network-online.target

[Service]
User=mediamtx
ExecStart=/usr/local/bin/mediamtx /etc/mediamtx/mediamtx.yml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Oracle's Ubuntu images ship an iptables REJECT rule; insert the SRT port ahead of it and persist.
iptables -C INPUT -p udp --dport 8890 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 8890 -j ACCEPT
netfilter-persistent save >/dev/null

systemctl daemon-reload
systemctl enable --now mediamtx >/dev/null
systemctl restart mediamtx

IP=$(curl -fsS https://ifconfig.me || echo "<server-ip>")
echo
echo "Relay is up. In MetaStream > Settings > Ingest, use this URL and pick the HEVC codec:"
echo
echo "  srt://${IP}:8890?streamid=publish:live:phone:${SRT_PASS}"
echo
echo "Logs: journalctl -u mediamtx -f   (ffmpeg warnings show up there too)"
echo "Remember: UDP 8890 must also be open in the Oracle VCN security list."
