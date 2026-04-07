#!/usr/bin/env bash

set -euo pipefail

clear
welcome-fastfetch assistant || true

printf '\n'
printf 'assistant terminal initialized\n'
printf 'this window is reserved for codex / assistant workflow\n'
printf '\n'

if command -v codex >/dev/null 2>&1; then
  exec codex
fi

exec fish -i
