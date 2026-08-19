#!/usr/bin/env python3
"""Generate short theme-tinted UI clicks for gobijan.ui-sounds."""

from __future__ import annotations

import json
import math
import struct
import sys
import wave
from pathlib import Path

HOME = Path.home()
DEFAULT_DIR = HOME / ".config/omarchy/sounds/default"
GENERATED_DIR = HOME / ".config/omarchy/sounds/generated"
USER_THEMES = HOME / ".config/omarchy/themes"
CURRENT_THEME_DIR = HOME / ".local/state/omarchy/current/theme"
CURRENT_THEME_NAME = HOME / ".local/state/omarchy/current/theme.name"

SAMPLE_RATE = 44100
SOUND_EXTS = (".wav", ".ogg", ".oga", ".mp3", ".flac", ".opus")
EVENTS = (
    "openwindow",
    "closewindow",
    "workspace",
    "fullscreen",
    "unfullscreen",
    "float",
    "unfloat",
    "minimize",
    "urgent",
    "bell",
)


def current_theme() -> str:
    if CURRENT_THEME_NAME.is_file():
        name = CURRENT_THEME_NAME.read_text(encoding="utf-8").strip()
        if name:
            return name
    return "default"


def parse_kv_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def hex_to_rgb(value: str) -> tuple[int, int, int] | None:
    value = value.strip().lstrip("#")
    if len(value) == 3:
        value = "".join(ch * 2 for ch in value)
    if len(value) != 6:
        return None
    try:
        return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)
    except ValueError:
        return None


def rgb_to_hsl(r: int, g: int, b: int) -> tuple[float, float, float]:
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    high, low = max(rf, gf, bf), min(rf, gf, bf)
    light = (high + low) / 2.0
    delta = high - low
    if delta == 0:
        return 0.0, 0.0, light
    sat = delta / (1 - abs(2 * light - 1))
    if high == rf:
        hue = ((gf - bf) / delta) % 6
    elif high == gf:
        hue = (bf - rf) / delta + 2
    else:
        hue = (rf - gf) / delta + 4
    return hue * 60.0, sat, light


class Palette:
    def __init__(self, name: str, base_hz: float, brightness: float, richness: float, dark: bool):
        self.name = name
        self.base_hz = base_hz
        self.brightness = brightness
        self.richness = richness
        self.dark = dark


def palette_from_theme(theme: str) -> Palette:
    colors = parse_kv_file(CURRENT_THEME_DIR / "colors.toml")
    overlay = USER_THEMES / theme / "colors.toml"
    if overlay.is_file():
        colors.update(parse_kv_file(overlay))

    accent = hex_to_rgb(colors.get("accent", "#7aa2f7")) or (122, 162, 247)
    background = hex_to_rgb(colors.get("background", "#1a1b26")) or (26, 27, 38)
    hue, sat, _ = rgb_to_hsl(*accent)
    _, _, bg_light = rgb_to_hsl(*background)
    dark = colors.get("mode", "dark").lower() != "light" and bg_light < 0.5
    base_hz = 360.0 + (hue / 360.0) * 340.0
    if dark:
        base_hz *= 0.92
    brightness = 0.72 if dark else 1.0
    brightness *= 0.85 + 0.3 * (1.0 - bg_light if dark else bg_light)
    richness = 0.18 + sat * 0.55
    return Palette(theme, base_hz, brightness, richness, dark)


def default_palette() -> Palette:
    return Palette("default", 520.0, 0.85, 0.28, True)


def envelope(index: int, total: int, sample_rate: int, decay: float) -> float:
    attack = min(1.0, index / max(1, int(sample_rate * 0.003)))
    t = index / sample_rate
    return attack * math.exp(-t * decay)


def render_tone(
    freq: float,
    duration: float,
    volume: float,
    richness: float,
    decay: float,
    noise: float = 0.0,
) -> list[float]:
    n = max(1, int(SAMPLE_RATE * duration))
    samples = [0.0] * n
    harmonics = ((1.0, 1.0), (2.0, 0.18 * richness), (3.0, 0.05 * richness))
    noise_len = int(SAMPLE_RATE * 0.008)
    for i in range(n):
        t = i / SAMPLE_RATE
        env = envelope(i, n, SAMPLE_RATE, decay)
        tone = 0.0
        for mul, amp in harmonics:
            if amp > 0:
                tone += amp * math.sin(2.0 * math.pi * freq * mul * t)
        click = 0.0
        if noise and i < noise_len:
            click = noise * (((i * 1103515245 + 12345) & 0x7FFFFFFF) / 0x7FFFFFFF - 0.5)
            click *= envelope(i, noise_len, SAMPLE_RATE, 90.0)
        samples[i] = (tone + click) * env * volume
    return samples


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max((abs(s) for s in samples), default=0.0)
    norm = 0.88 / peak if peak > 0.88 else 1.0
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            value = max(-1.0, min(1.0, sample * norm))
            frames.extend(struct.pack("<h", int(value * 32767)))
        wav.writeframes(frames)


def recipes(palette: Palette) -> dict[str, list[float]]:
    base = palette.base_hz
    vol = 0.24 * palette.brightness
    rich = palette.richness
    decay = 32.0 if palette.dark else 40.0
    return {
        "openwindow": render_tone(base * 1.18, 0.055, vol, rich, decay, 0.26),
        "closewindow": render_tone(base * 0.86, 0.05, vol * 0.85, rich, decay + 4, 0.2),
        "workspace": render_tone(base * 1.48, 0.038, vol * 0.62, rich * 0.55, decay + 8, 0.22),
        "fullscreen": render_tone(base * 1.32, 0.06, vol * 0.9, rich, decay, 0.16),
        "unfullscreen": render_tone(base * 0.94, 0.05, vol * 0.78, rich, decay + 2, 0.14),
        "float": render_tone(base * 1.68, 0.042, vol * 0.7, rich, decay + 4, 0.2),
        "unfloat": render_tone(base * 1.12, 0.04, vol * 0.66, rich, decay + 4, 0.14),
        "minimize": render_tone(base * 0.72, 0.048, vol * 0.72, rich * 0.7, decay + 6, 0.14),
        "urgent": render_tone(base * 1.82, 0.06, vol * 0.75, min(1.0, rich + 0.15), decay, 0.24),
        "bell": render_tone(base * 1.95, 0.065, vol * 0.68, rich, decay + 2, 0.18),
    }


def generate_pack(theme: str, force: bool = False) -> Path:
    if theme in {"", "default"}:
        dest = DEFAULT_DIR
        palette = default_palette()
    else:
        dest = GENERATED_DIR / theme
        palette = palette_from_theme(theme)
    dest.mkdir(parents=True, exist_ok=True)
    for event, samples in recipes(palette).items():
        path = dest / f"{event}.wav"
        if path.exists() and not force:
            continue
        write_wav(path, samples)
    return dest


def resolve_sound(event: str, theme: str) -> str:
    search = [
        USER_THEMES / theme / "sounds",
        CURRENT_THEME_DIR / "sounds",
        GENERATED_DIR / theme,
        DEFAULT_DIR,
    ]
    for directory in search:
        for ext in SOUND_EXTS:
            path = directory / f"{event}{ext}"
            if path.is_file():
                return str(path)
    return ""


def resolve_all(theme: str) -> dict[str, str]:
    return {event: resolve_sound(event, theme) for event in EVENTS}


def main(argv: list[str]) -> int:
    force = "--force" in argv
    args = [a for a in argv if not a.startswith("-")]
    command = args[0] if args and args[0] in {"generate", "list"} else "generate"
    theme = next((a for a in args if a not in {"generate", "list"}), current_theme())

    if command != "list":
        generate_pack("default", force=force)
        generate_pack(theme, force=force)

    print(json.dumps(resolve_all(theme), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
