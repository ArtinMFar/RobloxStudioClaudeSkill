---
name: roblox-studio
description: Install, launch and drive Roblox Studio inside a headless Linux cloud container (Claude Code on the web) using Wine, a virtual X display and CPU-only rendering - screenshots to see it, xdotool to click and type. Self-contained - all scripts are embedded. Use when asked to open/run Roblox Studio, build a Roblox place or game, place parts, or publish to Roblox from the cloud environment.
---

# Roblox Studio in a cloud container

Roblox Studio is a Windows app. This skill runs it under **Wine** on a virtual
X display (**Xvfb**), rendered on the **CPU** (no GPU), and drives it like a
person would: take a screenshot, look at it, click/type with **xdotool**.

This file is the whole skill: the scripts it needs are embedded in
**Appendix: script sources** at the end. Setup writes them to disk and puts a
small control command, `rbx`, on the PATH.

## Status of this skill

| Step | Status |
|---|---|
| Install Wine + Studio, create prefix | Verified from a clean container (Ubuntu 24.04, Wine 11.19 Staging, Studio 0.742), ~1-5 min |
| Launch Studio, render UI, screenshot, click | Verified |
| CPU / "low resolution" management | Verified, numbers below |
| Sign-in links routed to the container's browser | Verified |
| Sign in | **Not yet completed** - see "Signing in" (CAPTCHA constraint) |
| Open Baseplate, place parts, save, publish | **Not yet verified** - planned approach below |

## Setup (once per container)

1. If `command -v rbx && rbx status` works, setup is already done - skip to
   "Seeing the screen".
2. Write the five files from the appendix into
   `~/.local/share/roblox-studio/bin/`, **exactly** as shown (with the Write
   tool use absolute paths; `$HOME` is `/root` in Claude Code cloud
   containers, check with `echo $HOME`):
   `install.sh`, `rs.sh`, `bootstrap_studio.py`, `xdg-open`, `browser.cjs`.
3. Run (needs root or sudo; ~1-5 min: apt + Wine prefix + ~1.1 GB Studio download):
   ```bash
   chmod +x ~/.local/share/roblox-studio/bin/*
   ~/.local/share/roblox-studio/bin/install.sh
   rbx start            # starts Xvfb :99 + openbox if needed, then Studio; waits for its window
   rbx shot "" 50       # half-size screenshot -> prints /tmp/roblox-shots/shot-HHMMSS.png
   ```
4. Open the printed PNG with the Read tool to see the screen.

The container is ephemeral: when it is reclaimed, Wine, Studio and the login
are gone. Redo setup in a new session (`install.sh` is idempotent).
Shell variables don't persist between Bash calls, which is why everything
goes through the `rbx` command. `rbx help` lists all commands.

## How it works

- **Wine**: `winehq-staging` from dl.winehq.org, prefix `~/.wine-roblox`, Windows 10 mode.
- **Studio download**: `bootstrap_studio.py` reads the current
  `WindowsStudio64` version from `clientsettingscdn.roblox.com`, downloads every
  package in `setup.rbxcdn.com/<version>-rbxPkgManifest.txt`, checks MD5s,
  and extracts each zip to its folder (map taken from Bloxstrap) under
  `~/.local/share/roblox-studio/versions/<version>/`. The official
  `RobloxStudioInstaller.exe` is avoided because it needs WebView2. The
  proxy sometimes cuts big downloads; the script retries. If Roblox adds a
  package the map doesn't know, it is extracted to the root with a warning -
  look up its folder in Bloxstrap's `PackageDirectoryMap`.
- **Display**: `Xvfb :99` at 1280x800x24 plus `openbox` (window manager, so
  maximize/minimize/focus work). Override with `RS_RES=WxH rbx display`
  before Studio starts.
- **Rendering**: Studio tries Vulkan first, rejects Mesa's lavapipe
  ("Device llvmpipe ... is emulated, skipping"), then uses **Direct3D 11 via
  Wine's wined3d -> OpenGL on Mesa llvmpipe**. That works. `install.sh` sets
  `FFlagDebugGraphicsPreferD3D11` to skip the failed Vulkan attempt. Check
  with `grep CreateGraphicsEngine "$(rbx logpath)"`.
- **Studio flags** (FFlags) live in
  `~/.wine-roblox/drive_c/users/<user>/AppData/Local/Roblox/ClientSettings/ClientAppSettings.json`
  (not the per-version `ClientSettings/` folder: Studio calls that the legacy
  location, and it is lost on every Studio update).
- **Login page A/B test**: Roblox puts each machine (by its GUID) in a
  test group for Studio's login page. The control group gets an embedded
  WebView2 login, which fails under Wine with "Launch Failed - An error
  occurred while launching Studio login". `install.sh` forces the newer page
  by setting every `FIntStudioLoginPageRolloutPercent*` flag it finds in the
  live settings (`clientsettingscdn.roblox.com/v2/settings/application/PCStudioApp`)
  to 100. Check with `grep isInLoginPageTreatment "$(rbx logpath)"`
  (should say `inTreatment=true`).
- **Audio**: none; the ALSA errors in `/tmp/rs-studio.log` are harmless.
- **URLs**: Studio (through Wine) and Chromium open links with `xdg-open`.
  `install.sh` replaces it with the embedded `xdg-open`, which logs every URL
  to `/tmp/roblox-opened-urls.log` (`rbx urls`), opens http(s) links in the
  container's Chromium, and passes `roblox-studio-auth:`/`roblox-studio:`
  links to Studio.

## Seeing the screen

Screenshots cost context, so pick the cheapest one that answers the question.

| Need | Command | Approx. image tokens |
|---|---|---|
| Overview, find where things are | `rbx shot "" 50` (640x400) | ~350 |
| Read small text / exact coordinates | `rbx shot "" 100 WxH+X+Y` (crop at full res) | proportional to crop |
| Full detail | `rbx shot` (1280x800) | ~1400 |

- **Coordinates**: in a 50% screenshot multiply x and y by 2 to get screen
  coordinates. In a crop `WxH+X+Y`, add X and Y.
- Prefer text over pixels when you can:
  - `rbx status` - Studio PID and window titles (the title shows the open place).
  - `rbx log [n]` - Studio's own log (errors, loaded place, login events).
  - `rbx code` - the current Quick Sign-in code, from the log.
  - `rbx urls` - sign-in links Studio tried to open.

## Interacting

```bash
rbx full                 # ALWAYS first: raise + maximize Studio so it is on top
rbx click X Y            # left click (rclick, dclick also exist)
rbx drag X1 Y1 X2 Y2
rbx scroll X Y down 3
rbx type 'hello'         # types into the focused widget
rbx paste 'long text'    # clipboard + ctrl+v; much faster for code
rbx key ctrl+s           # xdotool key names: Return, Escape, Tab, ctrl+shift+x, alt+p, F5
```

Loop: screenshot -> decide -> act -> wait about 1 s -> screenshot again to
confirm. Studio under software rendering is slow, so give heavy actions
(opening a place, starting play mode) several seconds. Prefer keyboard
shortcuts and typing over finding small buttons.

## CPU and the "low resolution" idea

The container has 4 vCPUs and llvmpipe renders on them, so Studio's frame rate
competes with everything else. Measured on Studio's login screen:

| Studio window | Studio CPU |
|---|---|
| `rbx full` (maximized 1280x780, visible) | ~280% |
| `rbx low` (shrunk to its 640x520 minimum) | ~130% |
| `rbx hide` (minimized) | ~45% |

Changing the Xvfb screen size while Studio runs (`xrandr`) does **not** help:
windows keep their size and CPU stays the same. Manage the **window**
instead:

- `rbx hide` while you are writing code, waiting, or doing other work.
- `rbx full` right before you screenshot or click, so coordinates line up
  with what you see.
- Covering Studio with another window (e.g. Chromium) also throttles it.
- `rbx cpu` shows Studio's current CPU use.

## Signing in

Studio 0.742's login screen offers:

1. **Sign in** - a browser OAuth (PKCE) flow. Clicking it makes Wine open
   `https://apis.roblox.com/oauth/v1/authorize?...redirect_uri=roblox-studio-auth:/...`
   (read it with `rbx urls`). The `state` and PKCE challenge belong to the
   running Studio process, so a link only works for the Studio that made it.
   Click Sign in again for a fresh link after a restart. When the account is
   approved, the browser is redirected to
   `roblox-studio-auth:/?code=...&state=...`, and that URL has to reach this
   Studio: `rbx auth '<url>'`.
2. **Use another device** - a Quick Sign-in code (`rbx code`), refreshed every
   few minutes. The user enters it on a device that is already signed in
   (More -> Quick Sign-in, or https://www.roblox.com/crossdevicelogin/ConfirmCode).
3. **Create one** - opens `roblox.com/account/signupredir?returnUrl=<the authorize URL>`.

**CAPTCHA constraint:** Roblox shows a CAPTCHA puzzle for sign-up, password
login and email one-time-code login started from the container's browser.
**Do not solve, automate or relay CAPTCHAs** - the human verification must
happen on the user's own device. Also **never ask for a password or a
`.ROBLOSECURITY` cookie**. If a user pastes a cookie, don't use it, and tell
them to invalidate it (Settings -> Security -> log out of all other
sessions).

Ways forward, best first:

- **Desktop OAuth hand-off.** Click Studio's Sign in, give the user the URL
  from `rbx urls`. On a desktop browser where they are signed in to Roblox,
  they open DevTools (F12) -> Network with "Preserve log" ticked, approve
  "Authorize Roblox Studio", press Cancel if the browser offers to open
  Roblox Studio, then Ctrl+F in the Network panel for
  `roblox-studio-auth:/?code` and paste the full URL back. Run
  `rbx auth '<url>'` quickly (the code is short-lived). This does not work
  well on phones, which don't show the final URL. *Not yet verified end to end.*
- **Quick Sign-in code**: send the user `rbx code`. The user found that this can
  be refused because the container and their device are on different
  networks.

After signing in, check `rbx shot "" 50` for Studio's start page, and
`rbx log` for login errors.

## Building and publishing (not yet verified)

Planned approach - update this section with real coordinates and gotchas
once a session gets past sign-in:

- **Open a Baseplate**: on the start page, click the **Baseplate**
  template (find it with a 50% screenshot). Wait for the window title to
  change (`rbx status`).
- **Place parts, reliable way**: open the **Command Bar** (View tab ->
  Command Bar), click into it, `rbx paste` Luau, press `Return`:
  ```lua
  local p = Instance.new("Part")
  p.Size = Vector3.new(8, 1, 8); p.Position = Vector3.new(0, 5, 0)
  p.Anchored = true; p.BrickColor = BrickColor.new("Bright red")
  p.Parent = workspace
  ```
  Then confirm with a screenshot or by checking the Explorer. Prefer scripts
  for anything bigger than a few parts.
- **Place parts with the GUI**: Home tab -> Part (inserts at the camera
  focus), then the Move/Scale tools or the Properties panel.
- **Scripts**: insert a Script under ServerScriptService and paste the
  source into the script editor.
- **Save / publish**: File -> Publish to Roblox (`alt+p`), fill the dialog
  (name, description), then confirm. `ctrl+s` saves to Roblox once published.

## Troubleshooting

- **No Studio window**: `cat /tmp/rs-studio.log`, `rbx log 80`.
  `rbx stop && rbx start`.
- **"Launch Failed - An error occurred while launching Studio login"**: the
  login page experiment flag didn't apply (Roblox may have renamed it). Re-run
  `install.sh` (it re-reads the live flag names), `rbx stop && rbx start`, and
  check `grep isInLoginPageTreatment "$(rbx logpath)"`. If the flag is gone,
  search the live settings for a new `LoginPage` flag, or use the dialog's
  "Login via Browser" button.
- **Black or garbled viewport**: check the renderer line in the log (see How it
  works). Mesa must be installed (`DISPLAY=:99 glxinfo -B` should show
  llvmpipe).
- **Studio wants an update / login says the version is outdated**: re-run
  `install.sh`. The bootstrapper fetches the current version; `rbx start`
  uses the newest folder in `versions/`.
- **Clicks land in the wrong place**: run `rbx full` first, and make sure
  the coordinates come from a screenshot taken *after* that (scale factor!).
- **Wine hangs**: `rbx stop` (runs `wineserver -k`), then start again.
- **Driving the container's Chromium** (sign-in pages): `rbx browser [url]`
  starts it with remote debugging on :9222, then
  `node ~/.local/share/roblox-studio/bin/browser.cjs goto|shot|text|click|fill|select|eval|url ...`.

## Appendix: script sources

Write each file to `~/.local/share/roblox-studio/bin/<name>` verbatim.

### `install.sh`

One-time setup: apt packages, WineHQ, Wine prefix, Studio download, Studio flags, URL router, `rbx` link.

```bash
#!/bin/bash
# One-time setup of Roblox Studio under Wine in a headless Ubuntu 24.04
# container (Claude Code cloud). Safe to re-run. Takes ~3-5 minutes.
# Expects rs.sh, xdg-open and bootstrap_studio.py next to it.
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

log "URL router -> /usr/local/bin/xdg-open, rbx -> /usr/local/bin/rbx"
$SUDO install -m755 "$HERE/xdg-open" /usr/local/bin/xdg-open
$SUDO ln -sf "$HERE/rs.sh" /usr/local/bin/rbx

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

# Studio flags go in %LOCALAPPDATA%\Roblox\ClientSettings (survives updates).
FLAGS="$WINEPREFIX/drive_c/users/$(whoami)/AppData/Local/Roblox/ClientSettings/ClientAppSettings.json"
mkdir -p "$(dirname "$FLAGS")"
python3 - "$FLAGS" <<'EOF'
import json, sys, urllib.request
path = sys.argv[1]
try:
    flags = json.load(open(path))
except Exception:
    flags = {}
# Studio tries Vulkan first, rejects lavapipe ("emulated") and falls back to
# D3D11 via wined3d -> OpenGL (llvmpipe). Go to D3D11 directly.
flags["FFlagDebugGraphicsPreferD3D11"] = True
# Roblox A/B tests Studio's login page per machine GUID. The control group gets
# an embedded WebView2 login that fails under Wine ("Launch Failed"); force the
# newer page (browser Sign in + Quick Sign-in). The flag's numeric suffix
# changes between releases, so take the current names from the live settings.
try:
    url = "https://clientsettingscdn.roblox.com/v2/settings/application/PCStudioApp"
    live = json.load(urllib.request.urlopen(url, timeout=30))["applicationSettings"]
    for k in live:
        if k.startswith("FIntStudioLoginPageRolloutPercent"):
            flags[k] = 100
except Exception as e:
    print(f"[install] could not read live flags: {e}", file=sys.stderr)
json.dump(flags, open(path, "w"), indent=2)
EOF

log "done: $STUDIO"
echo "$STUDIO"
```

### `rs.sh`

The `rbx` control command (linked to /usr/local/bin/rbx by install.sh).

```bash
#!/bin/bash
# rs.sh (linked as /usr/local/bin/rbx) - drive Roblox Studio (Wine) on a
# virtual X display. Run `rbx help` for the command list.
set -uo pipefail
export DISPLAY="${RS_DISPLAY:-:99}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-roblox}"
RS_HOME="${RS_HOME:-$HOME/.local/share/roblox-studio}"
RS_RES="${RS_RES:-1280x800}"
RS_SHOTS="${RS_SHOTS:-/tmp/roblox-shots}"
LOGDIR="$WINEPREFIX/drive_c/users/$(whoami)/AppData/Local/Roblox/logs"

studio_dir() { ls -d "$RS_HOME"/versions/version-*/ 2>/dev/null | tail -1; }
studio_pid() { pgrep -f '^[A-Z]:.*RobloxStudioBeta\.exe' | head -1; }
studio_win() { xdotool search --name '^Roblox Studio$' 2>/dev/null | head -1 || true; }
# Any top-level Studio window (title is "<place> - Roblox Studio" once a place is open).
studio_any_win() { xdotool search --name 'Roblox Studio' 2>/dev/null | tail -1 || true; }
latest_log() { ls -t "$LOGDIR"/*Studio*last.log 2>/dev/null | head -1; }

cmd_display() {
  if ! xdpyinfo >/dev/null 2>&1; then
    nohup Xvfb "$DISPLAY" -screen 0 "${RS_RES}x24" +extension GLX +extension RANDR -nolisten tcp \
      >/tmp/rs-xvfb.log 2>&1 &
    for _ in $(seq 50); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.1; done
  fi
  pgrep -x openbox >/dev/null || { nohup openbox >/tmp/rs-openbox.log 2>&1 & sleep 0.5; }
  echo "display $DISPLAY $(xdpyinfo | awk '/dimensions/{print $2}')"
}

cmd_start() {
  cmd_display >/dev/null
  if [ -n "$(studio_pid)" ]; then echo "studio already running (pid $(studio_pid))"; return; fi
  local dir; dir=$(studio_dir)
  [ -n "$dir" ] || { echo "studio not installed; run $RS_HOME/bin/install.sh" >&2; return 1; }
  (cd "$dir" && WINEDEBUG=-all nohup wine RobloxStudioBeta.exe "$@" >/tmp/rs-studio.log 2>&1 &)
  for _ in $(seq 90); do [ -n "$(studio_any_win)" ] && break; sleep 1; done
  sleep 3
  echo "studio started: $(xdotool getwindowname "$(studio_any_win)" 2>/dev/null)"
}

cmd_stop() { WINEPREFIX="$WINEPREFIX" wineserver -k 2>/dev/null; echo stopped; }

cmd_status() {
  echo "display: $(xdpyinfo 2>/dev/null | awk '/dimensions/{print $2}' || echo down)"
  echo "studio pid: $(studio_pid || true)"
  wmctrl -lG 2>/dev/null | awk '{ $1=$1; print "  window:", $0 }'
}

# shot [file] [scale%] [crop WxH+X+Y]  -> prints file path
cmd_shot() {
  mkdir -p "$RS_SHOTS"
  local out="${1:-$RS_SHOTS/shot-$(date +%H%M%S).png}" scale="${2:-100}" crop="${3:-}"
  local args=()
  [ -n "$crop" ] && args+=(-crop "$crop" +repage)
  [ "$scale" != 100 ] && args+=(-resize "${scale}%")
  import -window root "${args[@]}" "$out" && echo "$out"
}

cmd_click() { xdotool mousemove "$1" "$2" click "${3:-1}"; }
cmd_dclick() { xdotool mousemove "$1" "$2" click --repeat 2 --delay 80 1; }
cmd_rclick() { xdotool mousemove "$1" "$2" click 3; }
cmd_drag() {
  xdotool mousemove "$1" "$2" mousedown 1 sleep 0.2 mousemove "$3" "$4" sleep 0.2 mouseup 1
}
cmd_scroll() {  # scroll X Y up|down [clicks]
  local b=4; [ "$3" = down ] && b=5
  xdotool mousemove "$1" "$2" click --repeat "${4:-3}" --delay 50 "$b"
}
cmd_type() { xdotool type --delay "${RS_TYPE_DELAY:-12}" -- "$*"; }
cmd_key() { xdotool key --delay 60 -- "$@"; }
# paste TEXT: put text on the X clipboard and press ctrl+v (fast for long code)
cmd_paste() { printf '%s' "$*" | xclip -selection clipboard; xdotool key ctrl+v; }

cmd_focus() { local w; w=$(studio_any_win); [ -n "$w" ] && wmctrl -ia "$w"; }
# full: maximized + focused (use before looking/clicking)
cmd_full() {
  local w; w=$(studio_any_win); [ -n "$w" ] || return 1
  wmctrl -ia "$w"; wmctrl -ir "$w" -b add,maximized_vert,maximized_horz; sleep 1
}
# low: shrink Studio's window (~half the CPU of maximized)
cmd_low() {
  local w; w=$(studio_any_win); [ -n "$w" ] || return 1
  wmctrl -ir "$w" -b remove,maximized_vert,maximized_horz; wmctrl -ir "$w" -e 0,0,0,640,400
}
# hide: minimize (~1/3 the CPU of maximized; Studio throttles when not visible)
cmd_hide() { local w; w=$(studio_any_win); [ -n "$w" ] && xdotool windowminimize "$w"; }

cmd_code() {  # current Quick Sign-in code shown on the login screen
  grep -o 'awaitQuickSignIn via polling: code=[A-Z0-9]*' "$(latest_log)" | tail -1 | cut -d= -f2
}
cmd_urls() { tail -n "${1:-5}" /tmp/roblox-opened-urls.log 2>/dev/null; }
cmd_auth() {  # hand a roblox-studio-auth:/?code=...&state=... URL to Studio
  case "$1" in roblox-studio-auth:*) xdg-open "$1" ;; *) echo "not a roblox-studio-auth URL" >&2; return 1 ;; esac
}
cmd_log() { tail -n "${1:-40}" "$(latest_log)"; }
cmd_logpath() { latest_log; }
cmd_cpu() {
  local p; p=$(studio_pid); [ -n "$p" ] || { echo "studio not running"; return 1; }
  top -b -d 3 -n 2 -p "$p" | awk 'NR>7 && $1 ~ /^[0-9]+$/ {v=$9} END{print v "%"}'
}

cmd_browser() {  # start Chromium (CDP on :9222) for sign-in flows; drive with browser.cjs
  cmd_display >/dev/null
  if curl -s localhost:9222/json/version >/dev/null; then echo "browser already running"; return; fi
  local chrome; chrome=$(ls /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | tail -1)
  chrome=${chrome:-$(command -v chromium || command -v google-chrome)}
  nohup "$chrome" --no-sandbox --remote-debugging-port=9222 --user-data-dir="$RS_HOME/chromium-profile" \
    --no-first-run --no-default-browser-check --window-position=0,0 --window-size=1280,770 \
    "${1:-about:blank}" >/tmp/rs-chromium.log 2>&1 &
  for _ in $(seq 50); do curl -s localhost:9222/json/version >/dev/null && break; sleep 0.2; done
  echo "browser started"
}

cmd_help() { sed -n '/^usage:/,/^EOF/p' "$0" | sed '1d;$d'; }
: <<'EOF'
usage:
  display                 start Xvfb (RS_RES, default 1280x800) + openbox
  start [args]            start Studio (waits for its window)
  stop | status | cpu     kill all Wine processes | windows+pid | Studio CPU%
  shot [file] [scale%] [crop]   screenshot, e.g. shot "" 50 or shot "" 100 400x300+0+0
  click X Y [btn] | dclick X Y | rclick X Y | drag X1 Y1 X2 Y2 | scroll X Y up|down [n]
  type TEXT | paste TEXT | key COMBO...   e.g. key ctrl+s, key Return
  focus | full | low | hide     raise | maximize | shrink 640x400 | minimize
  code                    current Quick Sign-in code (from Studio's log)
  urls [n]                URLs Studio tried to open (sign-in links)
  auth URL                pass a roblox-studio-auth:/?code=... URL to Studio
  log [n] | logpath       Studio log tail | path
  browser [url]           start Chromium with CDP on :9222 (see browser.cjs)
EOF

c="${1:-help}"; shift || true
if declare -f "cmd_$c" >/dev/null; then "cmd_$c" "$@"; else echo "unknown command: $c" >&2; cmd_help; exit 2; fi
```

### `bootstrap_studio.py`

Downloads and unpacks the current Roblox Studio build.

```python
#!/usr/bin/env python3
"""Download and unpack the current Roblox Studio (WindowsStudio64) build.

This replaces RobloxStudioInstaller.exe, which needs WebView2 and is flaky
under Wine. It does what Vinegar / Bloxstrap do: read the deployment's
rbxPkgManifest.txt, fetch every package zip from setup.rbxcdn.com, verify the
MD5, and extract it into the directory Studio expects.

Usage: bootstrap_studio.py [--dest DIR] [--channel CHANNEL] [--version VERSION]
Prints the install directory (the one containing RobloxStudioBeta.exe) on the
last line of stdout.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import sys
import time
import urllib.request
import zipfile

CDN = "https://setup.rbxcdn.com"
CLIENT_VERSION = "https://clientsettingscdn.roblox.com/v2/client-version/WindowsStudio64"

# Package -> sub directory, from Bloxstrap's RobloxStudioData/CommonAppData.
PACKAGE_DIRS = {
    "RobloxStudio.zip": "",
    "LibrariesQt5.zip": "",
    "Libraries.zip": "",
    "redist.zip": "",
    "WebView2.zip": "",
    "content-studio_svg_textures.zip": "content/studio_svg_textures",
    "content-qt_translations.zip": "content/qt_translations",
    "content-api-docs.zip": "content/api_docs",
    "extracontent-scripts.zip": "ExtraContent/scripts",
    "studiocontent-models.zip": "StudioContent/models",
    "studiocontent-textures.zip": "StudioContent/textures",
    "BuiltInPlugins.zip": "BuiltInPlugins",
    "BuiltInStandalonePlugins.zip": "BuiltInStandalonePlugins",
    "ApplicationConfig.zip": "ApplicationConfig",
    "Plugins.zip": "Plugins",
    "Qml.zip": "Qml",
    "StudioFonts.zip": "StudioFonts",
    "RibbonConfig.zip": "RibbonConfig",
    "shaders.zip": "shaders",
    "ssl.zip": "ssl",
    "WebView2RuntimeInstaller.zip": "WebView2RuntimeInstaller",
    "content-avatar.zip": "content/avatar",
    "content-configs.zip": "content/configs",
    "content-fonts.zip": "content/fonts",
    "content-sky.zip": "content/sky",
    "content-sounds.zip": "content/sounds",
    "content-textures2.zip": "content/textures",
    "content-models.zip": "content/models",
    "content-textures3.zip": "PlatformContent/pc/textures",
    "content-terrain.zip": "PlatformContent/pc/terrain",
    "content-platform-fonts.zip": "PlatformContent/pc/fonts",
    "content-platform-dictionaries.zip": "PlatformContent/pc/shared_compression_dictionaries",
    "extracontent-luapackages.zip": "ExtraContent/LuaPackages",
    "extracontent-translations.zip": "ExtraContent/translations",
    "extracontent-models.zip": "ExtraContent/models",
    "extracontent-textures.zip": "ExtraContent/textures",
    "extracontent-places.zip": "ExtraContent/places",
}

APP_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<Settings>
\t<ContentFolder>content</ContentFolder>
\t<BaseUrl>http://www.roblox.com</BaseUrl>
</Settings>
"""


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


def parse_manifest(text):
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    if lines[0] != "v0":
        raise SystemExit(f"unexpected manifest header {lines[0]!r}")
    pkgs = []
    for i in range(1, len(lines), 4):
        pkgs.append({"name": lines[i], "md5": lines[i + 1]})
    return pkgs


def download(base, pkg, cache):
    path = os.path.join(cache, pkg["md5"] + ".zip")
    if os.path.exists(path):
        if hashlib.md5(open(path, "rb").read()).hexdigest() == pkg["md5"]:
            return path
    for attempt in range(6):
        try:
            data = fetch(f"{base}-{pkg['name']}")
        except Exception as e:  # proxies sometimes cut long transfers
            print(f"{pkg['name']}: {e!r} (attempt {attempt + 1})", file=sys.stderr)
            time.sleep(2 ** attempt)
            continue
        if hashlib.md5(data).hexdigest() == pkg["md5"]:
            with open(path + ".part", "wb") as f:
                f.write(data)
            os.replace(path + ".part", path)
            return path
        print(f"md5 mismatch for {pkg['name']} (attempt {attempt + 1})", file=sys.stderr)
    raise SystemExit(f"could not download {pkg['name']}")


def extract(zpath, dest):
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            # Roblox zips use Windows separators.
            name = info.filename.replace("\\", "/").lstrip("/")
            if not name or name.endswith("/"):
                continue
            out = os.path.normpath(os.path.join(dest, name))
            if not out.startswith(os.path.normpath(dest)):
                continue
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(info) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default=os.path.expanduser("~/.local/share/roblox-studio/versions"))
    ap.add_argument("--version", help="explicit version-xxxxxxxx hash")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/roblox-studio/downloads"))
    args = ap.parse_args()

    version = args.version or json.loads(fetch(CLIENT_VERSION))["clientVersionUpload"]
    install = os.path.join(args.dest, version)
    exe = os.path.join(install, "RobloxStudioBeta.exe")
    if os.path.exists(exe) and os.path.exists(os.path.join(install, ".complete")):
        print(f"{version} already installed", file=sys.stderr)
        print(install)
        return

    base = f"{CDN}/{version}"
    pkgs = parse_manifest(fetch(f"{base}-rbxPkgManifest.txt").decode())
    os.makedirs(args.cache, exist_ok=True)
    os.makedirs(install, exist_ok=True)

    unknown = [p["name"] for p in pkgs if p["name"] not in PACKAGE_DIRS]
    if unknown:
        print(f"warning: unknown packages, extracting to root: {unknown}", file=sys.stderr)

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        futs = {ex.submit(download, base, p, args.cache): p for p in pkgs}
        for fut in concurrent.futures.as_completed(futs):
            p = futs[fut]
            zpath = fut.result()
            extract(zpath, os.path.join(install, PACKAGE_DIRS.get(p["name"], "")))
            print(f"  {p['name']}", file=sys.stderr)

    with open(os.path.join(install, "AppSettings.xml"), "w") as f:
        f.write(APP_SETTINGS)
    open(os.path.join(install, ".complete"), "w").close()
    print(f"installed {version}", file=sys.stderr)
    print(install)


if __name__ == "__main__":
    main()
```

### `xdg-open`

URL router, installed to /usr/local/bin/xdg-open by install.sh.

```bash
#!/bin/bash
# Installed as /usr/local/bin/xdg-open by install.sh.
# Wine's winebrowser and Chromium hand URLs to xdg-open. Route them:
#   roblox-studio-auth: / roblox-studio:  -> Roblox Studio under Wine
#   http(s)                               -> the container's Chromium
# Every URL is also logged so it can be read back with `rs.sh urls`.
url="$1"
echo "$(date -Is) $url" >> /tmp/roblox-opened-urls.log
export DISPLAY="${DISPLAY:-:99}" WINEPREFIX="${WINEPREFIX:-$HOME/.wine-roblox}" WINEDEBUG=-all
RS_HOME="${RS_HOME:-$HOME/.local/share/roblox-studio}"
case "$url" in
  roblox-studio-auth:*|roblox-studio:*)
    studio=$(ls -d "$RS_HOME"/versions/version-*/ 2>/dev/null | tail -1)
    cd "$studio" && exec wine RobloxStudioBeta.exe "$url" >> /tmp/roblox-protocol.log 2>&1 ;;
  http://*|https://*)
    chrome=$(ls /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | tail -1)
    chrome=${chrome:-$(command -v chromium || command -v google-chrome)}
    [ -n "$chrome" ] || exit 0
    exec "$chrome" --no-sandbox --user-data-dir="$RS_HOME/chromium-profile" "$url" >/dev/null 2>&1 ;;
esac
```

### `browser.cjs`

Playwright-over-CDP helper for the container's Chromium (sign-in pages).

```js
#!/usr/bin/env node
// Drive the container's Chromium (started by `rbx browser` with
// --remote-debugging-port=9222) over CDP. Used for Roblox sign-up / sign-in,
// since the OAuth redirect must land inside the container.
//
//   browser.cjs goto <url>                 navigate the active tab
//   browser.cjs shot <file.png> [scale]     screenshot the active tab
//   browser.cjs text                        visible text of the page
//   browser.cjs click <selector|text=...>   click an element
//   browser.cjs fill <selector> <value>     type into an input
//   browser.cjs select <selector> <value>   choose a <select> option
//   browser.cjs eval <js>                   evaluate JS, print JSON result
//   browser.cjs url                         print the active tab URL
const { chromium } = require(
  require("child_process").execSync("npm root -g").toString().trim() + "/playwright"
);

(async () => {
  const [cmd, ...args] = process.argv.slice(2);
  const browser = await chromium.connectOverCDP("http://127.0.0.1:9222");
  const ctx = browser.contexts()[0];
  let page = ctx.pages().filter((p) => !p.url().startsWith("devtools:")).pop();
  if (!page) page = await ctx.newPage();
  await page.bringToFront();
  try {
    switch (cmd) {
      case "goto":
        await page.goto(args[0], { waitUntil: "domcontentloaded", timeout: 60000 });
        await page.waitForTimeout(2000);
        console.log(page.url());
        break;
      case "shot":
        await page.screenshot({ path: args[0], scale: "css" });
        console.log(args[0]);
        break;
      case "text":
        console.log(await page.evaluate(() => document.body.innerText));
        break;
      case "click":
        await page.locator(args[0]).first().click({ timeout: 15000 });
        await page.waitForTimeout(1500);
        console.log("clicked", page.url());
        break;
      case "fill":
        await page.locator(args[0]).first().fill(args[1], { timeout: 15000 });
        console.log("filled");
        break;
      case "select":
        console.log(await page.locator(args[0]).first().selectOption(args[1]));
        break;
      case "eval":
        console.log(JSON.stringify(await page.evaluate(args[0]), null, 1));
        break;
      case "url":
        console.log(page.url());
        break;
      default:
        console.error("unknown command", cmd);
        process.exitCode = 2;
    }
  } finally {
    // Disconnect without closing the shared browser.
    await browser.close().catch(() => {});
  }
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
```

