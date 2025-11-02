#!/usr/bin/env bash
set -euo pipefail
# Headless Spotify Web (Chromium + Xvfb) for Raspberry Pi / Debian 12+
# - User-level systemd unit (MPRIS-ready)
# - Xvfb virtual display, optional x11vnc viewer
# - Works with PipeWire (pipewire-pulse) or PulseAudio
#
# Usage examples:
#   sudo bash install-spotify-web-headless.sh
#   sudo bash install-spotify-web-headless.sh --user lucy --name "Arthur Pi"
#   sudo bash install-spotify-web-headless.sh --user lucy --name "Arthur Pi" --with-vnc --vnc-port 5901 --resolution 1280x720x24
#
# Uninstall:
#   sudo ./install-spotify-web-headless.sh --user lucy --uninstall

# -------- Defaults --------
RUN_USER="${SUDO_USER:-pi}"
DEVICE_NAME="Spotify Web Player"
DISPLAY_NUM=":99"
RESOLUTION="1280x720x24"
WITH_VNC="no"
VNC_PORT="5900"
UNINSTALL="no"

# -------- Arg parse --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) RUN_USER="$2"; shift 2 ;;
    --name) DEVICE_NAME="$2"; shift 2 ;;
    --display) DISPLAY_NUM="$2"; shift 2 ;;
    --resolution) RESOLUTION="$2"; shift 2 ;;
    --with-vnc) WITH_VNC="yes"; shift ;;
    --vnc-port) VNC_PORT="$2"; shift 2 ;;
    --uninstall) UNINSTALL="yes"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi
id -u "$RUN_USER" >/dev/null 2>&1 || { echo "User '$RUN_USER' not found"; exit 1; }

USER_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
USER_UID="$(id -u "$RUN_USER")"
RUNTIME_DIR="/run/user/$USER_UID"

UNIT_DIR="$USER_HOME/.config/systemd/user"
MAIN_UNIT="$UNIT_DIR/spotify-web.service"
VNC_UNIT="$UNIT_DIR/spotify-web-vnc.service"
LAUNCHER="/usr/local/bin/spotify-web-headless"

# -------- Uninstall --------
if [[ "$UNINSTALL" == "yes" ]]; then
  echo ">>> Stopping & removing services (user: $RUN_USER)…"
  mkdir -p "$UNIT_DIR"
  # Stop user units safely
  XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user stop spotify-web-vnc.service 2>/dev/null || true
  XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user disable spotify-web-vnc.service 2>/dev/null || true
  XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user stop spotify-web.service 2>/dev/null || true
  XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user disable spotify-web.service 2>/dev/null || true
  rm -f "$MAIN_UNIT" "$VNC_UNIT"
  XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user daemon-reload || true

  echo ">>> Removing launcher…"
  rm -f "$LAUNCHER"
  echo "✅ Uninstalled."
  exit 0
fi

# -------- Install packages --------
echo ">>> Installing packages…"
apt-get update
apt-get install -y \
  xvfb x11-utils x11-xserver-utils \
  dbus-user-session \
  playerctl \
  net-tools || true

# Audio servers (PipeWire Pulse is fine; fall back to PulseAudio if needed)
apt-get install -y pipewire-audio pipewire-pulse || true
apt-get install -y pulseaudio || true

# Chromium & DRM helpers (names differ across RPi OS vs Debian)
apt-get install -y chromium-browser || true
apt-get install -y chromium || true
apt-get install -y rpi-chromium-mods || true
apt-get install -y chromium-codecs-ffmpeg-extra || true

# Optional VNC
if [[ "$WITH_VNC" == "yes" ]]; then
  apt-get install -y x11vnc
fi

# Verify Chromium is available
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium || true)"
if [[ -z "${CHROMIUM_BIN}" ]]; then
  echo "ERROR: Chromium not found. Install 'chromium' or 'chromium-browser' and re-run." >&2
  exit 1
fi

# -------- Headless user-bus/session setup --------
echo ">>> Enabling headless user services (linger) for $RUN_USER…"
loginctl enable-linger "$RUN_USER" >/dev/null 2>&1 || true

echo ">>> Ensuring runtime dir & user@UID manager are up…"
mkdir -p "$RUNTIME_DIR"
chown "$RUN_USER":"$RUN_USER" "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
systemctl start "user@${USER_UID}.service" || true

# -------- Launcher script --------
echo ">>> Installing launcher: $LAUNCHER"
install -Dm0755 /dev/stdin "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Launch Chromium to open.spotify.com inside Xvfb display

DISPLAY_NUM="${DISPLAY_NUM:-:99}"
SCREEN_RES="${SCREEN_RES:-1280x720x24}"
PROFILE_DIR="${PROFILE_DIR:-$HOME/.config/spotify-web}"
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium)"

mkdir -p "$PROFILE_DIR" "$PROFILE_DIR/cache"

# Start Xvfb if it isn't running already
if ! xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; then
  /usr/bin/Xvfb "$DISPLAY_NUM" -screen 0 "$SCREEN_RES" -nolisten tcp &
  for _ in {1..30}; do
    sleep 0.2
    xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1 && break || true
  done
fi

export DISPLAY="$DISPLAY_NUM"

APP_NAME="${APP_NAME:-Spotify Web Player}"

exec "$CHROMIUM_BIN" \
  --no-first-run \
  --no-default-browser-check \
  --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --disk-cache-dir="$PROFILE_DIR/cache" \
  --user-data-dir="$PROFILE_DIR" \
  --password-store=basic \
  --window-size=1280,720 \
  --class="$APP_NAME" \
  --app=https://open.spotify.com/
EOF

# -------- User systemd unit(s) --------
echo ">>> Creating user systemd unit(s)…"
mkdir -p "$UNIT_DIR"
chown -R "$RUN_USER":"$RUN_USER" "$USER_HOME/.config"

# Main service
cat > "$MAIN_UNIT" <<EOF
[Unit]
Description=Headless Spotify Web (Chromium + Xvfb) - $DEVICE_NAME
After=network.target

[Service]
ExecStart=$LAUNCHER
Environment=DISPLAY_NUM=$DISPLAY_NUM
Environment=SCREEN_RES=$RESOLUTION
Environment=PROFILE_DIR=$USER_HOME/.config/spotify-web
Environment=APP_NAME=$DEVICE_NAME
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
chown "$RUN_USER":"$RUN_USER" "$MAIN_UNIT"

# Optional VNC viewer
if [[ "$WITH_VNC" == "yes" ]]; then
  cat > "$VNC_UNIT" <<EOF
[Unit]
Description=VNC for Headless Spotify Web (view $DISPLAY_NUM)
After=spotify-web.service
Requires=spotify-web.service

[Service]
Environment=DISPLAY=$DISPLAY_NUM
ExecStart=/usr/bin/x11vnc -display $DISPLAY_NUM -rfbport $VNC_PORT -forever -nopw -shared -repeat -xkb
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  chown "$RUN_USER":"$RUN_USER" "$VNC_UNIT"
fi

# -------- Enable + start (headless-safe via XDG_RUNTIME_DIR) --------
echo ">>> Enabling & starting user services…"
XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user daemon-reload
XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user enable --now spotify-web.service
if [[ "$WITH_VNC" == "yes" ]]; then
  XDG_RUNTIME_DIR="$RUNTIME_DIR" sudo -u "$RUN_USER" systemctl --user enable --now spotify-web-vnc.service
fi

echo
echo "✅ Installed."
echo "Device name: $DEVICE_NAME"
echo "User:        $RUN_USER"
echo "Display:     $DISPLAY_NUM"
echo "Resolution:  $RESOLUTION"
if [[ "$WITH_VNC" == "yes" ]]; then
  echo "VNC:         Port $VNC_PORT (connect to <pi-ip>:$VNC_PORT, no password)"
fi
echo
echo "First-time login:"
echo "  - Open VNC (if enabled) and sign in at open.spotify.com."
echo "  - If not using VNC, you can temporarily re-run with --with-vnc to log in once."
echo
echo "MPRIS test (once playing):"
echo "  XDG_RUNTIME_DIR=$RUNTIME_DIR sudo -u $RUN_USER playerctl --player=chromium metadata"
echo "  XDG_RUNTIME_DIR=$RUNTIME_DIR sudo -u $RUN_USER dbus-monitor \"interface='org.mpris.MediaPlayer2.Player'\" --session"
echo
echo "Logs:"
echo "  XDG_RUNTIME_DIR=$RUNTIME_DIR sudo -u $RUN_USER journalctl --user -u spotify-web.service -n 100 --no-pager --output=cat"
[[ "$WITH_VNC" == "yes" ]] && echo "  XDG_RUNTIME_DIR=$RUNTIME_DIR sudo -u $RUN_USER journalctl --user -u spotify-web-vnc.service -n 100 --no-pager --output=cat"
