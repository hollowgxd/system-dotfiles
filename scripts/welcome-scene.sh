#!/usr/bin/env bash

set -euo pipefail

workspace="${1:-5}"

hyprctl_cmd() {
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl "$@"
    return
  fi

  if hyprctl instances 2>/dev/null | grep -q .; then
    hyprctl -i 0 "$@"
    return
  fi

  echo "No Hyprland instance detected. Run this inside your Hyprland session." >&2
  exit 1
}

open_window() {
  local title="$1"
  shift

  kitty \
    --detach \
    --class welcome-scene \
    --title "$title" \
    "$@"
}

hyprctl_cmd dispatch workspace "$workspace"

open_window "welcome-hardware" \
  sh -lc 'clear; welcome-fastfetch hardware; exec fish -i'

open_window "welcome-software" \
  sh -lc 'clear; welcome-fastfetch software; exec fish -i'

open_window "welcome-assistant" \
  sh -lc 'exec ~/.local/bin/welcome-assistant-shell'

sleep 1

"$HOME/.local/bin/welcome-layout" "$workspace"
