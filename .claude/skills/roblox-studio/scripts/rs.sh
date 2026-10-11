#!/bin/bash
# rs.sh - drive Roblox Studio (Wine) on a virtual X display.
# Run `rs.sh help` for the command list.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
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
  [ -n "$dir" ] || { echo "studio not installed; run install.sh" >&2; return 1; }
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
