#!/usr/bin/env bash

set -euo pipefail

config_dir="${HOME}/.config/cava"
preset="${1:-spectrum}"

case "$preset" in
  spectrum)
    config_path="${config_dir}/config"
    ;;
  horizontal|center)
    config_path="${config_dir}/config-horizontal"
    ;;
  waveform|wave)
    config_path="${config_dir}/config-waveform"
    ;;
  *)
    printf 'Usage: %s [spectrum|horizontal|waveform]\n' "${0##*/}" >&2
    exit 1
    ;;
esac

exec cava -p "$config_path"
