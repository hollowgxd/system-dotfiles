#!/usr/bin/env bash

set -euo pipefail

theme_file="${HOME}/.config/rofi/waybar-calendar.rasi"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-calendar-popup"
pid_file="${state_dir}/rofi.pid"
last_close_file="${state_dir}/last-close-ms"
calendar_file="${state_dir}/calendar.txt"
close_grace_ms=400
popup_timeout_s=20

mkdir -p "$state_dir"

now_ms() {
  date +%s%3N
}

record_close() {
  printf '%s\n' "$(now_ms)" > "$last_close_file"
}

if [[ -f "$pid_file" ]]; then
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
    record_close
    exit 0
  fi
  rm -f "$pid_file"
fi

if [[ -f "$last_close_file" ]]; then
  last_close_ms="$(cat "$last_close_file" 2>/dev/null || printf '0')"
  current_ms="$(now_ms)"

  if [[ "$last_close_ms" =~ ^[0-9]+$ ]] && (( current_ms - last_close_ms < close_grace_ms )); then
    exit 0
  fi
fi

calendar_rows="$(
python3 <<'PY'
import calendar
from datetime import date

today = date.today()
year = today.year
month = today.month

months = [
    "",
    "Январь",
    "Февраль",
    "Март",
    "Апрель",
    "Май",
    "Июнь",
    "Июль",
    "Август",
    "Сентябрь",
    "Октябрь",
    "Ноябрь",
    "Декабрь",
]
weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

title = f"{months[month]} {year}"
rows = [
    f"<span foreground='#F4EBFF' weight='700'>{title:^20}</span>",
    " ".join(
        f"<span foreground='{'#F0A7C8' if index >= 5 else '#C88CFF'}' weight='700'>{name}</span>"
        for index, name in enumerate(weekdays)
    ),
]

for week in calendar.Calendar(firstweekday=0).monthdayscalendar(year, month):
    parts = []
    for index, day in enumerate(week):
        if day == 0:
            parts.append("  ")
            continue

        cell = f"{day:>2}"
        if day == today.day:
            parts.append(
                "<span foreground='#FFFFFF' background='#9158F2' weight='700'>"
                f"{cell}</span>"
            )
        elif index >= 5:
            parts.append(f"<span foreground='#F0A7C8'>{cell}</span>")
        else:
            parts.append(f"<span foreground='#D9C8FA'>{cell}</span>")
    rows.append(" ".join(parts))

print("\n".join(rows))
PY
)"

printf '%s\n' "$calendar_rows" > "$calendar_file"

rofi \
  -no-config \
  -dmenu \
  -markup-rows \
  -no-custom \
  -monitor -5 \
  -theme "$theme_file" \
  -p "" < "$calendar_file" >/dev/null 2>&1 &
pid=$!

printf '%s\n' "$pid" > "$pid_file"

(
  sleep "$popup_timeout_s"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
) >/dev/null 2>&1 &

(
  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.2
  done
  record_close
  rm -f "$pid_file" "$calendar_file"
) >/dev/null 2>&1 &
