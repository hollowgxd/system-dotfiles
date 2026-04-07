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

monitor_json="$(hyprctl_cmd -j monitors | jq -c 'map(select(.focused == true))[0] // .[0]')"

if [[ -z "$monitor_json" || "$monitor_json" == "null" ]]; then
  echo "Could not determine target monitor." >&2
  exit 1
fi

mon_x="$(jq -r '.x' <<<"$monitor_json")"
mon_y="$(jq -r '.y' <<<"$monitor_json")"
mon_w="$(jq -r '.width' <<<"$monitor_json")"
mon_h="$(jq -r '.height' <<<"$monitor_json")"

outer_gap=24
inner_gap=20
top_reserved=48
bottom_reserved=24
bottom_ratio=46

usable_x=$((mon_x + outer_gap))
usable_y=$((mon_y + top_reserved))
usable_w=$((mon_w - outer_gap * 2))
usable_h=$((mon_h - top_reserved - bottom_reserved))

bottom_h=$((usable_h * bottom_ratio / 100))
top_h=$((usable_h - inner_gap - bottom_h))
top_w=$(((usable_w - inner_gap) / 2))
bottom_w=$usable_w

left_x=$usable_x
right_x=$((usable_x + top_w + inner_gap))
top_y=$usable_y
bottom_y=$((usable_y + top_h + inner_gap))

hardware_addr="$(wait_for_client "welcome-hardware")"
software_addr="$(wait_for_client "welcome-software")"
assistant_addr="$(wait_for_client "welcome-assistant")"

hyprctl_cmd --batch "\
dispatch movetoworkspacesilent ${workspace},address:${hardware_addr}; \
dispatch movewindowpixel exact ${left_x} ${top_y},address:${hardware_addr}; \
dispatch resizewindowpixel exact ${top_w} ${top_h},address:${hardware_addr}; \
dispatch movetoworkspacesilent ${workspace},address:${software_addr}; \
dispatch movewindowpixel exact ${right_x} ${top_y},address:${software_addr}; \
dispatch resizewindowpixel exact ${top_w} ${top_h},address:${software_addr}; \
dispatch movetoworkspacesilent ${workspace},address:${assistant_addr}; \
dispatch movewindowpixel exact ${left_x} ${bottom_y},address:${assistant_addr}; \
dispatch resizewindowpixel exact ${bottom_w} ${bottom_h},address:${assistant_addr}"
