#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo patch-prizrak-box-wallpaper.sh /path/to/image.jpg [target_app_asar]

Defaults:
  target_app_asar: /usr/lib/prizrak-box/app.asar

This replaces Prizrak-Box's built-in default wallpaper with the provided image
and saves a timestamped backup next to the original app.asar.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

image_path="${1:-}"
target_asar="${2:-/usr/lib/prizrak-box/app.asar}"

if [[ -z "$image_path" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$image_path" ]]; then
  printf 'Image not found: %s\n' "$image_path" >&2
  exit 1
fi

if [[ ! -f "$target_asar" ]]; then
  printf 'Target app.asar not found: %s\n' "$target_asar" >&2
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  printf 'Run this script with sudo/root privileges.\n' >&2
  exit 1
fi

if ! command -v asar >/dev/null 2>&1; then
  printf 'asar is required but not installed.\n' >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
workdir="$(mktemp -d /tmp/prizrak-box-wallpaper.XXXXXX)"
backup_path="${target_asar}.bak.${stamp}"

cleanup() {
  rm -rf "$workdir"
}

trap cleanup EXIT

mkdir -p "$workdir/extract" "$workdir/patch"

asar extract "$target_asar" "$workdir/extract"
cp -a "$workdir/extract/." "$workdir/patch/"

cp -f "$image_path" "$workdir/patch/.vite/build/images/default.jpg"
cp -f "$image_path" "$workdir/patch/.vite/renderer/px_window/images/default.jpg"

asar pack "$workdir/patch" "$workdir/app.asar"

cp -a "$target_asar" "$backup_path"
install -m 0644 "$workdir/app.asar" "$target_asar"

printf 'Patched: %s\n' "$target_asar"
printf 'Backup: %s\n' "$backup_path"
