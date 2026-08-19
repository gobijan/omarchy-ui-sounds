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

function defaultConfig() {
  return {
    enabled: true,
    volume: 0.38,
    startup_grace_ms: 1500,
    burst_ms: 140,
    events: {}
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
    else if (key.indexOf("event.") === 0)
      cfg.events[key.slice(6)] = parseBool(value)
  })
  return cfg
}

function setEnabledInConfig(text, enabled) {
  var written = false
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].replace(/^\s+/, "").indexOf("enabled=") === 0) {
      lines[i] = "enabled=" + (enabled ? "true" : "false")
      written = true
    }
  }
  if (!written)
    lines.unshift("enabled=" + (enabled ? "true" : "false"))
  var out = lines.join("\n")
  if (out.length && out.charAt(out.length - 1) !== "\n")
    out += "\n"
  return out
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
