#!/bin/bash
# One-time setup of Roblox Studio under Wine in a headless Ubuntu 24.04
# container (Claude Code cloud). Safe to re-run. Takes ~3-5 minutes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-roblox}"
RS_HOME="${RS_HOME:-$HOME/.local/share/roblox-studio}"
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"

log() { echo "[install] $*" >&2; }

if ! command -v wine >/dev/null; then
  log "adding WineHQ repository"
  $SUDO dpkg --add-architecture i386
  $SUDO mkdir -pm755 /etc/apt/keyrings
  $SUDO curl -fsSL -o /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
  . /etc/os-release
  $SUDO curl -fsSL -o /etc/apt/sources.list.d/winehq-$VERSION_CODENAME.sources \
    https://dl.winehq.org/wine-builds/ubuntu/dists/$VERSION_CODENAME/winehq-$VERSION_CODENAME.sources
  $SUDO apt-get update -q >/dev/null
  log "installing winehq-staging"
  $SUDO apt-get install -y -q --install-recommends winehq-staging >/tmp/rs-wine-install.log 2>&1
fi

log "installing X/Mesa/automation packages"
$SUDO apt-get install -y -q xvfb xdotool x11-utils x11-xserver-utils xauth wmctrl openbox \
  imagemagick mesa-utils libgl1-mesa-dri mesa-vulkan-drivers cabextract unzip winbind \
  fonts-liberation fonts-dejavu-core xclip >/tmp/rs-x-install.log 2>&1

log "URL router -> /usr/local/bin/xdg-open"
$SUDO install -m755 "$HERE/xdg-open" /usr/local/bin/xdg-open

# Let Chromium hand roblox-studio-auth: redirects to xdg-open without a prompt.
$SUDO mkdir -p /etc/chromium/policies/managed
$SUDO tee /etc/chromium/policies/managed/roblox.json >/dev/null <<'EOF'
{
  "AutoLaunchProtocolsFromOrigins": [
    {"protocol": "roblox-studio-auth", "allowed_origins": ["*"]},
    {"protocol": "roblox-studio", "allowed_origins": ["*"]}
  ],
  "PasswordManagerEnabled": false
}
EOF

"$HERE/rs.sh" display >/dev/null

if [ ! -f "$WINEPREFIX/system.reg" ]; then
  log "creating Wine prefix $WINEPREFIX"
  DISPLAY=:99 WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i >/tmp/rs-wineboot.log 2>&1
  DISPLAY=:99 WINEDEBUG=-all wine reg add 'HKCU\Software\Wine' /v Version /d win10 /f >/dev/null 2>&1
  wineserver -w
fi

log "downloading Roblox Studio"
STUDIO=$(python3 "$HERE/bootstrap_studio.py" --dest "$RS_HOME/versions" | tail -1)

# Studio picks Vulkan first, rejects lavapipe ("emulated"), then falls back to
# D3D11 via wined3d -> OpenGL (llvmpipe). Prefer D3D11 directly.
mkdir -p "$STUDIO/ClientSettings"
[ -f "$STUDIO/ClientSettings/ClientAppSettings.json" ] || cat >"$STUDIO/ClientSettings/ClientAppSettings.json" <<'EOF'
{
  "FFlagDebugGraphicsPreferD3D11": true
}
EOF

log "done: $STUDIO"
echo "$STUDIO"
