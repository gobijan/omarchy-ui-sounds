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
PLUGIN_DIR = Path(__file__).resolve().parent
DEFAULT_DIR = HOME / ".config/omarchy/sounds/default"
GENERATED_DIR = HOME / ".config/omarchy/sounds/generated"
USER_THEMES = HOME / ".config/omarchy/themes"
USER_PACKS = HOME / ".config/omarchy/sounds/packs"
PLUGIN_PACKS = PLUGIN_DIR / "packs"
CURRENT_THEME_DIR = HOME / ".local/state/omarchy/current/theme"
CURRENT_THEME_NAME = HOME / ".local/state/omarchy/current/theme.name"
SYSTEM_THEMES = Path("/usr/share/omarchy/themes")
CATALOG_PATH = HOME / ".config/omarchy/sounds/catalog.json"
LOFI_RATE = 11025

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

PACK_SUMMARIES = {
    "theme": "Follow the active Omarchy theme palette",
    "quake": "LibreQuake menu and item remakes",
    "90sfps": "Synthesized 90s-FPS homage",
    "kenney": "Clean modern UI clicks",
    "digital": "Arcade lasers and power-ups",
    "chip": "8-bit menu blips",
    "scifi": "Airlock doors, lasers, force fields",
}

EVENT_SUMMARIES = {
    "openwindow": "A window opens",
    "closewindow": "A window closes",
    "workspace": "Workspace switch",
    "fullscreen": "A window enters fullscreen",
    "unfullscreen": "A window leaves fullscreen",
    "float": "A window is floated",
    "unfloat": "A window is tiled",
    "minimize": "A window is minimized",
    "urgent": "A window requests attention",
    "bell": "An app rings the system bell",
}

USAGE = """\
Usage: generate.py [<command>] [--pack NAME] [--force] [theme]

Commands:
  generate   Write samples and print resolved paths (default)
  list       Print resolved paths without writing
  packs      Print available pack names as JSON
  info       Print packs, themes, and events as JSON
  help       Show this help

Pack names: theme, quake, 90sfps, kenney, digital, chip, scifi
"""


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


def _noise(index: int, seed: int) -> float:
    return ((index * 1103515245 + seed) & 0x7FFFFFFF) / 0x7FFFFFFF * 2.0 - 1.0


def _one_pole(samples: list[float], cutoff: float, rate: int) -> list[float]:
    coeff = 1.0 - math.exp(-2.0 * math.pi * cutoff / rate)
    out: list[float] = []
    acc = 0.0
    for sample in samples:
        acc += coeff * (sample - acc)
        out.append(acc)
    return out


def _bitcrush(samples: list[float], bits: int = 8) -> list[float]:
    levels = float(1 << (bits - 1))
    return [round(sample * levels) / levels for sample in samples]


def _upsample(samples: list[float], factor: int) -> list[float]:
    out: list[float] = []
    for sample in samples:
        out.extend([sample] * factor)
    return out


def _mix(base: list[float], extra: list[float], offset: int) -> list[float]:
    needed = offset + len(extra)
    if needed > len(base):
        base.extend([0.0] * (needed - len(base)))
    for i, sample in enumerate(extra):
        base[offset + i] += sample
    return base


def _square(t: float, freq: float, duty: float = 0.5) -> float:
    return 1.0 if (t * freq) % 1.0 < duty else -1.0


def _quake_tone(freq: float, duration: float, volume: float, decay: float, duty: float = 0.42) -> list[float]:
    n = max(1, int(LOFI_RATE * duration))
    samples = [0.0] * n
    for i in range(n):
        t = i / LOFI_RATE
        env = min(1.0, i / max(1, int(LOFI_RATE * 0.002))) * math.exp(-t * decay)
        tone = 0.72 * _square(t, freq, duty) + 0.28 * math.sin(2.0 * math.pi * freq * t)
        samples[i] = math.tanh(tone * 1.35) * env * volume
    return samples


def _quake_noise(duration: float, volume: float, cutoff: float, seed: int) -> list[float]:
    n = max(1, int(LOFI_RATE * duration))
    raw = [_noise(i, seed) * volume * math.exp(-i / LOFI_RATE * 28.0) for i in range(n)]
    return _one_pole(raw, cutoff, LOFI_RATE)


def _quake_finish(samples: list[float]) -> list[float]:
    crushed = _bitcrush(samples, 8)
    return _upsample(crushed, SAMPLE_RATE // LOFI_RATE)


def quake_recipes() -> dict[str, list[float]]:
    # Original homage, not ripped Quake samples: 11kHz, 8-bit, metallic/digital.
    openwindow = _quake_tone(620, 0.04, 0.28, 26.0)
    _mix(openwindow, _quake_tone(930, 0.055, 0.3, 22.0), int(LOFI_RATE * 0.032))
    _mix(openwindow, _quake_noise(0.018, 0.18, 2800, 17), 0)

    closewindow = _quake_tone(78, 0.07, 0.42, 18.0, duty=0.5)
    _mix(closewindow, _quake_noise(0.07, 0.34, 420, 91), 0)
    _mix(closewindow, _quake_tone(210, 0.03, 0.16, 40.0), int(LOFI_RATE * 0.008))

    workspace = []
    n = int(LOFI_RATE * 0.09)
    for i in range(n):
        t = i / LOFI_RATE
        freq = 280.0 + 2100.0 * (t / 0.09) ** 0.7
        env = min(1.0, i / max(1, int(LOFI_RATE * 0.004))) * (1.0 - t / 0.09)
        zap = 0.55 * _square(t, freq, 0.3) + 0.2 * _noise(i, 3)
        workspace.append(math.tanh(zap * 1.5) * env * 0.3)
    _mix(workspace, _quake_noise(0.02, 0.22, 3200, 5), 0)

    fullscreen = []
    n = int(LOFI_RATE * 0.11)
    for i in range(n):
        t = i / LOFI_RATE
        freq = 180.0 * (2.4 ** (t / 0.11))
        env = min(1.0, i / max(1, int(LOFI_RATE * 0.006))) * math.exp(-t * 8.0)
        fullscreen.append(math.tanh(_square(t, freq, 0.38) * 1.2) * env * 0.26)
    _mix(fullscreen, _quake_tone(140, 0.04, 0.18, 20.0), 0)

    unfullscreen = []
    n = int(LOFI_RATE * 0.09)
    for i in range(n):
        t = i / LOFI_RATE
        freq = 900.0 * (0.35 ** (t / 0.09))
        env = min(1.0, i / max(1, int(LOFI_RATE * 0.004))) * math.exp(-t * 10.0)
        unfullscreen.append(math.tanh(_square(t, freq, 0.4) * 1.1) * env * 0.24)

    menu = _quake_tone(1680, 0.028, 0.22, 48.0, duty=0.28)
    _mix(menu, _quake_noise(0.01, 0.16, 4000, 44), 0)

    unfloat = _quake_tone(1120, 0.026, 0.2, 50.0, duty=0.28)
    _mix(unfloat, _quake_noise(0.008, 0.12, 3000, 45), 0)

    minimize = []
    n = int(LOFI_RATE * 0.08)
    for i in range(n):
        t = i / LOFI_RATE
        freq = 1600.0 - 1200.0 * (t / 0.08)
        env = min(1.0, i / max(1, int(LOFI_RATE * 0.003))) * math.exp(-t * 14.0)
        minimize.append((_square(t, freq, 0.32) * 0.7 + _noise(i, 9) * 0.15) * env * 0.24)

    urgent = _quake_tone(310, 0.07, 0.28, 14.0, duty=0.22)
    _mix(urgent, _quake_noise(0.03, 0.2, 1800, 77), 0)

    bell = _quake_tone(880, 0.045, 0.22, 20.0)
    _mix(bell, _quake_tone(1320, 0.07, 0.2, 16.0), int(LOFI_RATE * 0.03))

    return {
        "openwindow": _quake_finish(openwindow),
        "closewindow": _quake_finish(closewindow),
        "workspace": _quake_finish(workspace),
        "fullscreen": _quake_finish(fullscreen),
        "unfullscreen": _quake_finish(unfullscreen),
        "float": _quake_finish(menu),
        "unfloat": _quake_finish(unfloat),
        "minimize": _quake_finish(minimize),
        "urgent": _quake_finish(urgent),
        "bell": _quake_finish(bell),
    }


def pack_has_sounds(directory: Path) -> bool:
    if not directory.is_dir():
        return False
    names = {path.stem for path in directory.iterdir() if path.suffix.lower() in SOUND_EXTS}
    return bool(names & set(EVENTS))


def shipped_packs() -> list[str]:
    names = {"90sfps"}
    for root in (PLUGIN_PACKS, USER_PACKS):
        if not root.is_dir():
            continue
        for path in root.iterdir():
            if path.is_dir() and pack_has_sounds(path):
                names.add(path.name)
    return sorted(names)


def pack_path(name: str) -> str:
    user_pack = USER_PACKS / name
    plugin_pack = PLUGIN_PACKS / name
    if pack_has_sounds(user_pack):
        return str(user_pack)
    if pack_has_sounds(plugin_pack):
        return str(plugin_pack)
    return ""


def describe_packs() -> list[dict[str, str]]:
    rows = [{"name": "theme", "summary": PACK_SUMMARIES["theme"], "path": ""}]
    for name in shipped_packs():
        rows.append({
            "name": name,
            "summary": PACK_SUMMARIES.get(name, "Custom pack"),
            "path": pack_path(name),
        })
    return rows


def list_omarchy_themes() -> list[dict[str, object]]:
    found: dict[str, dict[str, object]] = {}
    for root in (USER_THEMES, SYSTEM_THEMES):
        if not root.is_dir():
            continue
        for path in sorted(root.iterdir()):
            if not path.is_dir() or path.name.startswith("."):
                continue
            sounds_dir = path / "sounds"
            has_sounds = pack_has_sounds(sounds_dir)
            previous = found.get(path.name)
            if previous and previous.get("sounds") and not has_sounds:
                continue
            found[path.name] = {
                "name": path.name,
                "path": str(path),
                "sounds": has_sounds,
            }
    return [found[name] for name in sorted(found)]


def catalog() -> dict[str, object]:
    theme = current_theme()
    return {
        "theme": theme,
        "packs": describe_packs(),
        "themes": list_omarchy_themes(),
        "events": [{"name": name, "summary": EVENT_SUMMARIES.get(name, "")} for name in EVENTS],
    }


def write_catalog() -> None:
    CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CATALOG_PATH.write_text(json.dumps(catalog(), indent=2) + "\n", encoding="utf-8")


def generate_named_pack(name: str, force: bool = False) -> Path:
    recipes_for = {"90sfps": quake_recipes}
    if name in recipes_for:
        dest = USER_PACKS / name
        dest.mkdir(parents=True, exist_ok=True)
        for event, samples in recipes_for[name]().items():
            path = dest / f"{event}.wav"
            if path.exists() and not force:
                continue
            write_wav(path, samples)
        return dest
    user_pack = USER_PACKS / name
    plugin_pack = PLUGIN_PACKS / name
    if pack_has_sounds(user_pack):
        return user_pack
    if pack_has_sounds(plugin_pack):
        return plugin_pack
    known = ", ".join(shipped_packs()) or "none"
    raise SystemExit(f"unknown sound pack: {name} (available: {known})")


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


def resolve_sound(event: str, theme: str, pack: str = "") -> str:
    search = [
        USER_THEMES / theme / "sounds",
        CURRENT_THEME_DIR / "sounds",
    ]
    if pack and pack not in {"theme", "auto", "default"}:
        search.extend([USER_PACKS / pack, PLUGIN_PACKS / pack])
    search.extend([GENERATED_DIR / theme, DEFAULT_DIR])
    for directory in search:
        for ext in SOUND_EXTS:
            path = directory / f"{event}{ext}"
            if path.is_file():
                return str(path)
    return ""


def resolve_all(theme: str, pack: str = "") -> dict[str, str]:
    return {event: resolve_sound(event, theme, pack) for event in EVENTS}


def parse_pack(argv: list[str]) -> str:
    if "--pack" in argv:
        index = argv.index("--pack")
        if index + 1 < len(argv):
            return argv[index + 1].strip().lower()
    return ""


def main(argv: list[str]) -> int:
    if "-h" in argv or "--help" in argv:
        print(USAGE, end="")
        return 0

    force = "--force" in argv
    pack = parse_pack(argv)
    args = [a for a in argv if not a.startswith("-") and a != pack]
    # Drop the value that belonged to --pack if it was left in args.
    commands = {"generate", "list", "packs", "info", "help"}
    command = args[0] if args and args[0] in commands else "generate"
    theme = next((a for a in args if a not in commands), current_theme())

    if command == "help":
        print(USAGE, end="")
        return 0

    if command == "packs":
        print(json.dumps(shipped_packs(), separators=(",", ":")))
        return 0

    if command == "info":
        write_catalog()
        print(json.dumps(catalog(), separators=(",", ":")))
        return 0

    if command != "list":
        if pack and pack not in {"theme", "auto", "default"}:
            generate_named_pack(pack, force=force)
        generate_pack("default", force=force)
        generate_pack(theme, force=force)
        write_catalog()

    print(json.dumps(resolve_all(theme, pack), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
