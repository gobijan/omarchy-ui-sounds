# Interface Sounds

Theme-aware window and workspace clicks for [Omarchy](https://omarchy.org/).

![Interface Sounds](preview.png)

https://github.com/user-attachments/assets/c0058d10-2226-4c89-8c99-6435877340ea

This is an Omarchy **shell plugin**, not a theme and not a standalone daemon. That is the distribution channel Omarchy already has: a git repo with a `manifest.json`, installed by `omarchy plugin add`.

```bash
omarchy plugin add https://github.com/gobijan/omarchy-ui-sounds.git --enable
```

Update and remove are the same channel:

```bash
omarchy plugin update gobijan.ui-sounds
omarchy plugin remove gobijan.ui-sounds
```

The plugin is a headless `service`. Enabling it is enough — it does not add a bar widget. It listens to Hyprland events inside `omarchy-shell` and plays short `SoundEffect`s, so there is no extra systemd unit.

## Why a plugin, not a theme

| Channel | What it installs | Why not this |
|---|---|---|
| `omarchy theme install` | colors, backgrounds, app tints | Themes do not run code |
| `omarchy plugin add` | QML that lives in the shell | **This.** Events + playback belong here |
| AUR / `install.sh` | extra daemons and units | Works, but duplicates what the shell already hosts |

Themes *can* still ship the samples. The plugin is what plays them.

## Theme sound packs

Drop files named after the event into a theme. `omarchy theme install` already clones a theme repo into `~/.config/omarchy/themes/<slug>/`, so a theme author only needs this extra directory:

```text
your-theme/
  colors.toml
  backgrounds/
  sounds/
    openwindow.wav
    closewindow.wav
    workspace.wav
    fullscreen.wav
    unfullscreen.wav
    float.wav
    unfloat.wav
    minimize.wav
    urgent.wav
    bell.wav
```

Lookup order:

1. `~/.config/omarchy/themes/<theme>/sounds/`
2. the active theme's staged copy
3. a named pack (`pack=quake` → `packs/quake/` in the plugin, or `~/.config/omarchy/sounds/packs/quake/`)
4. a generated pack tinted from that theme's `colors.toml`
5. `~/.config/omarchy/sounds/default/`

Formats: `wav`, `ogg`, `oga`, `mp3`, `flac`, `opus`. Generated clicks are 44.1 kHz mono WAV.

If a theme has no `sounds/` directory, the plugin synthesizes a pack from the theme accent so switching themes still changes the clicks.

## Config

`~/.config/omarchy/sounds/config` is created on first run. Edits apply immediately.

```ini
enabled=true
volume=0.45
startup_grace_ms=600
burst_ms=100
pack=
event.urgent=false
event.bell=false
```

| Key | Default | What it does |
|---|---|---|
| `enabled` | `true` | Master on/off. The Toggle menu and `omarchy-shell ui-sounds toggle` flip this. |
| `volume` | `0.45` | Playback level from `0` (silent) to `1` (full). This is independent of the system output slider. `0.45` is present without jumping over music. |
| `startup_grace_ms` | `600` | Milliseconds after the plugin starts during which no sounds play. Covers the burst of Hyprland events when the shell comes up, so login does not machine-gun clicks. |
| `burst_ms` | `100` | Per-event cooldown. If the same event fires twice inside this window (compositor double-fires, session restore), only the first click plays. Two windows you open farther apart still get two sounds. |
| `pack` | empty | Which sample set to use after theme overlays. Empty / `theme` / `auto` follows the Omarchy theme palette. Named packs live in `packs/<name>/`. |
| `event.<name>` | on, except `urgent` and `bell` | Per-event mute. `false` skips that event even if a file exists. |

Events you can set with `event.<name>`:

| Event | When it plays |
|---|---|
| `openwindow` | A window opens |
| `closewindow` | A window closes |
| `workspace` | You switch workspaces |
| `fullscreen` / `unfullscreen` | A window enters or leaves fullscreen |
| `float` / `unfloat` | A window is floated or tiled |
| `minimize` | A window is minimized |
| `urgent` | A window requests attention (chat, browser). Off by default; some apps spam this. |
| `bell` | An app rings the system bell. Off by default; terminals can fire it often. |

Shipped packs:

| Pack | Character | Source | License |
|---|---|---|---|
| *(empty)* / `theme` | clicks tinted from the active theme | generated | MIT |
| `quake` | LibreQuake menu, item, and talk sounds | [LibreQuake](https://github.com/lavenderdotpet/LibreQuake) | BSD-3-Clause |
| `90sfps` | 90s-FPS homage (synthesized, not ripped) | this plugin | MIT |
| `kenney` | clean modern UI clicks | [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) | CC0 |
| `digital` | arcade lasers and power-ups | [Kenney Digital Audio](https://kenney.nl/assets/digital-audio) | CC0 |
| `chip` | 8-bit menu blips | [Juhani Junkala 512 SFX](https://opengameart.org/content/512-sound-effects-8-bit-style) | CC0 |
| `scifi` | airlock doors, lasers, force fields | [Kenney Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) | CC0 |

Original id Software Quake samples are not shipped. `quake` is the legal remake from LibreQuake. Each pack has `ATTRIBUTION.txt`.

Example: turn urgent alerts on, Quake pack, a bit louder:

```ini
volume=0.55
pack=quake
event.urgent=true
```

## Control

Super menu → **Trigger → Toggle → Interface Sounds**:

![Toggle Interface Sounds](media/toggle-interface-sounds.png)

```bash
omarchy-shell ui-sounds help
omarchy-shell ui-sounds status
omarchy-shell ui-sounds packs
omarchy-shell ui-sounds themes
omarchy-shell ui-sounds events
omarchy-shell ui-sounds pack quake
omarchy-shell ui-sounds pack kenney
omarchy-shell ui-sounds pack theme
omarchy-shell ui-sounds play openwindow
omarchy-shell ui-sounds toggle
omarchy-shell ui-sounds generate
```

`help`, `status`, `packs`, `themes`, and `events` print a list. `json` is the machine-readable snapshot. `pack list` is the same as `packs`. An unknown pack or event name prints the list instead of failing silently.

## Local development

```bash
omarchy plugin add /path/to/omarchy-ui-sounds --enable --yes
omarchy plugin validate /path/to/omarchy-ui-sounds
```

`omarchy plugin add` clones the repo into `~/.config/omarchy/plugins/gobijan.ui-sounds/`. After that, edit the checkout there or update from the origin.

## Requirements

Omarchy with `omarchy-shell` (Quickshell) and `qt6-multimedia`. Both ship with current Omarchy.

## License

MIT. See [LICENSE](LICENSE).
