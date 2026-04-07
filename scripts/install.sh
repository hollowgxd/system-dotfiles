#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_HOME="${HOME}"

copy_file() {
  local src="$1"
  local dest="$2"

  install -d "$(dirname "$dest")"
  cp "$src" "$dest"
}

render_template() {
  local src="$1"
  local dest="$2"

  install -d "$(dirname "$dest")"
  sed "s|__HOME__|$TARGET_HOME|g" "$src" > "$dest"
}

copy_file "$REPO_ROOT/.bashrc" "$TARGET_HOME/.bashrc"
copy_file "$REPO_ROOT/.bash_profile" "$TARGET_HOME/.bash_profile"
copy_file "$REPO_ROOT/.gitconfig" "$TARGET_HOME/.gitconfig"

copy_file "$REPO_ROOT/.config/fish/config.fish" "$TARGET_HOME/.config/fish/config.fish"
copy_file "$REPO_ROOT/.config/fish/conf.d/rustup.fish" "$TARGET_HOME/.config/fish/conf.d/rustup.fish"

copy_file "$REPO_ROOT/.config/hypr/hyprland.conf" "$TARGET_HOME/.config/hypr/hyprland.conf"
copy_file "$REPO_ROOT/.config/hypr/hyprlock.conf" "$TARGET_HOME/.config/hypr/hyprlock.conf"
copy_file "$REPO_ROOT/.config/hypr/wallpapers/takeu.png" "$TARGET_HOME/.config/hypr/wallpapers/takeu.png"
render_template "$REPO_ROOT/.config/hypr/hyprpaper.conf" "$TARGET_HOME/.config/hypr/hyprpaper.conf"

copy_file "$REPO_ROOT/.config/kitty/kitty.conf" "$TARGET_HOME/.config/kitty/kitty.conf"

copy_file "$REPO_ROOT/.config/waybar/config" "$TARGET_HOME/.config/waybar/config"
copy_file "$REPO_ROOT/.config/waybar/style.css" "$TARGET_HOME/.config/waybar/style.css"

copy_file "$REPO_ROOT/.config/wofi/config" "$TARGET_HOME/.config/wofi/config"
copy_file "$REPO_ROOT/.config/wofi/style.css" "$TARGET_HOME/.config/wofi/style.css"

copy_file "$REPO_ROOT/.config/wlogout/style.css" "$TARGET_HOME/.config/wlogout/style.css"

copy_file "$REPO_ROOT/.config/fastfetch/assets/fetch.png" "$TARGET_HOME/.config/fastfetch/assets/fetch.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/cain.png" "$TARGET_HOME/.config/fastfetch/assets/cain.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/mylogo.txt" "$TARGET_HOME/.config/fastfetch/assets/mylogo.txt"
render_template "$REPO_ROOT/.config/fastfetch/config.jsonc" "$TARGET_HOME/.config/fastfetch/config.jsonc"

echo "Dotfiles installed into $TARGET_HOME"
