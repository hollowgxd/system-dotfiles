#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

STATE_DIR = Path.home() / ".cache" / "waybar"
POPUP_PID_FILE = STATE_DIR / "volume-popup.pid"
CAVA_CONFIG_FILE = STATE_DIR / "volume-cava.conf"
CAVA_FIFO_FILE = STATE_DIR / "volume-cava.fifo"
WAYBAR_CONFIG_FILE = Path.home() / ".config" / "waybar" / "config"

FG = "#eadfff"
HEADER = "#f4ebff"
ACCENT = "#c88cff"
MUTED = "#ffbfd1"
BAR_COUNT = 24
CAVA_RANGE = 100


def run_command(*args: str) -> str | None:
    try:
        proc = subprocess.run(
            list(args),
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    return proc.stdout.strip()


def get_volume_info() -> tuple[int, bool]:
    output = run_command("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@") or ""
    match = re.search(r"Volume:\s+([0-9]*\.?[0-9]+)", output)
    if not match:
        return 0, False

    muted = "[MUTED]" in output.upper()
    volume = round(float(match.group(1)) * 100)
    return max(0, min(int(volume), 200)), muted


def get_sink_metadata() -> dict[str, str]:
    output = run_command("wpctl", "inspect", "@DEFAULT_AUDIO_SINK@") or ""
    metadata: dict[str, str] = {
        "name": "Audio",
        "source": "auto",
    }

    for raw_line in output.splitlines():
        line = raw_line.strip()
        if "=" not in line:
            continue

        key, value = [part.strip() for part in line.split("=", 1)]
        key = key.lstrip("* ").strip()
        value = value.strip().strip('"')

        if key == "node.nick" and value:
            metadata["name"] = value
        elif key == "node.description" and value and metadata["name"] == "Audio":
            metadata["name"] = value
        elif key == "node.name" and value:
            # CAVA's PipeWire input wants the monitor source node name for the
            # active sink. Passing PipeWire object.path makes it fall back to
            # the default input source, which in this setup is the microphone.
            metadata["source"] = f"{value}.monitor"

    return metadata


def clear_popup_pid() -> None:
    try:
        POPUP_PID_FILE.unlink()
    except FileNotFoundError:
        pass


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
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        POPUP_PID_FILE.write_text(str(seen[0]), encoding="utf-8")
    else:
        clear_popup_pid()

    return seen


def print_status() -> int:
    volume, muted = get_volume_info()
    classes: list[str] = []
    if muted:
        classes.append("muted")
    if popup_pids():
        classes.append("expanded")

    payload = {
        "text": "0%" if muted else f"{volume}%",
        "class": classes,
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


def span(text: str, *, foreground: str | None = None, weight: str | None = None) -> str:
    attrs = []
    if foreground:
        attrs.append(f"foreground='{foreground}'")
    if weight:
        attrs.append(f"weight='{weight}'")
    attr_text = " ".join(attrs)
    if attr_text:
        return f"<span {attr_text}>{text}</span>"
    return text


def rounded_rectangle(cr, x: float, y: float, width: float, height: float, radius: float) -> None:
    radius = max(0.0, min(radius, width / 2, height / 2))
    cr.new_sub_path()
    cr.arc(x + width - radius, y + radius, radius, -1.5708, 0.0)
    cr.arc(x + width - radius, y + height - radius, radius, 0.0, 1.5708)
    cr.arc(x + radius, y + height - radius, radius, 1.5708, 3.1416)
    cr.arc(x + radius, y + radius, radius, 3.1416, 4.7124)
    cr.close_path()


def hex_to_rgba(color: str, alpha: float) -> tuple[float, float, float, float]:
    color = color.lstrip("#")
    if len(color) != 6:
        return 1.0, 1.0, 1.0, alpha
    return (
        int(color[0:2], 16) / 255.0,
        int(color[2:4], 16) / 255.0,
        int(color[4:6], 16) / 255.0,
        alpha,
    )


def write_cava_config(source: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    try:
        CAVA_FIFO_FILE.unlink()
    except FileNotFoundError:
        pass

    config = "\n".join(
        [
            "[general]",
            f"bars = {BAR_COUNT}",
            "framerate = 90",
            "autosens = 1",
            "sensitivity = 130",
            "",
            "[input]",
            "method = pipewire",
            f"source = {source}",
            "",
            "[output]",
            "method = raw",
            "channels = mono",
            "mono_option = average",
            f"raw_target = {CAVA_FIFO_FILE}",
            "data_format = ascii",
            f"ascii_max_range = {CAVA_RANGE}",
            "bar_delimiter = 59",
            "frame_delimiter = 10",
            "",
        ]
    )
    CAVA_CONFIG_FILE.write_text(config, encoding="utf-8")


def cleanup_cava_files() -> None:
    for path in (CAVA_CONFIG_FILE, CAVA_FIFO_FILE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def parse_frame(line: str) -> list[int]:
    values: list[int] = []
    for chunk in line.strip().split(";"):
        if not chunk:
            continue
        try:
            values.append(int(chunk))
        except ValueError:
            return []
    return values


def run_popup() -> int:
    import gi

    gi.require_version("Gdk", "3.0")
    gi.require_version("Gtk", "3.0")
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

    metadata = get_sink_metadata()
    volume, muted = get_volume_info()
    status = {
        "name": metadata["name"],
        "source": metadata["source"],
        "volume": volume,
        "muted": muted,
        "values": [0.0] * BAR_COUNT,
        "display_values": [0.0] * BAR_COUNT,
    }

    window_width = 286
    window_height = 128
    left, top = get_popup_geometry(window_width, window_height)

    css = b"""
window#volume-popup {
  background: rgba(7, 4, 14, 0.98);
  border: 1px solid rgba(185, 121, 255, 0.34);
  border-radius: 14px;
}
#volume-popup-box {
  padding: 10px 12px 12px 12px;
}
#volume-popup-title {
  color: #d5c4ee;
  font-size: 11px;
  font-weight: 700;
}
#volume-popup-value {
  color: #f4ebff;
  font-size: 18px;
}
#volume-popup-subtitle {
  color: #9b86ba;
  font-size: 10px;
}
#volume-popup-viz {
  min-height: 74px;
}
"""

    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.set_name("volume-popup")
    window.set_default_size(window_width, window_height)
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
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, top)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.LEFT, left)

    display = Gdk.Display.get_default()
    if display is not None and hasattr(display, "get_monitor_at_point"):
        monitor = display.get_monitor_at_point(left, top)
        if monitor is not None:
            GtkLayerShell.set_monitor(window, monitor)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
    box.set_name("volume-popup-box")

    header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    header_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
    title_label = Gtk.Label()
    title_label.set_name("volume-popup-title")
    title_label.set_xalign(0.0)
    title_label.set_ellipsize(3)
    title_label.set_max_width_chars(24)

    subtitle_label = Gtk.Label()
    subtitle_label.set_name("volume-popup-subtitle")
    subtitle_label.set_xalign(0.0)

    value_label = Gtk.Label()
    value_label.set_name("volume-popup-value")
    value_label.set_use_markup(True)
    value_label.set_xalign(1.0)

    spectrum_area = Gtk.DrawingArea()
    spectrum_area.set_name("volume-popup-viz")
    spectrum_area.set_size_request(-1, 74)

    header_text.pack_start(title_label, False, False, 0)
    header_text.pack_start(subtitle_label, False, False, 0)
    header.pack_start(header_text, True, True, 0)
    header.pack_end(value_label, False, False, 0)
    box.pack_start(header, False, False, 0)
    box.pack_start(spectrum_area, True, True, 0)
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

    cava_stop = threading.Event()
    cava_proc: subprocess.Popen[str] | None = None

    def apply_popup_position() -> bool:
        width = window.get_allocated_width() or window_width
        height = window.get_allocated_height() or window_height
        left, top = get_popup_geometry(width, height)
        GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, top)
        GtkLayerShell.set_margin(window, GtkLayerShell.Edge.LEFT, left)

        display = Gdk.Display.get_default()
        if display is not None and hasattr(display, "get_monitor_at_point"):
            monitor = display.get_monitor_at_point(left, top)
            if monitor is not None:
                GtkLayerShell.set_monitor(window, monitor)
        return False

    def redraw() -> None:
        title_label.set_text(status["name"])
        subtitle_label.set_text("monitor")
        value_text = "Muted" if status["muted"] else f"{status['volume']}%"
        value_color = MUTED if status["muted"] else HEADER
        value_label.set_markup(span(value_text, foreground=value_color, weight="700"))
        spectrum_area.queue_draw()

    def refresh_status() -> bool:
        current_volume, current_muted = get_volume_info()
        status["volume"] = current_volume
        status["muted"] = current_muted
        redraw()
        return True

    def update_spectrum(values: list[int]) -> bool:
        normalized = [max(0.0, min(float(value) / CAVA_RANGE, 1.0)) for value in values[:BAR_COUNT]]
        status["values"] = normalized + [0.0] * (BAR_COUNT - len(normalized))
        return False

    def animate_spectrum() -> bool:
        changed = False
        for index, target in enumerate(status["values"]):
            current = status["display_values"][index]
            step = (target - current) * 0.38
            if abs(step) < 0.003:
                next_value = target
            else:
                next_value = current + step
            if abs(next_value - current) > 0.001:
                changed = True
            status["display_values"][index] = next_value
        if changed:
            spectrum_area.queue_draw()
        return True

    def draw_spectrum(_widget, cr) -> bool:
        width = float(spectrum_area.get_allocated_width())
        height = float(spectrum_area.get_allocated_height())
        if width <= 0 or height <= 0:
            return False

        bar_gap = 4.0
        bar_width = (width - (BAR_COUNT - 1) * bar_gap) / BAR_COUNT
        radius = min(3.5, bar_width / 2)
        muted = bool(status["muted"])

        ghost_color = hex_to_rgba("#ffffff", 0.05 if not muted else 0.03)
        low_color = hex_to_rgba("#8a57dd", 0.95 if not muted else 0.35)
        high_color = hex_to_rgba("#e2b5ff", 0.98 if not muted else 0.45)

        for index, value in enumerate(status["display_values"]):
            x = index * (bar_width + bar_gap)
            rounded_rectangle(cr, x, 0, bar_width, height, radius)
            cr.set_source_rgba(*ghost_color)
            cr.fill()

            fill_height = max(6.0, height * value)
            y = height - fill_height
            import cairo

            pattern = cairo.LinearGradient(0, y, 0, height)
            pattern.add_color_stop_rgba(0.0, *high_color)
            pattern.add_color_stop_rgba(1.0, *low_color)
            rounded_rectangle(cr, x, y, bar_width, fill_height, radius)
            cr.set_source(pattern)
            cr.fill()

        return False

    def read_cava() -> None:
        nonlocal cava_proc
        write_cava_config(str(status["source"]))

        try:
            cava_proc = subprocess.Popen(
                ["cava", "-p", str(CAVA_CONFIG_FILE)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
            )
        except OSError:
            return

        deadline = time.monotonic() + 3
        while (
            not cava_stop.is_set()
            and not CAVA_FIFO_FILE.exists()
            and cava_proc.poll() is None
            and time.monotonic() < deadline
        ):
            time.sleep(0.05)

        if cava_stop.is_set() or not CAVA_FIFO_FILE.exists():
            return

        try:
            with CAVA_FIFO_FILE.open("r", encoding="utf-8", errors="ignore") as fifo:
                for line in fifo:
                    if cava_stop.is_set():
                        break
                    values = parse_frame(line)
                    if values:
                        GLib.idle_add(update_spectrum, values)
        except OSError:
            pass

    def shutdown(*_args) -> None:
        cava_stop.set()
        if cava_proc is not None and cava_proc.poll() is None:
            cava_proc.terminate()
            try:
                cava_proc.wait(timeout=0.3)
            except subprocess.TimeoutExpired:
                cava_proc.kill()
        cleanup_cava_files()
        clear_popup_pid()
        Gtk.main_quit()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    POPUP_PID_FILE.write_text(str(os.getpid()), encoding="utf-8")

    redraw()
    GLib.timeout_add(120, refresh_status)
    GLib.timeout_add(16, animate_spectrum)
    threading.Thread(target=read_cava, daemon=True).start()
    spectrum_area.connect("draw", draw_spectrum)
    window.connect("destroy", shutdown)
    window.show_all()
    GLib.idle_add(apply_popup_position)
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
        cleanup_cava_files()
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
    if action == "toggle-popup":
        return toggle_popup()
    if action == "popup":
        return run_popup()
    return 1


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "status":
        return print_status()
    return handle_action(action)


if __name__ == "__main__":
    raise SystemExit(main())
