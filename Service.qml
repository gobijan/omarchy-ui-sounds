import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Sounds.js" as Sounds

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string configPath: home + "/.config/omarchy/sounds/config"
  readonly property string catalogPath: home + "/.config/omarchy/sounds/catalog.json"
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
  readonly property var eventNames: Sounds.EVENT_NAMES

  property string themeName: "default"
  property var config: Sounds.defaultConfig()
  property string configText: ""
  property var soundIndex: ({})
  property var catalog: Sounds.fallbackCatalog()
  property bool generating: false
  property string pendingTheme: ""
  property bool pendingForce: false
  property double startedAt: Date.now()
  property var lastPlayed: ({})

  readonly property bool enabled: config.enabled !== false
  readonly property real volume: Number(config.volume || 0)

  function applyConfig(text) {
    var previousPack = root.config.pack || ""
    root.configText = text || ""
    root.config = Sounds.parseConfig(text)
    if (root.pluginDir && (root.config.pack || "") !== previousPack)
      generatePack(root.themeName, false)
  }

  function applyThemeName(text) {
    var name = String(text || "").trim() || "default"
    if (name === root.themeName) {
      if (!Object.keys(root.soundIndex).length)
        generatePack(name, false)
      return
    }
    root.themeName = name
    generatePack(name, false)
  }

  function writeEnabled(value) {
    var next = Sounds.setEnabledInConfig(root.configText || Sounds.DEFAULT_CONFIG_TEXT, value)
    configFile.setText(next)
    applyConfig(next)
  }

  function applySoundIndex(text) {
    try {
      var parsed = JSON.parse(String(text || "{}"))
      var next = {}
      if (parsed && typeof parsed === "object") {
        for (var i = 0; i < root.eventNames.length; i++) {
          var event = root.eventNames[i]
          if (parsed[event])
            next[event] = parsed[event]
        }
      }
      root.soundIndex = next
    } catch (error) {
      root.soundIndex = {}
    }
  }

  function applyCatalog(text) {
    try {
      root.catalog = Sounds.normalizeCatalog(JSON.parse(String(text || "{}")))
    } catch (error) {
      root.catalog = Sounds.fallbackCatalog()
    }
  }

  function helpState() {
    return {
      enabled: root.enabled,
      volume: root.volume,
      theme: root.themeName,
      pack: root.config.pack || "",
      generating: root.generating,
      catalog: root.catalog
    }
  }

  function knownPacks() {
    return Sounds.knownPackNames(root.catalog)
  }

  onPluginDirChanged: {
    if (root.pluginDir)
      generatePack(root.themeName || "default", false)
  }

  function generatePack(theme, force) {
    if (!root.pluginDir)
      return
    theme = theme || root.themeName || "default"
    if (generateProcess.running) {
      root.pendingTheme = theme
      root.pendingForce = root.pendingForce || !!force
      return
    }
    var args = ["/usr/bin/python3", root.pluginDir + "/generate.py"]
    if (force)
      args.push("--force")
    if (root.config.pack)
      args.push("--pack", root.config.pack)
    args.push(theme)
    root.generating = true
    generateProcess.command = args
    generateProcess.running = true
  }

  function finishGenerate() {
    root.generating = false
    if (!root.pendingTheme)
      return
    var theme = root.pendingTheme
    var force = root.pendingForce
    root.pendingTheme = ""
    root.pendingForce = false
    generatePack(theme, force)
  }

  function soundPath(event) {
    if (root.soundIndex[event])
      return root.soundIndex[event]
    return root.home + "/.config/omarchy/sounds/generated/" + root.themeName + "/" + event + ".wav"
  }

  function soundUrl(event) {
    return Sounds.fileUrl(soundPath(event))
  }

  function play(event) {
    event = String(event || "").trim().toLowerCase()
    if (root.eventNames.indexOf(event) < 0)
      return ""
    if (!root.enabled)
      return "disabled"
    if (root.config.events && root.config.events[event] === false)
      return "muted"
    var index = root.eventNames.indexOf(event)
    var fx = players.objectAt(index)
    if (!fx || !String(fx.source || ""))
      return "missing"
    fx.volume = root.volume
    fx.play()
    return event
  }

  function handleHyprlandEvent(event) {
    var name = Sounds.soundForEvent(event)
    if (!name)
      return
    var now = Date.now()
    if (now - root.startedAt < (root.config.startup_grace_ms || 0))
      return
    var last = root.lastPlayed[name] || 0
    if (now - last < (root.config.burst_ms || 0))
      return
    if (play(name) === name) {
      var next = {}
      for (var key in root.lastPlayed)
        next[key] = root.lastPlayed[key]
      next[name] = now
      root.lastPlayed = next
    }
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.enabled,
      volume: root.volume,
      theme: root.themeName,
      pack: root.config.pack || "",
      pluginDir: root.pluginDir,
      generating: root.generating,
      packs: root.knownPacks(),
      events: root.eventNames,
      sounds: root.soundIndex
    })
  }

  Instantiator {
    id: players
    model: root.eventNames
    delegate: SoundEffect {
      source: Sounds.fileUrl(root.soundIndex[modelData] || (root.home + "/.config/omarchy/sounds/generated/" + root.themeName + "/" + modelData + ".wav"))
      volume: root.volume
    }
  }

  Process {
    id: generateProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applySoundIndex(text)
        root.finishGenerate()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.finishGenerate()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: function() {
      var seed = Sounds.DEFAULT_CONFIG_TEXT
      setText(seed)
      root.applyConfig(seed)
    }
    onFileChanged: reload()
  }

  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyThemeName(text())
    onLoadFailed: function() { root.applyThemeName("default") }
    onFileChanged: reload()
  }

  FileView {
    id: catalogFile
    path: root.catalogPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyCatalog(text())
    onLoadFailed: function() { root.catalog = Sounds.fallbackCatalog() }
    onFileChanged: reload()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Component.onCompleted: {
    if (root.pluginDir)
      generatePack(root.themeName, false)
  }

  IpcHandler {
    target: "ui-sounds"

    function help(): string {
      return Sounds.formatHelp(root.helpState())
    }

    function status(): string {
      return Sounds.formatStatus(root.helpState())
    }

    function json(): string {
      return root.statusJson()
    }

    function toggle(): string {
      root.writeEnabled(!root.enabled)
      return root.enabled ? "on" : "off"
    }

    function enable(): string {
      root.writeEnabled(true)
      return "on"
    }

    function disable(): string {
      root.writeEnabled(false)
      return "off"
    }

    function packs(): string {
      return Sounds.formatPacks(root.catalog, root.config.pack)
    }

    function themes(): string {
      return Sounds.formatThemes(root.catalog, root.themeName)
    }

    function events(): string {
      return Sounds.formatEvents(root.catalog, root.config.events)
    }

    function play(event: string): string {
      var result = root.play(event)
      if (result)
        return result
      return "unknown event: " + event + "\n\n" + Sounds.formatEvents(root.catalog, root.config.events)
    }

    function generate(): string {
      root.generatePack(root.themeName, true)
      return root.themeName
    }

    function pack(name: string): string {
      var next = String(name || "").trim().toLowerCase()
      if (next === "list" || next === "ls" || next === "help" || next === "?")
        return Sounds.formatPacks(root.catalog, root.config.pack)
      if (next === "theme" || next === "auto" || next === "off")
        next = ""
      var known = root.knownPacks()
      if (next && known.indexOf(next) < 0)
        return "unknown pack: " + next + "\n\n" + Sounds.formatPacks(root.catalog, root.config.pack)
      var text = Sounds.setPackInConfig(root.configText || Sounds.DEFAULT_CONFIG_TEXT, next)
      configFile.setText(text)
      root.applyConfig(text)
      return next || "theme"
    }
  }
}
