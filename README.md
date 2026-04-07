# system-dotfiles

Portable backup of the current Arch Linux desktop setup.

## Stack

- Distro: Arch Linux
- WM: Hyprland
- Bar: Waybar
- Launcher: Wofi
- Logout menu: Wlogout
- Terminal: Kitty
- Shell: fish
- Fetch tool: fastfetch

## Tracked

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

## Layout

- `.config/*` contains the active configs
- `archive/waybar` keeps older Waybar variants out of the active tree
- `scripts/install.sh` syncs the repo into `$HOME` and renders machine-specific paths
- `.config/fastfetch/profiles` contains dedicated welcome-screen profiles

## Portability Notes

- Machine-generated `fish_variables` is intentionally not tracked
- `hyprpaper.conf` and `fastfetch/config.jsonc` use `__HOME__` placeholders in the repo
- `scripts/install.sh` replaces `__HOME__` with the actual home directory during install

## Usage

1. Install packages from `pkglist-pacman.txt`
2. Install AUR packages from `pkglist-aur.txt`
3. Run `./scripts/install.sh`
4. Review monitor names, wallpaper selection, and any host-specific paths

## Welcome Profiles

- `welcome-hardware.jsonc`: hardware-focused terminal with `mangekyo_square.jpg`
- `welcome-software.jsonc`: software-focused terminal with `rinne_square.jpg`
- `welcome-assistant.jsonc`: assistant terminal with `slark_square.png`
- `welcome-fastfetch hardware|software|assistant` runs the matching profile after install
