#!/usr/bin/env bash

set -euo pipefail

if pgrep -x wofi >/dev/null 2>&1; then
  pkill -x wofi
else
  wofi -show drun -replace >/dev/null 2>&1 &
fi
