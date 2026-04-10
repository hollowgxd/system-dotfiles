#!/usr/bin/env bash

set -euo pipefail

if [[ -n "${UWSM_APP_UNIT:-}" ]] && command -v uwsm >/dev/null 2>&1; then
  exec uwsm stop
fi

if [[ -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
  if loginctl terminate-session "$XDG_SESSION_ID"; then
    exit 0
  fi
fi

if command -v hyprctl >/dev/null 2>&1; then
  exec hyprctl dispatch exit
fi

echo "Unable to terminate the current desktop session" >&2
exit 1
