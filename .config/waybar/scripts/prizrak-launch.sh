#!/usr/bin/env bash

set -u

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="$LOCK_DIR/prizrak-launch.lock"
LOG_FILE="${LOCK_DIR}/prizrak-launch.log"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

focus_prizrak_window() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl clients 2>/dev/null | rg -q '(^|\s)(class|initialClass): Prizrak-Box$' || return 1
  hyprctl dispatch focuswindow 'class:^(Prizrak-Box)$' >/dev/null 2>&1
}

has_prizrak_window() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl clients 2>/dev/null | rg -q '(^|\s)(class|initialClass): Prizrak-Box$'
}

has_prizrak_process() {
  pgrep -f '/usr/lib/prizrak-box/app.asar' >/dev/null 2>&1 \
    || pgrep -f '^/usr/bin/prizrak-box(\s|$)' >/dev/null 2>&1 \
    || pgrep -f '^/usr/lib/prizrak-box/px(\s|$)' >/dev/null 2>&1 \
    || pgrep -f '^/usr/lib/electron34/electron .*?/usr/lib/prizrak-box/app.asar' >/dev/null 2>&1
}

stop_prizrak() {
  log "stop_prizrak: invoking pkexec root-stop"
  pkexec /usr/local/bin/prizrak-box-root-stop >/dev/null 2>&1 || true
}

start_prizrak() {
  log "start_prizrak: spawning /home/halflight/start-prizrak.sh"
  setsid bash -c 'exec 9>&-; exec /home/halflight/start-prizrak.sh' >/dev/null 2>&1 < /dev/null &
}

cleanup() {
  :
}

trap cleanup EXIT

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "lock busy: exiting"
  exit 0
fi

if has_prizrak_window || has_prizrak_process; then
  log "detected running instance: window/process found"
  stop_prizrak
  exit 0
fi

log "no running instance detected"
start_prizrak
