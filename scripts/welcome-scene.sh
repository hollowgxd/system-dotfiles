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

get_client_address() {
  local title="$1"

  hyprctl_cmd -j clients | jq -r --arg title "$title" --argjson ws "$workspace" '
    .[]
    | select(.title == $title and .workspace.id == $ws)
    | .address
  ' | tail -n 1
}

wait_for_client() {
  local title="$1"
  local tries=50
  local addr=""

  while (( tries > 0 )); do
    addr="$(get_client_address "$title")"
    if [[ -n "$addr" ]]; then
      printf '%s\n' "$addr"
      return 0
    fi

    sleep 0.1
    tries=$((tries - 1))
  done

  echo "Timed out waiting for client: $title" >&2
  exit 1
}

open_window() {
  local title="$1"
  shift

  kitty \
    --detach \
    --class welcome-scene \
    --title "$title" \
    --override font_size=11.0 \
    --override window_padding_width=8 \
    "$@"
}

hyprctl_cmd dispatch workspace "$workspace"

open_window "welcome-hardware" \
  bash -lc 'exec "$HOME/.local/bin/welcome-hardware-shell"'

hardware_addr="$(wait_for_client "welcome-hardware")"

hyprctl_cmd dispatch focuswindow "address:${hardware_addr}"
hyprctl_cmd dispatch togglesplit

open_window "welcome-assistant" \
  bash -lc 'exec "$HOME/.local/bin/welcome-assistant-shell"'

assistant_addr="$(wait_for_client "welcome-assistant")"

hyprctl_cmd dispatch focuswindow "address:${hardware_addr}"
hyprctl_cmd dispatch togglesplit

open_window "welcome-software" \
  bash -lc 'exec "$HOME/.local/bin/welcome-software-shell"'

software_addr="$(wait_for_client "welcome-software")"

hyprctl_cmd --batch "\
dispatch settiled address:${hardware_addr}; \
dispatch settiled address:${software_addr}; \
dispatch settiled address:${assistant_addr}"
