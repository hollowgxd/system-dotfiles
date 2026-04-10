#!/usr/bin/env bash

set -euo pipefail

if pgrep -x wofi >/dev/null 2>&1; then
  pkill -x wofi
else
  wofi --conf "$HOME/.config/wofi/config" --style "$HOME/.config/wofi/style.css" --show drun --replace >/dev/null 2>&1 &
fi
