#!/usr/bin/env bash

set -euo pipefail

profile="${1:-default}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
config_dir="$config_home/fastfetch"

case "$profile" in
  hardware)
    config_file="$config_dir/profiles/welcome-hardware.jsonc"
    ;;
  software)
    config_file="$config_dir/profiles/welcome-software.jsonc"
    ;;
  assistant)
    config_file="$config_dir/profiles/welcome-assistant.jsonc"
    ;;
  default)
    config_file="$config_dir/config.jsonc"
    ;;
  *)
    echo "Unknown fastfetch profile: $profile" >&2
    exit 1
    ;;
esac

exec fastfetch --config "$config_file"
