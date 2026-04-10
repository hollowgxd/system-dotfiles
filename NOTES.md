# System Notes

## Current Defaults

- Terminal: `kitty`
- File manager: `thunar`
- App launcher: `wofi --show drun`
- Browser: `firefox`

## Hyprland

- `Super+E` must open the configured file manager, currently `thunar`.
- `Super+Shift+W` launches `~/.local/bin/welcome-scene`.
- Do not reintroduce `windowrule2`; treat it as deprecated in this setup.
- Do not use `gestures:workspace_swipe`; it does not exist in the current Hyprland version here.

## Welcome Scene

- The assistant window must start directly in `codex`, without `fastfetch`.
- Keep the welcome scene on native Hyprland tiling. Do not switch it back to pixel-positioned floating layout.
- Current scene order in `welcome-scene.sh`:
  - open `assistant`
  - `layoutmsg preselect u`
  - open `hardware`
  - `layoutmsg preselect r`
  - open `software`

## Fastfetch Assets

- Hardware profile uses `~/.config/fastfetch/assets/mangekyo_square.png` because it has the correct crop.

## Theme Notes

- The current visual source of truth is the purple neon Waybar theme the user provided in chat.
- Wlogout should visually match that Waybar theme: deep violet background, neon purple borders/glow, glassy dark panels, JetBrains Mono, and rune image buttons.
- Do not restyle Waybar itself unless explicitly asked; only adapt adjacent UI like Wlogout to match it.
