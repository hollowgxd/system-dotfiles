#!/usr/bin/env bash

set -u

has_prizrak_window() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl clients 2>/dev/null | rg -q '(^|\s)(class|initialClass): Prizrak-Box$'
}

has_prizrak_process() {
  pgrep -f '/usr/lib/prizrak-box/app.asar' >/dev/null 2>&1 \
    || pgrep -f '^/usr/bin/prizrak-box(\s|$)' >/dev/null 2>&1 \
    || pgrep -f '^/usr/lib/prizrak-box/px(\s|$)' >/dev/null 2>&1
}

if has_prizrak_window; then
  printf '{"text":" ","class":"active","tooltip":"Prizrak Box window is open"}\n'
elif has_prizrak_process; then
  printf '{"text":" ","class":"active","tooltip":"Prizrak Box process is still running"}\n'
else
  printf '{"text":" ","class":"inactive","tooltip":"Prizrak Box is stopped"}\n'
fi
