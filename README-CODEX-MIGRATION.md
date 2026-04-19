# Codex Migration Guide

Use this on another laptop to apply the current `system-dotfiles` setup quickly.

## 1) Sync repository

```bash
cd ~
if [ -d system-dotfiles/.git ]; then
  git -C system-dotfiles pull --ff-only
else
  git clone https://github.com/hollowgxd/system-dotfiles.git
fi
cd ~/system-dotfiles
```

## 2) Install configs into `$HOME`

```bash
./scripts/install.sh
```

This copies:
- Hyprland + `hyprland-gui.conf` (HyprMod managed file)
- Waybar config/scripts/icons + helper scripts from `.local/bin`
- GTK3/GTK4 theme overrides (including `gtk-4.0/gtk.css` for HyprMod styling)
- Wofi/XSettings/theme overlay files

## 3) Apply without reboot

```bash
hyprctl reload
pkill -x waybar || true
nohup waybar >/tmp/waybar.log 2>&1 &
pkill -x xsettingsd || true
nohup xsettingsd >/tmp/xsettingsd.log 2>&1 &
```

## 4) Cursor theme requirement

Configs expect cursor theme: `Moga-Neon-Purple`.

Check:

```bash
test -d /usr/share/icons/Moga-Neon-Purple/cursors && echo OK || echo MISSING
```

If missing, install/import that cursor theme first, then re-run step 3.

## 5) Quick validation

```bash
rg -n "Moga-Neon-Purple" ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprland-gui.conf ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini ~/.config/xsettingsd/xsettingsd.conf
```
