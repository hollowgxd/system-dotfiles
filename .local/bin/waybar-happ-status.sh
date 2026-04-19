#!/usr/bin/env bash

set -u

CURRENT_USER="${USER:-$(id -un 2>/dev/null || true)}"

pgrep_safe() {
  if [[ -n "$CURRENT_USER" ]]; then
    pgrep -u "$CURRENT_USER" "$@" 2>/dev/null || true
  else
    pgrep "$@" 2>/dev/null || true
  fi
}

has_hyprctl() {
  command -v hyprctl >/dev/null 2>&1
}

to_lower() {
  tr '[:upper:]' '[:lower:]'
}

pid_cmdline_lower() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | to_lower
}

pid_exe_lower() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -L "/proc/$pid/exe" ]] || return 1
  readlink -f "/proc/$pid/exe" 2>/dev/null | to_lower
}

pid_parent() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/status" ]] || return 1
  awk '/^PPid:/ {print $2}' "/proc/$pid/status" 2>/dev/null
}

pid_is_happ_like() {
  local pid="$1"
  local cmd exe

  cmd="$(pid_cmdline_lower "$pid" || true)"
  exe="$(pid_exe_lower "$pid" || true)"

  [[ "$exe" == /opt/happ/* || "$exe" == */happ || "$exe" == */happd ]] && return 0
  [[ "$cmd" == /opt/happ/bin/happ* ]] && return 0
  [[ "$cmd" == /opt/happ/bin/happd* ]] && return 0
  [[ "$cmd" == happ || "$cmd" == happ\ * ]] && return 0
  [[ "$cmd" == happd || "$cmd" == happd\ * ]] && return 0
  return 1
}

pid_matches_happ_roots() {
  local pid="$1"
  local roots="$2"
  local cur="$pid"
  local depth

  [[ "$cur" =~ ^[0-9]+$ ]] || return 1

  for depth in {1..24}; do
    [[ "$cur" =~ ^[0-9]+$ && "$cur" -gt 1 ]] || break
    if [[ " $roots " == *" $cur "* ]]; then
      return 0
    fi
    cur="$(pid_parent "$cur" || true)"
  done
  return 1
}

get_happ_pids() {
  local pid
  {
    pgrep_safe -x Happ
    pgrep_safe -x happ
    pgrep_safe -x happd
    pgrep_safe -f '^/opt/happ/bin/Happ([[:space:]]|$)'
    pgrep_safe -f '/opt/happ/bin/Happ'
    pgrep_safe -f '/opt/happ/bin/happd([[:space:]]|$)'
    pgrep_safe -f '(^|/|[[:space:]])happd([[:space:]]|$)'
  } | awk 'NF' | sort -u \
    | while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        pid_is_happ_like "$pid" && printf '%s\n' "$pid"
      done \
    | sort -u | tr '\n' ' ' | sed 's/[[:space:]]\+$//'
}

has_happ_window() {
  has_hyprctl || return 1

  if command -v jq >/dev/null 2>&1; then
    local roots
    local addr
    local pid
    local class
    local initial
    local title

    roots="$(get_happ_pids)"

    while IFS=$'\t' read -r addr pid class initial title; do
      [[ -n "$addr" ]] || continue
      if printf '%s %s %s\n' "$class" "$initial" "$title" | to_lower | rg -q 'happ'; then
        return 0
      fi
      if pid_is_happ_like "$pid" || pid_matches_happ_roots "$pid" "$roots"; then
        return 0
      fi
    done < <(
      hyprctl -j clients 2>/dev/null \
        | jq -r '.[]? | [(.address // ""), ((.pid // 0)|tostring), (.class // ""), (.initialClass // ""), (.title // "")] | @tsv' 2>/dev/null
    )

    return 1
  fi

  hyprctl clients 2>/dev/null | rg -qi '(^|\s)(class|initialClass): .*happ'
}

has_happ_process() {
  [[ -n "$(get_happ_pids)" ]]
}

if has_happ_window; then
  printf '{"text":" ","class":"active","tooltip":"Happ window is open"}\n'
elif has_happ_process; then
  printf '{"text":" ","class":"inactive","tooltip":"Happ daemon is running (window is closed)"}\n'
else
  printf '{"text":" ","class":"inactive","tooltip":"Happ is stopped"}\n'
fi
