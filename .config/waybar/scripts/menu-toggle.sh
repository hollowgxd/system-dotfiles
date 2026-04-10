#!/usr/bin/env bash

set -euo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-wofi"
last_close_file="$state_dir/last-close-ms"
close_grace_ms=400

mkdir -p "$state_dir"

now_ms() {
  date +%s%3N
}

if pgrep -x wofi >/dev/null 2>&1; then
  pkill -x wofi
  printf '%s\n' "$(now_ms)" > "$last_close_file"
  exit 0
fi

if [[ -f "$last_close_file" ]]; then
  last_close_ms="$(cat "$last_close_file" 2>/dev/null || printf '0')"
  current_ms="$(now_ms)"

  if [[ "$last_close_ms" =~ ^[0-9]+$ ]] && (( current_ms - last_close_ms < close_grace_ms )); then
    rm -f "$last_close_file"
    exit 0
  fi
fi

(
  wofi --conf "$HOME/.config/wofi/config" --style "$HOME/.config/wofi/style.css" --show drun >/dev/null 2>&1
  printf '%s\n' "$(now_ms)" > "$last_close_file"
) &
