#!/usr/bin/env python3

from __future__ import annotations

import calendar
import json
import os
import signal
import subprocess
import sys
from datetime import datetime
from html import escape
from pathlib import Path

STATE_DIR = Path.home() / ".cache" / "waybar"
STATE_FILE = STATE_DIR / "clock-calendar-state.json"
POPUP_PID_FILE = STATE_DIR / "clock-calendar-popup.pid"
WAYBAR_CONFIG_FILE = Path.home() / ".config" / "waybar" / "config"

MONTHS_RU = [
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

WEEKDAYS_RU = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

FG = "#eadfff"
ACCENT = "#c88cff"
HEADER = "#f4ebff"


def shift_month(year: int, month: int, delta: int) -> tuple[int, int]:
    month_index = year * 12 + (month - 1) + delta
    return month_index // 12, month_index % 12 + 1


def current_month() -> tuple[int, int]:
    now = datetime.now()
    return now.year, now.month


def default_state() -> dict[str, int | bool]:
    year, month = current_month()
    return {"year": year, "month": month, "alt": False}


def load_state() -> dict[str, int | bool]:
    state = default_state()
    if not STATE_FILE.exists():
        return state

    try:
        payload = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        saved_year = int(payload.get("year", state["year"]))
        saved_month = int(payload.get("month", state["month"]))
        alt = bool(payload.get("alt", False))
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return state

    if 1 <= saved_month <= 12:
        state["year"] = saved_year
        state["month"] = saved_month

    state["alt"] = alt
    return state


def reset_state() -> None:
    try:
        STATE_FILE.unlink()
    except FileNotFoundError:
        pass


def persist_state(state: dict[str, int | bool]) -> None:
    today_year, today_month = current_month()
    if (
        int(state["year"]) == today_year
        and int(state["month"]) == today_month
        and not bool(state["alt"])
    ):
        reset_state()
        return

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(
        {
            "year": int(state["year"]),
            "month": int(state["month"]),
            "alt": bool(state["alt"]),
        },
        ensure_ascii=False,
    )
    STATE_FILE.write_text(payload, encoding="utf-8")


def popup_pid() -> int | None:
    pids = popup_pids()
    return pids[0] if pids else None


def popup_pids() -> list[int]:
    seen: list[int] = []

    try:
        pid = int(POPUP_PID_FILE.read_text(encoding="utf-8").strip())
    except (FileNotFoundError, OSError, ValueError):
        pid = None

    if pid is not None:
        try:
            os.kill(pid, 0)
            seen.append(pid)
        except OSError:
            clear_popup_pid()

    try:
        proc = subprocess.run(
            ["pgrep", "-f", f"{__file__} popup"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return seen

    for line in proc.stdout.splitlines():
        try:
            found = int(line.strip())
        except ValueError:
            continue
        if found not in seen:
            seen.append(found)

    if seen:
        POPUP_PID_FILE.write_text(str(seen[0]), encoding="utf-8")
    else:
        clear_popup_pid()

    return seen


def clear_popup_pid() -> None:
    try:
        POPUP_PID_FILE.unlink()
    except FileNotFoundError:
        pass


def span(
    text: str,
    *,
    foreground: str | None = None,
    weight: str | None = None,
    underline: str | None = None,
) -> str:
    attrs = []
    if foreground:
        attrs.append(f"foreground='{foreground}'")
    if weight:
        attrs.append(f"weight='{weight}'")
    if underline:
        attrs.append(f"underline='{underline}'")

    attr_text = " ".join(attrs)
    body = escape(text)
    if attr_text:
        return f"<span {attr_text}>{body}</span>"
    return body


def render_weekday_row() -> str:
    cells = []
    for index, label in enumerate(WEEKDAYS_RU):
        color = ACCENT if index >= 5 else HEADER
        cells.append(span(label, foreground=color, weight="700"))
    return "\u00a0".join(cells)


def render_days(year: int, month: int, now: datetime) -> list[str]:
    cal = calendar.Calendar(firstweekday=calendar.MONDAY)
    lines: list[str] = []

    for week in cal.monthdayscalendar(year, month):
        cells = []
        for index, day in enumerate(week):
            if day == 0:
                cells.append("\u00a0\u00a0")
                continue

            text = f"{day:>2}".replace(" ", "\u00a0")
            color = ACCENT if index >= 5 else FG
            weight = None
            underline = None

            if (year, month, day) == (now.year, now.month, now.day):
                weight = "700"
                underline = "single"

            cells.append(
                span(
                    text,
                    foreground=color,
                    weight=weight,
                    underline=underline,
                )
            )

        lines.append("\u00a0".join(cells))

    while len(lines) < 6:
        lines.append("\u00a0".join(["\u00a0\u00a0"] * 7))

    return lines


def build_calendar_markup(year: int, month: int) -> str:
    now = datetime.now()
    title = span(f"{MONTHS_RU[month - 1]} {year}", foreground=HEADER, weight="700")
    lines = [render_weekday_row(), *render_days(year, month, now)]
    body = "\n".join(f"<span font_desc='JetBrains Mono 10'>{line}</span>" for line in lines)
    return f"{title}\n{body}"


def build_tooltip(year: int, month: int) -> str:
    return build_calendar_markup(year, month)


def format_bar_text(now: datetime, alt: bool) -> str:
    if alt:
        return f"{WEEKDAYS_RU[now.weekday()]} {now:%d.%m}"
    return now.strftime("%H:%M")


def print_status() -> int:
    now = datetime.now()
    state = load_state()
    payload = {
        "text": format_bar_text(now, bool(state["alt"])),
        "tooltip": build_tooltip(int(state["year"]), int(state["month"])),
        "class": ["expanded"] if popup_pids() else [],
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def call_hyprctl_json(*args: str) -> dict | list | None:
    try:
        proc = subprocess.run(
            ["hyprctl", *args, "-j"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None

    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def get_waybar_offsets() -> tuple[int, int]:
    margin_top = 12
    bar_height = 52

    try:
        payload = json.loads(WAYBAR_CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return margin_top, bar_height

    if isinstance(payload, dict):
        try:
            margin_top = int(payload.get("margin-top", margin_top))
        except (TypeError, ValueError):
            pass
        try:
            bar_height = int(payload.get("height", bar_height))
        except (TypeError, ValueError):
            pass

    return margin_top, bar_height


def get_popup_geometry(width: int, height: int) -> tuple[int, int]:
    cursor = call_hyprctl_json("cursorpos")
    cursor_x = int(float(cursor.get("x", 24))) if isinstance(cursor, dict) else 24
    cursor_y = int(float(cursor.get("y", 24))) if isinstance(cursor, dict) else 24
    margin_top, bar_height = get_waybar_offsets()

    monitors = call_hyprctl_json("monitors")
    monitor = None
    if isinstance(monitors, list):
        for candidate in monitors:
            x = int(candidate.get("x", 0))
            y = int(candidate.get("y", 0))
            w = int(candidate.get("width", 1920))
            h = int(candidate.get("height", 1080))
            if x <= cursor_x < x + w and y <= cursor_y < y + h:
                monitor = candidate
                break
        if monitor is None and monitors:
            monitor = next((m for m in monitors if m.get("focused")), monitors[0])

    popup_gap = 1

    if not isinstance(monitor, dict):
        return max(12, cursor_x - width // 2), margin_top + bar_height + popup_gap

    mx = int(monitor.get("x", 0))
    my = int(monitor.get("y", 0))
    mw = int(monitor.get("width", 1920))
    mh = int(monitor.get("height", 1080))
    reserved = monitor.get("reserved", [0, 0, 0, 0])
    reserved_top = 0
    if isinstance(reserved, list) and len(reserved) >= 2:
        try:
            reserved_top = int(reserved[1])
        except (TypeError, ValueError):
            reserved_top = 0

    rel_x = cursor_x - mx
    left = max(12, min(rel_x - width // 2, mw - width - 12))
    top_base = popup_gap if reserved_top > 0 else margin_top + bar_height + popup_gap
    top = max(top_base, 12)
    top = min(top, mh - height - 12)
    return left, top


def run_popup() -> int:
    import gi

    gi.require_version("Gdk", "3.0")
    gi.require_version("Gtk", "3.0")
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

    padding_x = 8
    padding_y = 7

    css = b"""
window#clock-popup {
  background: rgba(7, 4, 14, 0.98);
  border: 1px solid rgba(185, 121, 255, 0.34);
  border-radius: 14px;
}
#clock-popup-box {
  padding: 7px 8px;
}
#clock-popup-label {
  color: #f4ebff;
}
"""

    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.set_name("clock-popup")
    window.set_resizable(False)
    window.set_decorated(False)
    window.set_accept_focus(False)
    window.set_skip_taskbar_hint(True)
    window.set_skip_pager_hint(True)
    window.stick()

    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.TOP)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.NONE)
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.LEFT, True)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    box.set_name("clock-popup-box")
    label = Gtk.Label()
    label.set_name("clock-popup-label")
    label.set_use_markup(True)
    label.set_line_wrap(False)
    label.set_xalign(0.0)
    label.set_yalign(0.0)
    label.set_justify(Gtk.Justification.LEFT)
    box.pack_start(label, False, False, 0)
    window.add(box)

    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    screen = Gdk.Screen.get_default()
    if screen is not None:
        Gtk.StyleContext.add_provider_for_screen(
            screen,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    state_signature = ""

    def apply_popup_position(width: int, height: int) -> None:
        left, top = get_popup_geometry(width, height)
        GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, top)
        GtkLayerShell.set_margin(window, GtkLayerShell.Edge.LEFT, left)

        display = Gdk.Display.get_default()
        if display is not None and hasattr(display, "get_monitor_at_point"):
            monitor = display.get_monitor_at_point(left, top)
            if monitor is not None:
                GtkLayerShell.set_monitor(window, monitor)

    def update_window_size() -> tuple[int, int]:
        _min_width, natural_width = label.get_preferred_width()
        _min_height, natural_height = label.get_preferred_height()
        window_width = natural_width + padding_x * 2
        window_height = natural_height + padding_y * 2
        window.resize(window_width, window_height)
        return window_width, window_height

    def sync_popup_geometry() -> bool:
        window_width, window_height = update_window_size()
        apply_popup_position(window_width, window_height)
        return False

    def refresh() -> bool:
        nonlocal state_signature
        state = load_state()
        signature = f"{state['year']}-{state['month']}"
        if signature != state_signature:
            state_signature = signature
            label.set_markup(build_calendar_markup(int(state["year"]), int(state["month"])))
            GLib.idle_add(sync_popup_geometry)
        return True

    def shutdown(*_args) -> None:
        clear_popup_pid()
        Gtk.main_quit()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    POPUP_PID_FILE.write_text(str(os.getpid()), encoding="utf-8")

    refresh()
    GLib.timeout_add(150, refresh)
    window.connect("destroy", shutdown)
    window.show_all()
    GLib.idle_add(sync_popup_geometry)
    Gtk.main()
    return 0


def toggle_popup() -> int:
    pids = popup_pids()
    if pids:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        clear_popup_pid()
        return 0

    subprocess.Popen(
        [sys.executable, __file__, "popup"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    return 0


def handle_action(action: str) -> int:
    state = load_state()

    if action == "toggle-display":
        state["alt"] = not bool(state["alt"])
        persist_state(state)
        return 0

    if action == "today":
        year, month = current_month()
        state["year"] = year
        state["month"] = month
        persist_state(state)
        return 0

    if action == "toggle-popup":
        return toggle_popup()

    if action == "popup":
        return run_popup()

    delta = {"prev": -1, "next": 1}.get(action)
    if delta is None:
        return 1

    year, month = shift_month(int(state["year"]), int(state["month"]), delta)
    state["year"] = year
    state["month"] = month
    persist_state(state)
    return 0


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "status":
        return print_status()
    return handle_action(action)


if __name__ == "__main__":
    raise SystemExit(main())
