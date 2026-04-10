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

copy_executable() {
  local src="$1"
  local dest="$2"

  install -d "$(dirname "$dest")"
  install -m 755 "$src" "$dest"
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

copy_file "$REPO_ROOT/.config/gtk-3.0/settings.ini" "$TARGET_HOME/.config/gtk-3.0/settings.ini"
copy_file "$REPO_ROOT/.config/gtk-3.0/gtk.css" "$TARGET_HOME/.config/gtk-3.0/gtk.css"
copy_file "$REPO_ROOT/.config/gtk-4.0/settings.ini" "$TARGET_HOME/.config/gtk-4.0/settings.ini"
copy_file "$REPO_ROOT/.themes/WaybarDark/index.theme" "$TARGET_HOME/.themes/WaybarDark/index.theme"
copy_file "$REPO_ROOT/.themes/WaybarDark/gtk-3.0/gtk.css" "$TARGET_HOME/.themes/WaybarDark/gtk-3.0/gtk.css"

copy_file "$REPO_ROOT/.config/kitty/kitty.conf" "$TARGET_HOME/.config/kitty/kitty.conf"

copy_file "$REPO_ROOT/.config/waybar/config" "$TARGET_HOME/.config/waybar/config"
copy_file "$REPO_ROOT/.config/waybar/style.css" "$TARGET_HOME/.config/waybar/style.css"
copy_executable "$REPO_ROOT/.config/waybar/scripts/menu-status.sh" "$TARGET_HOME/.config/waybar/scripts/menu-status.sh"
copy_executable "$REPO_ROOT/.config/waybar/scripts/menu-toggle.sh" "$TARGET_HOME/.config/waybar/scripts/menu-toggle.sh"
copy_executable "$REPO_ROOT/.config/waybar/scripts/keyboard-layout.sh" "$TARGET_HOME/.config/waybar/scripts/keyboard-layout.sh"
copy_executable "$REPO_ROOT/.config/waybar/scripts/prizrak-launch.sh" "$TARGET_HOME/.config/waybar/scripts/prizrak-launch.sh"
copy_executable "$REPO_ROOT/.config/waybar/scripts/prizrak-status.sh" "$TARGET_HOME/.config/waybar/scripts/prizrak-status.sh"
copy_file "$REPO_ROOT/.config/waybar/icons/app.svg" "$TARGET_HOME/.config/waybar/icons/app.svg"
copy_file "$REPO_ROOT/.config/waybar/icons/network.svg" "$TARGET_HOME/.config/waybar/icons/network.svg"
copy_file "$REPO_ROOT/.config/waybar/icons/volume.svg" "$TARGET_HOME/.config/waybar/icons/volume.svg"
copy_file "$REPO_ROOT/.config/waybar/icons/volume-mute.svg" "$TARGET_HOME/.config/waybar/icons/volume-mute.svg"
copy_file "$REPO_ROOT/.config/waybar/icons/keyboard.svg" "$TARGET_HOME/.config/waybar/icons/keyboard.svg"
copy_file "$REPO_ROOT/.config/waybar/icons/clock.svg" "$TARGET_HOME/.config/waybar/icons/clock.svg"
copy_file "$REPO_ROOT/.config/waybar/icons/power-off.svg" "$TARGET_HOME/.config/waybar/icons/power-off.svg"

copy_file "$REPO_ROOT/.config/wofi/config" "$TARGET_HOME/.config/wofi/config"
copy_file "$REPO_ROOT/.config/wofi/style.css" "$TARGET_HOME/.config/wofi/style.css"

render_template "$REPO_ROOT/.config/wlogout/style.css" "$TARGET_HOME/.config/wlogout/style.css"
copy_file "$REPO_ROOT/.config/wlogout/rune1.png" "$TARGET_HOME/.config/wlogout/rune1.png"
copy_file "$REPO_ROOT/.config/wlogout/rune2.png" "$TARGET_HOME/.config/wlogout/rune2.png"
copy_file "$REPO_ROOT/.config/wlogout/rune3.png" "$TARGET_HOME/.config/wlogout/rune3.png"
copy_file "$REPO_ROOT/.config/wlogout/rune4.png" "$TARGET_HOME/.config/wlogout/rune4.png"
copy_file "$REPO_ROOT/.config/wlogout/rune5.png" "$TARGET_HOME/.config/wlogout/rune5.png"
copy_file "$REPO_ROOT/.config/wlogout/rune6.png" "$TARGET_HOME/.config/wlogout/rune6.png"

copy_file "$REPO_ROOT/.config/fastfetch/assets/fetch.png" "$TARGET_HOME/.config/fastfetch/assets/fetch.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/cain.png" "$TARGET_HOME/.config/fastfetch/assets/cain.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/mangekyo_square.jpg" "$TARGET_HOME/.config/fastfetch/assets/mangekyo_square.jpg"
copy_file "$REPO_ROOT/.config/fastfetch/assets/mangekyo_square_ff.png" "$TARGET_HOME/.config/fastfetch/assets/mangekyo_square_ff.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/rinne_square.jpg" "$TARGET_HOME/.config/fastfetch/assets/rinne_square.jpg"
copy_file "$REPO_ROOT/.config/fastfetch/assets/rinne_square_ff.png" "$TARGET_HOME/.config/fastfetch/assets/rinne_square_ff.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/slark_square.png" "$TARGET_HOME/.config/fastfetch/assets/slark_square.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/slark_square_ff.png" "$TARGET_HOME/.config/fastfetch/assets/slark_square_ff.png"
copy_file "$REPO_ROOT/.config/fastfetch/assets/mylogo.txt" "$TARGET_HOME/.config/fastfetch/assets/mylogo.txt"
render_template "$REPO_ROOT/.config/fastfetch/config.jsonc" "$TARGET_HOME/.config/fastfetch/config.jsonc"
render_template "$REPO_ROOT/.config/fastfetch/profiles/welcome-hardware.jsonc" "$TARGET_HOME/.config/fastfetch/profiles/welcome-hardware.jsonc"
render_template "$REPO_ROOT/.config/fastfetch/profiles/welcome-software.jsonc" "$TARGET_HOME/.config/fastfetch/profiles/welcome-software.jsonc"
render_template "$REPO_ROOT/.config/fastfetch/profiles/welcome-assistant.jsonc" "$TARGET_HOME/.config/fastfetch/profiles/welcome-assistant.jsonc"

copy_executable "$REPO_ROOT/scripts/install.sh" "$TARGET_HOME/.local/bin/system-dotfiles-install"
copy_executable "$REPO_ROOT/scripts/welcome-fastfetch.sh" "$TARGET_HOME/.local/bin/welcome-fastfetch"
copy_executable "$REPO_ROOT/scripts/welcome-hardware-shell.sh" "$TARGET_HOME/.local/bin/welcome-hardware-shell"
copy_executable "$REPO_ROOT/scripts/welcome-software-shell.sh" "$TARGET_HOME/.local/bin/welcome-software-shell"
copy_executable "$REPO_ROOT/scripts/welcome-assistant-shell.sh" "$TARGET_HOME/.local/bin/welcome-assistant-shell"
copy_executable "$REPO_ROOT/scripts/welcome-layout.sh" "$TARGET_HOME/.local/bin/welcome-layout"
copy_executable "$REPO_ROOT/scripts/welcome-scene.sh" "$TARGET_HOME/.local/bin/welcome-scene"

echo "Dotfiles installed into $TARGET_HOME"
