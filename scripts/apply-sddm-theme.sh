#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_DIR="/usr/share/sddm/themes/sugar-candy"

install -d "$THEME_DIR/Backgrounds"
install -m 644 "$REPO_ROOT/.config/sddm/sugar-candy/theme.conf.user" \
  "$THEME_DIR/theme.conf.user"
install -m 644 "$REPO_ROOT/.config/hypr/wallpapers/sddm.png" \
  "$THEME_DIR/Backgrounds/sddm-login.png"

echo "Applied SDDM Sugar Candy overrides to $THEME_DIR"
