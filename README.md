# system-dotfiles

Personal Arch Linux dotfiles and package manifests for recreating the current desktop setup.

## Included

- `~/.config/hypr`
- `~/.config/waybar`
- `~/.config/kitty`
- `~/.config/fish`
- `~/.config/wofi`
- `~/.config/wlogout`
- `~/.config/fastfetch`
- `~/.bashrc`
- `~/.bash_profile`
- `~/.gitconfig`
- `pkglist-pacman.txt`
- `pkglist-aur.txt`

## Current Stack

- Distro: Arch Linux
- WM: Hyprland
- Bar: Waybar
- Launcher: Wofi
- Logout menu: Wlogout
- Terminal: Kitty
- Shell: fish

## Notes

- Some configs reference local absolute paths.
- `hyprpaper.conf` points to `/home/halflight/Изображения/takeu.png`
- `fastfetch/config.jsonc` references local image assets and a Steam screenshot path

## Restore Outline

1. Install packages from `pkglist-pacman.txt`
2. Install AUR packages from `pkglist-aur.txt`
3. Copy the files into `$HOME`
4. Review absolute paths in Hyprland and Fastfetch configs

