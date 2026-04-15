#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore[no-redef]


HOME = Path.home()
XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
XDG_CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME") or (HOME / ".cache"))

CONFIG_PATH = HOME / ".config" / "voice-assistant" / "config.toml"
API_KEY_PATH = HOME / ".config" / "voice-assistant" / "openai-api-key"
WHISPER_CPP_DIR = HOME / ".local" / "share" / "whisper.cpp"
WHISPER_CPP_BIN = WHISPER_CPP_DIR / "build" / "bin" / "whisper-cli"
WHISPER_MODEL_PATH = WHISPER_CPP_DIR / "models" / "ggml-large-v3-turbo-q5_0.bin"
STATE_DIR = XDG_RUNTIME_DIR / "voice-assistant"
CACHE_DIR = XDG_CACHE_HOME / "voice-assistant"
PID_FILE = STATE_DIR / "recording.pid"
AUDIO_FILE = CACHE_DIR / "last-input.wav"
TRANSCRIPT_FILE = CACHE_DIR / "last-transcript.txt"
WHISPER_OUTPUT_BASE = CACHE_DIR / "last-whisper-output"
LOG_FILE = CACHE_DIR / "last-codex-output.log"
LAST_MESSAGE_FILE = CACHE_DIR / "last-assistant-message.txt"
SESSION_FILE = CACHE_DIR / "codex-session.txt"
CODEX_WINDOW_TITLE = "Voice Codex"


@dataclass
class Config:
    stt_backend: str = "whispercpp"
    stt_model: str = "gpt-4o-mini-transcribe"
    stt_local_model_path: str = str(WHISPER_MODEL_PATH)
    stt_language: str = "ru"
    stt_prompt: str = (
        "Russian desktop voice commands about Hyprland, Waybar, Wofi, Codex, "
        "Firefox, Discord, Steam, Obsidian, calendar, locking the screen, and volume."
    )
    stt_threads: int = max(1, os.cpu_count() or 4)
    record_input: str = "default"
    record_sample_rate: int = 16000
    record_max_seconds: int = 30
    cache_max_age_seconds: int = 3600
    route_local_actions: bool = False
    terminal: str = "kitty"
    codex_workdir: str = str(HOME)
    codex_model: str = "gpt-5.4"
    codex_sandbox: str = "workspace-write"
    notify: bool = True


@dataclass
class LocalAction:
    label: str
    command: list[str]
    message: str


def ensure_dirs() -> None:
    global STATE_DIR, PID_FILE

    preferred_dirs = [
        STATE_DIR,
        Path("/tmp") / f"voice-assistant-{os.getuid()}",
    ]

    for candidate in preferred_dirs:
        try:
            candidate.mkdir(parents=True, exist_ok=True)
        except OSError:
            continue
        STATE_DIR = candidate
        PID_FILE = STATE_DIR / "recording.pid"
        break
    else:  # pragma: no cover
        raise RuntimeError("Could not create a writable runtime directory for voice assistant state.")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)


def load_config() -> Config:
    config = Config()
    if not CONFIG_PATH.exists():
        return config

    payload = tomllib.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    for field in config.__dataclass_fields__:
        if field in payload:
            setattr(config, field, payload[field])
    return config


def notify(config: Config, title: str, body: str = "") -> None:
    if not config.notify:
        return
    if not shutil_which("notify-send"):
        return

    command = ["notify-send", title]
    if body:
        command.append(body)
    subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        close_fds=True,
        start_new_session=True,
    )


def shutil_which(command: str) -> str | None:
    return subprocess.run(
        ["bash", "-lc", f"command -v {command}"],
        check=False,
        capture_output=True,
        text=True,
    ).stdout.strip() or None


def read_pid() -> int | None:
    try:
        return int(PID_FILE.read_text(encoding="utf-8").strip())
    except (FileNotFoundError, OSError, ValueError):
        return None


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def write_pid(pid: int) -> None:
    ensure_dirs()
    PID_FILE.write_text(str(pid), encoding="utf-8")


def clear_pid() -> None:
    try:
        PID_FILE.unlink()
    except OSError:
        pass


def prune_cache(config: Config) -> None:
    max_age = max(60, int(config.cache_max_age_seconds))
    cutoff = time.time() - max_age
    patterns = (
        "*.wav",
        "*.txt",
        "*.json",
        "*.log",
    )
    for pattern in patterns:
        for path in CACHE_DIR.glob(pattern):
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink()
            except FileNotFoundError:
                continue


def finalize_recording(config: Config) -> int:
    if not AUDIO_FILE.exists() or AUDIO_FILE.stat().st_size < 4096:
        notify(config, "Voice Assistant", "Recording was too short.")
        return 1

    try:
        transcript = transcribe_audio(config, AUDIO_FILE)
    except Exception as exc:  # pragma: no cover
        notify(config, "Voice Assistant", transcribe_error_message(exc))
        return 1

    transcript = transcript.strip()
    if not transcript:
        notify(config, "Voice Assistant", "Nothing was recognized.")
        return 1

    TRANSCRIPT_FILE.write_text(transcript, encoding="utf-8")
    notify(config, "Voice Assistant", transcript[:180])

    if config.route_local_actions:
        action = resolve_local_action(transcript)
        if action is not None:
            run_local_action(config, action)
            return 0

    launch_codex_window(config, TRANSCRIPT_FILE)
    return 0


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s%+-]", " ", text.lower(), flags=re.UNICODE)).strip()


def openai_api_key() -> str:
    env_key = os.environ.get("OPENAI_API_KEY", "")
    key = env_key.strip() if isinstance(env_key, str) else ""
    if key:
        return key

    if API_KEY_PATH.exists():
        key = API_KEY_PATH.read_text(encoding="utf-8").strip()
        if key:
            return key

    auth_path = HOME / ".codex" / "auth.json"
    if not auth_path.exists():
        raise RuntimeError("OPENAI_API_KEY is not set and ~/.codex/auth.json was not found.")

    payload = json.loads(auth_path.read_text(encoding="utf-8"))
    raw_key = payload.get("OPENAI_API_KEY", "")
    key = raw_key.strip() if isinstance(raw_key, str) else ""
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not configured. Codex login tokens are present, "
            "but speech-to-text needs a real OpenAI API key."
        )
    return key


def transcribe_error_message(exc: Exception) -> str:
    if isinstance(exc, subprocess.CalledProcessError):
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        if stderr and stdout:
            details = f"{stderr}\n{stdout}"
        else:
            details = stderr or stdout or str(exc)
        return f"Speech-to-text request failed: {details}"
    return str(exc)


def start_recording(config: Config) -> int:
    ensure_dirs()
    prune_cache(config)

    pid = read_pid()
    if pid and process_alive(pid):
        notify(config, "Voice Assistant", "Recording is already running.")
        return 0

    clear_pid()
    for path in (AUDIO_FILE, TRANSCRIPT_FILE, LOG_FILE, LAST_MESSAGE_FILE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    command = [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-f",
        "pulse",
        "-i",
        config.record_input,
        "-t",
        str(max(1, int(config.record_max_seconds))),
        "-ac",
        "1",
        "-ar",
        str(config.record_sample_rate),
        str(AUDIO_FILE),
    ]

    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    write_pid(process.pid)
    notify(config, "Voice Assistant", "Listening. Speak now and press the hotkey again to stop.")
    return 0


def toggle_recording(config: Config) -> int:
    pid = read_pid()
    if pid and process_alive(pid):
        return stop_recording(config)

    clear_pid()
    return start_recording(config)


def stop_recording(config: Config) -> int:
    pid = read_pid()
    if not pid:
        clear_pid()
        notify(config, "Voice Assistant", "No active recording was found.")
        return 1

    if not process_alive(pid):
        clear_pid()
        return finalize_recording(config)

    try:
        os.killpg(pid, signal.SIGINT)
    except OSError:
        try:
            os.kill(pid, signal.SIGINT)
        except OSError:
            pass

    deadline = time.monotonic() + 3
    while process_alive(pid) and time.monotonic() < deadline:
        time.sleep(0.05)

    if process_alive(pid):
        try:
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass

    clear_pid()
    return finalize_recording(config)


def transcribe_audio(config: Config, audio_path: Path) -> str:
    backend = config.stt_backend.lower().strip()
    if backend in {"openai", "openai-api"}:
        return transcribe_audio_openai(config, audio_path)
    if backend in {"whispercpp", "whisper.cpp", "local"}:
        return transcribe_audio_whisper_cpp(config, audio_path)
    raise RuntimeError(f"Unsupported STT backend: {config.stt_backend}")


def transcribe_audio_openai(config: Config, audio_path: Path) -> str:

    api_key = openai_api_key()
    command = [
        "curl",
        "--silent",
        "--show-error",
        "--fail-with-body",
        "https://api.openai.com/v1/audio/transcriptions",
        "-H",
        f"Authorization: Bearer {api_key}",
        "-F",
        f"file=@{audio_path}",
        "-F",
        f"model={config.stt_model}",
        "-F",
        "response_format=json",
    ]

    if config.stt_language:
        command.extend(["-F", f"language={config.stt_language}"])
    if config.stt_prompt:
        command.extend(["-F", f"prompt={config.stt_prompt}"])

    result = subprocess.run(command, check=True, capture_output=True, text=True)
    body = result.stdout.strip()
    if not body:
        return ""

    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return body

    if isinstance(payload, dict):
        return str(payload.get("text", "")).strip()
    return ""


def whisper_cpp_binary() -> Path:
    if WHISPER_CPP_BIN.exists():
        return WHISPER_CPP_BIN

    in_path = shutil_which("whisper-cli")
    if in_path:
        return Path(in_path)

    raise RuntimeError(f"whisper-cli was not found. Expected it at {WHISPER_CPP_BIN} or in PATH.")


def transcribe_audio_whisper_cpp(config: Config, audio_path: Path) -> str:
    binary = whisper_cpp_binary()
    model_path = Path(config.stt_local_model_path).expanduser()
    if not model_path.exists():
        raise RuntimeError(f"Whisper model is missing: {model_path}")

    output_txt = WHISPER_OUTPUT_BASE.with_suffix(".txt")
    try:
        output_txt.unlink()
    except FileNotFoundError:
        pass

    language = config.stt_language.strip() if config.stt_language else "auto"
    command = [
        str(binary),
        "--no-gpu",
        "--threads",
        str(max(1, int(config.stt_threads))),
        "--language",
        language or "auto",
        "--model",
        str(model_path),
        "--file",
        str(audio_path),
        "--output-file",
        str(WHISPER_OUTPUT_BASE),
        "--output-txt",
        "--no-timestamps",
        "--no-prints",
    ]

    if config.stt_prompt:
        command.extend(["--prompt", config.stt_prompt])

    result = subprocess.run(command, check=True, capture_output=True, text=True)
    if output_txt.exists():
        return output_txt.read_text(encoding="utf-8").strip()

    stdout = result.stdout.strip()
    if stdout:
        return stdout

    stderr = result.stderr.strip()
    if stderr:
        raise RuntimeError(f"whisper.cpp returned no transcript. {stderr}")
    return ""


def command_exists(command: str) -> bool:
    return shutil_which(command) is not None


def extract_percent(text: str, fallback: int = 10) -> int:
    match = re.search(r"(\d{1,3})", text)
    if not match:
        return fallback
    value = int(match.group(1))
    return max(1, min(value, 200))


def contains_any(text: str, variants: tuple[str, ...]) -> bool:
    return any(variant in text for variant in variants)


def wants_open(text: str) -> bool:
    verbs = (
        "open",
        "launch",
        "run",
        "show",
        "start",
        "открой",
        "запусти",
        "покажи",
        "зайди",
    )
    return contains_any(text, verbs)


def app_action(text: str, aliases: tuple[str, ...], label: str, command: list[str], message: str) -> LocalAction | None:
    if not contains_any(text, aliases):
        return None

    compact = text.replace(" ", "")
    if wants_open(text) or text in aliases or compact in aliases or len(text.split()) <= 3:
        return LocalAction(label=label, command=command, message=message)
    return None


def resolve_local_action(transcript: str) -> LocalAction | None:
    text = normalize_text(transcript)
    if not text:
        return None

    action = app_action(
        text,
        ("discord", "дискорд"),
        "discord",
        ["discord"],
        "Opening Discord.",
    )
    if action:
        return action

    action = app_action(
        text,
        ("steam", "стим"),
        "steam",
        ["steam"],
        "Opening Steam.",
    )
    if action:
        return action

    action = app_action(
        text,
        ("obsidian", "обсидиан"),
        "obsidian",
        ["obsidian"],
        "Opening Obsidian.",
    )
    if action:
        return action

    action = app_action(
        text,
        ("firefox", "браузер", "browser", "фаерфокс"),
        "firefox",
        ["firefox"],
        "Opening Firefox.",
    )
    if action:
        return action

    action = app_action(
        text,
        ("terminal", "терминал", "kitty"),
        "terminal",
        ["kitty"],
        "Opening terminal.",
    )
    if action:
        return action

    action = app_action(
        text,
        ("thunar", "files", "file manager", "проводник", "файловый менеджер"),
        "thunar",
        ["thunar"],
        "Opening file manager.",
    )
    if action:
        return action

    if contains_any(text, ("calendar", "календар", "дата")) and contains_any(text, ("show", "open", "покажи", "открой")):
        return LocalAction(
            label="calendar",
            command=[str(HOME / ".local" / "bin" / "waybar-calendar-toggle")],
            message="Opening calendar popup.",
        )

    if contains_any(text, ("launcher", "menu", "wofi", "меню", "лаунчер")) and contains_any(text, ("show", "open", "покажи", "открой")):
        return LocalAction(
            label="launcher",
            command=[str(HOME / ".config" / "waybar" / "scripts" / "menu-toggle.sh")],
            message="Opening launcher.",
        )

    if contains_any(text, ("lock", "lock screen", "заблокируй", "заблокировать", "экран")) and contains_any(
        text, ("lock", "заблок", "screen", "экран")
    ):
        return LocalAction(
            label="lock",
            command=["hyprlock"],
            message="Locking the screen.",
        )

    if contains_any(text, ("mute", "выключи звук", "без звука", "mute volume", "замьюти", "заглуши")):
        return LocalAction(
            label="mute",
            command=["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"],
            message="Muting audio.",
        )

    if contains_any(text, ("unmute", "включи звук", "верни звук", "размьюти")):
        return LocalAction(
            label="unmute",
            command=["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"],
            message="Unmuting audio.",
        )

    if contains_any(text, ("volume", "громкость")) and re.search(r"\b\d{1,3}\b", text):
        absolute_markers = ("set", "make", "на", "to", "до", "сделай", "поставь")
        if contains_any(text, absolute_markers):
            level = extract_percent(text, fallback=50)
            return LocalAction(
                label="volume-set",
                command=["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{level}%"],
                message=f"Setting volume to {level}%.",
            )

    if contains_any(text, ("louder", "volume up", "громче", "повысь", "увеличь громкость", "добавь громкость")):
        step = extract_percent(text, fallback=10)
        return LocalAction(
            label="volume-up",
            command=["wpctl", "set-volume", "-l", "2.0", "@DEFAULT_AUDIO_SINK@", f"{step}%+"],
            message=f"Raising volume by {step}%.",
        )

    if contains_any(text, ("quieter", "volume down", "тише", "убавь громкость", "уменьши громкость", "сделай тише")):
        step = extract_percent(text, fallback=10)
        return LocalAction(
            label="volume-down",
            command=["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{step}%-"],
            message=f"Lowering volume by {step}%.",
        )

    return None


def run_local_action(config: Config, action: LocalAction) -> None:
    if not command_exists(action.command[0]) and not Path(action.command[0]).exists():
        notify(config, "Voice Assistant", f"Command is missing for action: {action.label}")
        return

    subprocess.Popen(
        action.command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    notify(config, "Voice Assistant", action.message)


def codex_prompt(transcript: str) -> str:
    return (
        "You are Codex answering a voice-transcribed prompt from the owner of a Linux desktop. "
        "Reply in Russian. Be concise by default. If the speech-to-text seems imperfect, infer the most likely "
        "meaning and mention your assumption briefly. You may use tools available in the current Codex session "
        "under the active sandbox policy.\n\n"
        f"Voice transcript:\n{transcript}"
    )


def launch_codex_window(config: Config, transcript_path: Path) -> None:
    script_path = Path(__file__).resolve()
    command = [
        config.terminal,
        "--title",
        CODEX_WINDOW_TITLE,
        sys.executable,
        str(script_path),
        "codex-window",
        "--transcript-file",
        str(transcript_path),
    ]
    subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    notify(config, "Voice Assistant", "Forwarding the request to Codex.")


def run_codex_window(config: Config, transcript_path: Path) -> int:
    transcript = transcript_path.read_text(encoding="utf-8").strip()
    if not transcript:
        print("Transcript is empty.", file=sys.stderr)
        return 1

    print(f"Voice transcript:\n{transcript}\n")
    print("Running Codex voice bridge...\n")
    sys.stdout.flush()

    prompt = codex_prompt(transcript)
    command = [
        "codex",
        "-C",
        config.codex_workdir,
        "-s",
        config.codex_sandbox,
        "exec",
        "--skip-git-repo-check",
        "--output-last-message",
        str(LAST_MESSAGE_FILE),
    ]

    session_id = load_session_id()
    if session_id:
        command.extend(["resume", session_id, prompt])
    else:
        command.extend(["-m", config.codex_model, prompt])

    with LOG_FILE.open("w", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="")
            log_handle.write(line)
            log_handle.flush()
            session_match = re.search(r"session id:\s*([0-9a-f-]{36})", line, flags=re.IGNORECASE)
            if session_match:
                SESSION_FILE.write_text(session_match.group(1), encoding="utf-8")

        code = process.wait()

    assistant_message = ""
    try:
        assistant_message = LAST_MESSAGE_FILE.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        assistant_message = ""

    if assistant_message:
        notify(config, "Voice Assistant", assistant_message[:220])
    elif code != 0:
        notify(config, "Voice Assistant", "Codex request failed. See the terminal output.")

    return code


def load_session_id() -> str | None:
    try:
        value = SESSION_FILE.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    return value or None


def debug_intent(transcript: str) -> int:
    action = resolve_local_action(transcript)
    if action is None:
        print("no-match")
        return 1
    print(json.dumps({"label": action.label, "command": action.command, "message": action.message}, ensure_ascii=False))
    return 0


def transcribe_file(config: Config, audio_path: Path) -> int:
    try:
        print(transcribe_audio(config, audio_path))
        return 0
    except Exception as exc:
        print(transcribe_error_message(exc), file=sys.stderr)
        return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="voice-assistant")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("start-recording")
    subparsers.add_parser("stop-recording")
    subparsers.add_parser("toggle-recording")

    codex_parser = subparsers.add_parser("codex-window")
    codex_parser.add_argument("--transcript-file", required=True, type=Path)

    debug_parser = subparsers.add_parser("debug-intent")
    debug_parser.add_argument("transcript")

    transcribe_parser = subparsers.add_parser("transcribe-file")
    transcribe_parser.add_argument("audio_file", type=Path)

    return parser


def main() -> int:
    ensure_dirs()
    config = load_config()
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "start-recording":
        return start_recording(config)
    if args.command == "stop-recording":
        return stop_recording(config)
    if args.command == "toggle-recording":
        return toggle_recording(config)
    if args.command == "codex-window":
        return run_codex_window(config, args.transcript_file)
    if args.command == "debug-intent":
        return debug_intent(args.transcript)
    if args.command == "transcribe-file":
        return transcribe_file(config, args.audio_file)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
