#!/usr/bin/env bash

set -u

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
if [[ ! -d "$LOCK_DIR" || ! -w "$LOCK_DIR" ]]; then
  LOCK_DIR="/tmp"
fi
LOCK_FILE="$LOCK_DIR/waybar-happ-control.lock"
LOG_FILE="$LOCK_DIR/waybar-happ-control.log"
APP_BIN="/opt/happ/bin/Happ"
CURRENT_USER="${USER:-$(id -un 2>/dev/null || true)}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

pgrep_safe() {
  if [[ -n "$CURRENT_USER" ]]; then
    pgrep -u "$CURRENT_USER" "$@" 2>/dev/null || true
  else
    pgrep "$@" 2>/dev/null || true
  fi
}

pkill_safe() {
  local signal="$1"
  shift
  if [[ -n "$CURRENT_USER" ]]; then
    pkill -u "$CURRENT_USER" "$signal" "$@" >/dev/null 2>&1 || true
  else
    pkill "$signal" "$@" >/dev/null 2>&1 || true
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

get_happ_client_addresses() {
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
        printf '%s\n' "$addr"
        continue
      fi

      if pid_is_happ_like "$pid" || pid_matches_happ_roots "$pid" "$roots"; then
        printf '%s\n' "$addr"
      fi
    done < <(
      hyprctl -j clients 2>/dev/null \
        | jq -r '.[]? | [(.address // ""), ((.pid // 0)|tostring), (.class // ""), (.initialClass // ""), (.title // "")] | @tsv' 2>/dev/null
    )

    return 0
  fi

  hyprctl clients 2>/dev/null \
    | awk '
        tolower($0) ~ /^(class|initialclass):/ && tolower($0) ~ /happ/ { hit=1 }
        /^Window / { if (hit && addr != "") print addr; hit=0; addr="" }
        /^Window / { addr=$2 }
        END { if (hit && addr != "") print addr }
      ' \
    | awk 'NF' \
    | sort -u
}

has_happ_window() {
  [[ -n "$(get_happ_client_addresses | head -n1)" ]]
}

focus_happ_window() {
  has_hyprctl || return 1
  local addr
  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    if hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1; then
      return 0
    fi
  done < <(get_happ_client_addresses)

  hyprctl dispatch focuswindow 'class:^(Happ|happ)$' >/dev/null 2>&1
}

close_happ_window() {
  has_hyprctl || return 1
  local addr
  local rc=1

  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1 && rc=0
  done < <(get_happ_client_addresses)

  if [[ $rc -eq 0 ]]; then
    return 0
  fi
  hyprctl dispatch closewindow 'class:^(Happ|happ)$' >/dev/null 2>&1
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

kill_happ_by_patterns() {
  local signal="$1"

  pkill_safe "$signal" -f '^/opt/happ/bin/Happ([[:space:]]|$)'
  pkill_safe "$signal" -x Happ
  pkill_safe "$signal" -x happ
  pkill_safe "$signal" -f '/opt/happ/bin/happd([[:space:]]|$)'
  pkill_safe "$signal" -f '(^|/|[[:space:]])happd([[:space:]]|$)'
  pkill_safe "$signal" -x happd
}

start_happ() {
  if command -v happ >/dev/null 2>&1; then
    log "start_happ: launching happ from PATH"
    # Close lock FD before exec so running app cannot keep the lock forever.
    setsid bash -c 'exec 9>&-; exec happ' >/dev/null 2>&1 < /dev/null &
    return 0
  fi

  if [[ -x "$APP_BIN" ]]; then
    log "start_happ: launching $APP_BIN"
    # Close lock FD before exec so running app cannot keep the lock forever.
    setsid bash -c 'exec 9>&-; exec "$1"' _ "$APP_BIN" >/dev/null 2>&1 < /dev/null &
    return 0
  fi

  log "start_happ: binary not found"
  return 1
}

collect_runtime_paths_from_pid() {
  local pid="$1"

  if [[ -r "/proc/$pid/cmdline" ]]; then
    tr '\0' '\n' < "/proc/$pid/cmdline" | rg '^(/tmp|/dev/shm)/' || true
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -w -Fn -p "$pid" 2>/dev/null | sed -n 's/^n//p' | rg '^(/tmp|/dev/shm)/' || true
  fi
}

cleanup_happ_runtime_artifacts() {
  local pids="$1"
  local candidates
  local dir
  local path

  candidates="$(
    {
      printf '%s\n' "/tmp/happd.sock"
      printf '%s\n' "/tmp/happ.sock"

      for pid in $pids; do
        collect_runtime_paths_from_pid "$pid"
      done

      for dir in /tmp /dev/shm "${XDG_RUNTIME_DIR:-}"; do
        [[ -n "$dir" && -d "$dir" ]] || continue
        if [[ -n "$CURRENT_USER" ]]; then
          find "$dir" -maxdepth 1 -user "$CURRENT_USER" \( -type f -o -type s \) \
            \( -name 'happ*.sock' -o -name 'happ*.policy' -o -name 'happd*' -o -name '*happd*' \) 2>/dev/null || true
          find "$dir" -maxdepth 1 -user "$CURRENT_USER" \( -type f -o -type s \) \
            -regextype posix-extended \
            -regex '.*/tc[A-Za-z0-9+/=]{8,}$' 2>/dev/null || true
        else
          find "$dir" -maxdepth 1 \( -type f -o -type s \) \
            \( -name 'happ*.sock' -o -name 'happ*.policy' -o -name 'happd*' -o -name '*happd*' \) 2>/dev/null || true
          find "$dir" -maxdepth 1 \( -type f -o -type s \) \
            -regextype posix-extended \
            -regex '.*/tc[A-Za-z0-9+/=]{8,}$' 2>/dev/null || true
        fi
      done
    } | awk 'NF' | sort -u
  )"

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" != /tmp/* && "$path" != /dev/shm/* ]]; then
      [[ -n "${XDG_RUNTIME_DIR:-}" && "$path" == "$XDG_RUNTIME_DIR"/* ]] || continue
    fi
    if [[ "$path" == "$LOCK_FILE" || "$path" == "$LOG_FILE" ]]; then
      continue
    fi
    case "$(basename "$path")" in
      waybar-happ-control.lock|waybar-happ-control.log)
        continue
        ;;
    esac
    if [[ -e "$path" || -L "$path" ]]; then
      rm -f -- "$path" 2>/dev/null || true
      log "cleanup: removed $path"
    fi
  done <<< "$candidates"
}

stop_happ() {
  local pids="$1"
  local alive=""
  local i

  close_happ_window || true
  sleep 0.2

  if [[ -n "$pids" ]]; then
    log "stop_happ: SIGTERM pids=$pids"
    kill $pids >/dev/null 2>&1 || true
  fi
  kill_happ_by_patterns -TERM

  for i in {1..20}; do
    alive="$(get_happ_pids)"
    [[ -z "$alive" ]] && break
    sleep 0.15
  done

  if [[ -n "$alive" ]]; then
    log "stop_happ: SIGKILL pids=$alive"
    kill -9 $alive >/dev/null 2>&1 || true
    kill_happ_by_patterns -KILL
    sleep 0.1
    alive="$(get_happ_pids)"
  fi
  if [[ -n "$alive" ]]; then
    log "stop_happ: residual pids after SIGKILL: $alive"
  fi

  cleanup_happ_runtime_artifacts "$pids $alive"
}

action="${1:-open}"
LOCK_WAIT_SECONDS=8

exec 9>"$LOCK_FILE"
if ! flock -w "$LOCK_WAIT_SECONDS" 9; then
  log "lock timeout (${LOCK_WAIT_SECONDS}s): skipping action=$action"
  exit 0
fi

case "$action" in
  close|stop|kill)
    stop_happ "$(get_happ_pids)"
    ;;
  *)
    if has_happ_window; then
      log "open: window detected, focusing"
      focus_happ_window || true
      exit 0
    fi

    if [[ -n "$(get_happ_pids)" ]]; then
      reset_pids=""
      log "open: process detected without focused window, trying focus"
      focus_happ_window || true

      for _ in {1..12}; do
        sleep 0.15
        has_happ_window && break
      done

      if ! has_happ_window; then
        reset_pids="$(get_happ_pids)"
        if [[ -n "$reset_pids" ]]; then
          log "open: stale process without window, applying reset pids=$reset_pids"
          stop_happ "$reset_pids"
        fi
        log "open: relaunch after reset"
        start_happ || exit 1
        for _ in {1..24}; do
          sleep 0.15
          has_happ_window && break
        done
      fi

      focus_happ_window || true
      exit 0
    fi

    log "open: no process found, launching"
    start_happ || exit 1

    for _ in {1..20}; do
      sleep 0.15
      has_happ_window && break
    done
    focus_happ_window || true
    ;;
esac
