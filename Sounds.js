.pragma library

var EVENT_SOUNDS = {
  openwindow: "openwindow",
  closewindow: "closewindow",
  workspacev2: "workspace",
  urgent: "urgent",
  bell: "bell"
}

var STATEFUL_EVENTS = {
  fullscreen: ["unfullscreen", "fullscreen"],
  changefloatingmode: ["unfloat", "float"],
  minimized: ["unminimize", "minimize"]
}

var EVENT_NAMES = [
  "openwindow",
  "closewindow",
  "workspace",
  "fullscreen",
  "unfullscreen",
  "float",
  "unfloat",
  "minimize",
  "urgent",
  "bell"
]

var IGNORE_CLASSES = {
  "hyprland-preview-share-picker": true,
  "xdph-picker": true
}

var SOUND_EXTS = [".wav", ".ogg", ".oga", ".mp3", ".flac", ".opus"]

var PACK_SUMMARIES = {
  theme: "Follow the active Omarchy theme palette",
  quake: "LibreQuake menu and item remakes",
  "90sfps": "Synthesized 90s-FPS homage",
  kenney: "Clean modern UI clicks",
  digital: "Arcade lasers and power-ups",
  chip: "8-bit menu blips",
  scifi: "Airlock doors, lasers, force fields"
}

var EVENT_SUMMARIES = {
  openwindow: "A window opens",
  closewindow: "A window closes",
  workspace: "Workspace switch",
  fullscreen: "A window enters fullscreen",
  unfullscreen: "A window leaves fullscreen",
  float: "A window is floated",
  unfloat: "A window is tiled",
  minimize: "A window is minimized",
  urgent: "A window requests attention (off by default)",
  bell: "An app rings the system bell (off by default)"
}

var DEFAULT_CONFIG_TEXT = [
  "enabled=true",
  "volume=0.45",
  "startup_grace_ms=600",
  "burst_ms=100",
  "pack=",
  "event.urgent=false",
  "event.bell=false",
  ""
].join("\n")

function defaultConfig() {
  return {
    enabled: true,
    volume: 0.45,
    startup_grace_ms: 600,
    burst_ms: 100,
    pack: "",
    events: {
      urgent: false,
      bell: false
    }
  }
}

function parseBool(value) {
  var s = String(value || "").trim().toLowerCase()
  return s === "1" || s === "true" || s === "yes" || s === "on"
}

function parseConfig(text) {
  var cfg = defaultConfig()
  String(text || "").split("\n").forEach(function (raw) {
    var line = raw.split("#", 1)[0].trim()
    if (!line || line.indexOf("=") === -1)
      return
    var parts = line.split("=")
    var key = parts[0].trim()
    var value = parts.slice(1).join("=").trim()
    if (key === "enabled")
      cfg.enabled = parseBool(value)
    else if (key === "volume")
      cfg.volume = Math.max(0, Math.min(1, Number(value)))
    else if (key === "startup_grace_ms")
      cfg.startup_grace_ms = Math.max(0, parseInt(value, 10) || 0)
    else if (key === "burst_ms")
      cfg.burst_ms = Math.max(0, parseInt(value, 10) || 0)
    else if (key === "pack")
      cfg.pack = value.replace(/[^a-z0-9_-]/gi, "").toLowerCase()
    else if (key.indexOf("event.") === 0)
      cfg.events[key.slice(6)] = parseBool(value)
  })
  return cfg
}

function setKeyInConfig(text, key, value) {
  var written = false
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].replace(/^\s+/, "").indexOf(key + "=") === 0) {
      lines[i] = key + "=" + value
      written = true
    }
  }
  if (!written)
    lines.push(key + "=" + value)
  var out = lines.join("\n")
  if (out.length && out.charAt(out.length - 1) !== "\n")
    out += "\n"
  return out
}

function setEnabledInConfig(text, enabled) {
  return setKeyInConfig(text, "enabled", enabled ? "true" : "false")
}

function setPackInConfig(text, pack) {
  return setKeyInConfig(text || DEFAULT_CONFIG_TEXT, "pack", pack)
}

function fallbackCatalog() {
  var packs = [{ name: "theme", summary: PACK_SUMMARIES.theme, path: "" }]
  var names = ["90sfps", "chip", "digital", "kenney", "quake", "scifi"]
  for (var i = 0; i < names.length; i++)
    packs.push({ name: names[i], summary: PACK_SUMMARIES[names[i]], path: "" })
  var events = []
  for (var j = 0; j < EVENT_NAMES.length; j++)
    events.push({ name: EVENT_NAMES[j], summary: EVENT_SUMMARIES[EVENT_NAMES[j]] || "" })
  return { theme: "default", packs: packs, themes: [], events: events }
}

function normalizeCatalog(raw) {
  var fallback = fallbackCatalog()
  if (!raw || typeof raw !== "object")
    return fallback
  return {
    theme: String(raw.theme || fallback.theme),
    packs: raw.packs && raw.packs.length ? raw.packs : fallback.packs,
    themes: raw.themes && raw.themes.length ? raw.themes : [],
    events: raw.events && raw.events.length ? raw.events : fallback.events
  }
}

function currentPackName(pack) {
  var name = String(pack || "").trim().toLowerCase()
  if (!name || name === "auto" || name === "off" || name === "default")
    return "theme"
  return name
}

function knownPackNames(catalog) {
  var names = ["theme"]
  var packs = catalog && catalog.packs ? catalog.packs : []
  for (var i = 0; i < packs.length; i++) {
    var name = String(packs[i].name || "").trim()
    if (name && names.indexOf(name) < 0)
      names.push(name)
  }
  return names
}

function padRight(text, width) {
  var s = String(text || "")
  while (s.length < width)
    s += " "
  return s
}

function formatPacks(catalog, activePack) {
  var packs = catalog && catalog.packs ? catalog.packs : fallbackCatalog().packs
  var current = currentPackName(activePack)
  var lines = ["Packs:"]
  for (var i = 0; i < packs.length; i++) {
    var pack = packs[i]
    var name = String(pack.name || "")
    var mark = name === current ? "*" : " "
    var summary = pack.summary || PACK_SUMMARIES[name] || "Custom pack"
    lines.push("  " + mark + " " + padRight(name, 10) + "  " + summary)
  }
  lines.push("")
  lines.push("Use: omarchy-shell ui-sounds pack <name>")
  return lines.join("\n")
}

function formatThemes(catalog, activeTheme) {
  var themes = catalog && catalog.themes ? catalog.themes : []
  var current = String(activeTheme || (catalog && catalog.theme) || "default")
  var lines = ["Omarchy themes:"]
  if (!themes.length) {
    lines.push("  (none found under ~/.config/omarchy/themes or /usr/share/omarchy/themes)")
    lines.push("")
    lines.push("Active theme: " + current)
    lines.push("pack=theme follows this palette for generated clicks.")
    return lines.join("\n")
  }
  var withSounds = 0
  for (var i = 0; i < themes.length; i++) {
    var theme = themes[i]
    var name = String(theme.name || "")
    var mark = name === current ? "*" : " "
    var extra = theme.sounds ? "  [has sounds/]" : ""
    lines.push("  " + mark + " " + name + extra)
    if (theme.sounds)
      withSounds += 1
  }
  lines.push("")
  lines.push("Active: " + current + "  (" + themes.length + " installed, " + withSounds + " with sounds/)")
  lines.push("pack=theme tints generated clicks from the active theme.")
  lines.push("A theme sounds/ directory overrides the selected pack.")
  return lines.join("\n")
}

function formatEvents(catalog, eventsConfig) {
  var events = catalog && catalog.events ? catalog.events : fallbackCatalog().events
  var cfg = eventsConfig || {}
  var lines = ["Events:"]
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var name = String(event.name || "")
    var muted = cfg[name] === false
    var flag = muted ? "off" : "on "
    lines.push("  " + flag + "  " + padRight(name, 14) + "  " + (event.summary || EVENT_SUMMARIES[name] || ""))
  }
  lines.push("")
  lines.push("Use: omarchy-shell ui-sounds play <event>")
  return lines.join("\n")
}

function formatStatus(state) {
  var enabled = state.enabled !== false
  var pack = currentPackName(state.pack)
  var lines = [
    "ui-sounds",
    "  enabled    " + (enabled ? "on" : "off"),
    "  volume     " + String(state.volume),
    "  theme      " + (state.theme || "default"),
    "  pack       " + pack,
    "  generating " + (state.generating ? "yes" : "no"),
    "",
    formatPacks(state.catalog, pack),
    "",
    "Help: omarchy-shell ui-sounds help"
  ]
  return lines.join("\n")
}

function formatHelp(state) {
  var pack = currentPackName(state.pack)
  var lines = [
    "ui-sounds — window and workspace sound effects",
    "",
    "Usage:",
    "  omarchy-shell ui-sounds <command> [args]",
    "",
    "Commands:",
    "  help              Show this help",
    "  status            Current state and pack list",
    "  json              Machine-readable status",
    "  toggle            Enable or disable playback",
    "  enable            Turn sounds on",
    "  disable           Turn sounds off",
    "  packs             List sound packs",
    "  pack <name>       Switch pack (theme, quake, 90sfps, ...)",
    "  themes            List Omarchy themes",
    "  play <event>      Play one event",
    "  events            List events",
    "  generate          Regenerate theme-tinted clicks",
    "",
    "Current: " + (state.enabled !== false ? "on" : "off") +
      "  pack=" + pack +
      "  theme=" + (state.theme || "default") +
      "  volume=" + String(state.volume),
    "",
    formatPacks(state.catalog, pack)
  ]
  return lines.join("\n")
}

function eventParts(event, count) {
  try {
    if (event && event.parse)
      return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}

function soundForEvent(event) {
  var name = String(event && event.name ? event.name : "")
  var data = String(event && event.data ? event.data : "")
  if (name === "openwindow") {
    var parts = eventParts(event, 4)
    var klass = String(parts[2] || "")
    if (IGNORE_CLASSES[klass])
      return ""
    return "openwindow"
  }
  if (EVENT_SOUNDS[name])
    return EVENT_SOUNDS[name]
  if (STATEFUL_EVENTS[name]) {
    var pair = STATEFUL_EVENTS[name]
    var bit = data.split(",").pop().trim()
    return bit === "1" ? pair[1] : pair[0]
  }
  return ""
}

function candidatePaths(home, theme, event) {
  var dirs = [
    home + "/.config/omarchy/themes/" + theme + "/sounds",
    home + "/.local/state/omarchy/current/theme/sounds",
    home + "/.config/omarchy/sounds/generated/" + theme,
    home + "/.config/omarchy/sounds/default"
  ]
  var paths = []
  for (var i = 0; i < dirs.length; i++) {
    for (var j = 0; j < SOUND_EXTS.length; j++)
      paths.push(dirs[i] + "/" + event + SOUND_EXTS[j])
  }
  return paths
}

function fileUrl(path) {
  if (!path)
    return ""
  return "file://" + path
}
