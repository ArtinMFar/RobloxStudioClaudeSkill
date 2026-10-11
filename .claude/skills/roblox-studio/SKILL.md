---
name: roblox-studio
description: Install, launch and drive Roblox Studio inside a headless Linux cloud container (Claude Code on the web) using Wine, a virtual X display and CPU-only rendering - screenshots to see it, xdotool to click and type. Use when asked to open/run Roblox Studio, build a Roblox place or game, place parts, or publish to Roblox from the cloud environment.
---

# Roblox Studio in a cloud container

Roblox Studio is a Windows app. This skill runs it under **Wine** on a virtual
X display (**Xvfb**), rendered on the **CPU** (no GPU), and drives it like a
person would: take a screenshot, look at it, click/type with **xdotool**.

All commands below are relative to this skill's directory
(`.claude/skills/roblox-studio/`). `scripts/rs.sh help` lists every command.

## Status of this skill

| Step | Status |
|---|---|
| Install Wine + Studio, create prefix | Verified (Ubuntu 24.04, Wine 11.19 Staging, Studio 0.742) |
| Launch Studio, render UI, screenshot, click | Verified |
| CPU / "low resolution" management | Verified, numbers below |
| Sign-in links routed to the container's browser | Verified |
| Sign in | **Not yet completed** - see "Signing in" (CAPTCHA constraint) |
| Open Baseplate, place parts, save, publish | **Not yet verified** - planned approach below |

## Quick start

```bash
S=.claude/skills/roblox-studio/scripts
$S/install.sh            # once per container, ~3-5 min (apt + Wine prefix + ~1.1 GB Studio download)
$S/rs.sh start           # starts Xvfb :99 + openbox if needed, then Studio; waits for its window
$S/rs.sh shot "" 50      # half-size screenshot -> prints /tmp/roblox-shots/shot-HHMMSS.png
```

Then open the printed PNG with the Read tool to see the screen.

The container is ephemeral: when it is reclaimed, Wine, Studio and the login
are gone. Re-run `install.sh` in a new session (it is idempotent).

## How it works

- **Wine**: `winehq-staging` from dl.winehq.org, prefix `~/.wine-roblox`, Windows 10 mode.
- **Studio download**: `scripts/bootstrap_studio.py` reads the current
  `WindowsStudio64` version from `clientsettingscdn.roblox.com`, downloads every
  package in `setup.rbxcdn.com/<version>-rbxPkgManifest.txt`, checks MD5s,
  and extracts each zip to its folder (map taken from Bloxstrap) under
  `~/.local/share/roblox-studio/versions/<version>/`. The official
  `RobloxStudioInstaller.exe` is avoided because it needs WebView2. The
  proxy sometimes cuts big downloads; the script retries.
- **Display**: `Xvfb :99` at 1280x800x24 plus `openbox` (window manager, so
  maximize/minimize/focus work). Override size with `RS_RES=WxH` before the
  first `rs.sh display`/`start`.
- **Rendering**: Studio tries Vulkan first, rejects Mesa's lavapipe
  ("Device llvmpipe ... is emulated, skipping"), then uses **Direct3D 11 via
  Wine's wined3d -> OpenGL on Mesa llvmpipe**. That works. `install.sh` sets
  `FFlagDebugGraphicsPreferD3D11` in `ClientSettings/ClientAppSettings.json`
  to skip the failed Vulkan attempt. Check with
  `grep CreateGraphicsEngine "$(scripts/rs.sh logpath)"`.
- **Audio**: none; the ALSA errors in `/tmp/rs-studio.log` are harmless.
- **URLs**: Studio (through Wine) and Chromium open links with `xdg-open`.
  `install.sh` replaces it with `scripts/xdg-open`, which logs every URL to
  `/tmp/roblox-opened-urls.log` (`rs.sh urls`), opens http(s) links in the
  container's Chromium, and passes `roblox-studio-auth:`/`roblox-studio:`
  links to Studio.

## Seeing the screen

Screenshots cost context, so pick the cheapest one that answers the question.

| Need | Command | Approx. image tokens |
|---|---|---|
| Overview, find where things are | `rs.sh shot "" 50` (640x400) | ~350 |
| Read small text / exact coordinates | `rs.sh shot "" 100 WxH+X+Y` (crop at full res) | proportional to crop |
| Full detail | `rs.sh shot` (1280x800) | ~1400 |

- **Coordinates**: in a 50% screenshot multiply x and y by 2 to get screen
  coordinates. In a crop `WxH+X+Y`, add X and Y.
- Prefer text over pixels when you can:
  - `rs.sh status` - Studio PID and window titles (the title shows the open place).
  - `rs.sh log [n]` - Studio's own log (errors, loaded place, login events).
  - `rs.sh code` - the current Quick Sign-in code, from the log.
  - `rs.sh urls` - sign-in links Studio tried to open.

## Interacting

```bash
rs.sh full                 # ALWAYS first: raise + maximize Studio so it is on top
rs.sh click X Y            # left click (rclick, dclick also exist)
rs.sh drag X1 Y1 X2 Y2
rs.sh scroll X Y down 3
rs.sh type 'hello'         # types into the focused widget
rs.sh paste 'long text'    # clipboard + ctrl+v; much faster for code
rs.sh key ctrl+s           # xdotool key names: Return, Escape, Tab, ctrl+shift+x, alt+p, F5
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
| `rs.sh full` (maximized 1280x780, visible) | ~280% |
| `rs.sh low` (shrunk to its 640x520 minimum) | ~130% |
| `rs.sh hide` (minimized) | ~45% |

Changing the Xvfb screen size while Studio runs (`xrandr`) does **not** help:
windows keep their size and CPU stays the same. Manage the **window**
instead:

- `rs.sh hide` while you are writing code, waiting, or doing other work.
- `rs.sh full` right before you screenshot or click, so coordinates line up
  with what you see.
- Covering Studio with another window (e.g. Chromium) also throttles it.
- `rs.sh cpu` shows Studio's current CPU use.

## Signing in

Studio 0.742's login screen offers:

1. **Sign in** - a browser OAuth (PKCE) flow. Clicking it makes Wine open
   `https://apis.roblox.com/oauth/v1/authorize?...redirect_uri=roblox-studio-auth:/...`.
   The `state` contains the running Studio's PID and the PKCE challenge, so a
   link only works for the Studio process that made it. Click Sign in again
   for a fresh link after a restart. When the account is approved, the browser
   is redirected to `roblox-studio-auth:/?code=...&state=...`, and that URL has
   to reach this Studio: `rs.sh auth '<url>'`.
2. **Use another device** - a Quick Sign-in code (`rs.sh code`), refreshed every
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
  from `rs.sh urls`. On a desktop browser where they are signed in to Roblox,
  they open DevTools (F12) -> Network with "Preserve log" ticked, approve
  "Authorize Roblox Studio", press Cancel if the browser offers to open
  Roblox Studio, then Ctrl+F in the Network panel for
  `roblox-studio-auth:/?code` and paste the full URL back. Run
  `rs.sh auth '<url>'` quickly (the code is short-lived). This does not work
  well on phones, which don't show the final URL. *Not yet verified end to end.*
- **Quick Sign-in code**: send the user `rs.sh code`. The user found that this can
  be refused because the container and their device are on different
  networks.

After signing in, check `rs.sh shot "" 50` for Studio's start page, and
`rs.sh log` for login errors.

## Building and publishing (not yet verified)

Planned approach - update this section with real coordinates and gotchas
once a session gets past sign-in:

- **Open a Baseplate**: on the start page, click the **Baseplate**
  template (find it with a 50% screenshot). Wait for the window title to
  change (`rs.sh status`).
- **Place parts, reliable way**: open the **Command Bar** (View tab ->
  Command Bar), click into it, `rs.sh paste` Luau, press `Return`:
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

- **No Studio window**: `cat /tmp/rs-studio.log`, `rs.sh log 80`.
  `rs.sh stop && rs.sh start`.
- **Black or garbled viewport**: check the renderer line in the log (see How it
  works). Mesa must be installed (`glxinfo -B` under `DISPLAY=:99` should show
  llvmpipe).
- **Studio wants an update / login says the version is outdated**: re-run
  `install.sh`. The bootstrapper fetches the current version; `rs.sh start`
  uses the newest folder in `versions/`.
- **Clicks land in the wrong place**: run `rs.sh full` first, and make sure
  the coordinates come from a screenshot taken *after* that (scale factor!).
- **Wine hangs**: `rs.sh stop` (runs `wineserver -k`), then start again.

## Files

- `scripts/install.sh` - one-time setup (apt, WineHQ, prefix, Studio, URL router, Chromium policy)
- `scripts/bootstrap_studio.py` - Studio downloader/extractor
- `scripts/rs.sh` - display/Studio control, screenshots, input, CPU modes, sign-in helpers
- `scripts/xdg-open` - URL router installed to `/usr/local/bin/xdg-open`
- `scripts/browser.cjs` - Playwright-over-CDP helper for the container's Chromium (`rs.sh browser` starts it): `goto`, `shot`, `text`, `click`, `fill`, `select`, `eval`, `url`
