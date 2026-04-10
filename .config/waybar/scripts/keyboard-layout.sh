#!/usr/bin/env bash

set -euo pipefail

CONFIG_PATH="${HOME}/.config/hypr/hyprland.conf"

get_layouts() {
  local line
  line="$(sed -n 's/^[[:space:]]*kb_layout[[:space:]]*=[[:space:]]*//p' "$CONFIG_PATH" | head -n1)"
  line="${line// /}"
  if [[ -z "$line" ]]; then
    printf 'us\n'
    return
  fi
  tr ',' '\n' <<<"$line"
}

label_for_code() {
  case "$1" in
    us) printf 'EN' ;;
    ru) printf 'RU' ;;
    ua) printf 'UA' ;;
    de) printf 'DE' ;;
    fr) printf 'FR' ;;
    es) printf 'ES' ;;
    *) printf '%s' "${1^^}" ;;
  esac
}

find_keyboard_name() {
  hyprctl devices -j 2>/dev/null | jq -r '
    (.keyboards[] | select(.main == true) | .name),
    (.keyboards[0].name)
  ' | sed -n '/./{p;q;}'
}

get_active_layout_code() {
  local keymap
  keymap="$(hyprctl devices -j 2>/dev/null | jq -r '
    (.keyboards[] | select(.main == true) | .active_keymap),
    (.keyboards[0].active_keymap)
  ' | sed -n '/./{p;q;}')"

  keymap="${keymap,,}"

  case "$keymap" in
    *russian*|*рус*) printf 'ru' ;;
    *ukrain*|*укр*) printf 'ua' ;;
    *german*|*deutsch*) printf 'de' ;;
    *french*|*fran*) printf 'fr' ;;
    *spanish*|*espa*) printf 'es' ;;
    *english*|*"us"*) printf 'us' ;;
    *)
      while IFS= read -r code; do
        [[ -n "$code" ]] || continue
        if [[ "$keymap" == *"${code,,}"* ]]; then
          printf '%s' "$code"
          return
        fi
      done < <(get_layouts)
      printf '%s' "$(get_layouts | head -n1)"
      ;;
  esac
}

print_status() {
  mapfile -t layouts < <(get_layouts)
  local active next index=0

  active="$(get_active_layout_code)"
  next="${layouts[0]}"

  for i in "${!layouts[@]}"; do
    if [[ "${layouts[$i]}" == "$active" ]]; then
      index="$i"
      next="${layouts[$(((i + 1) % ${#layouts[@]}))]}"
      break
    fi
  done

  printf '{"text":"%s","tooltip":"Active: %s\\nNext: %s\\nClick: switch layout","class":"layout-%s"}\n' \
    "$(label_for_code "$active")" \
    "$(label_for_code "$active")" \
    "$(label_for_code "$next")" \
    "$active"
}

toggle_layout() {
  local keyboard
  keyboard="$(find_keyboard_name)"
  [[ -n "$keyboard" ]] || exit 1
  hyprctl switchxkblayout "$keyboard" next >/dev/null
}

case "${1:-status}" in
  toggle) toggle_layout ;;
  status) print_status ;;
  *) print_status ;;
esac
