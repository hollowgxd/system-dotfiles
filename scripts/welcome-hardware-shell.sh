#!/usr/bin/env bash

set -euo pipefail

clear
"$HOME/.local/bin/welcome-fastfetch" hardware || true

printf '\n'

export FASTFETCH_SKIP_AUTO=1
exec fish -i
