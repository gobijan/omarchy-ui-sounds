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
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
  readonly property var eventNames: Sounds.EVENT_NAMES

  property string themeName: "default"
  property var config: Sounds.defaultConfig()
  property string configText: ""
  property var soundIndex: ({})
  property bool generating: false
  property double startedAt: Date.now()
  property var lastPlayed: ({})

  readonly property bool enabled: config.enabled !== false
  readonly property real volume: Number(config.volume || 0)

  function applyConfig(text) {
    root.configText = text || ""
    root.config = Sounds.parseConfig(text)
  }

  function applyThemeName(text) {
    var name = String(text || "").trim() || "default"
    if (name === root.themeName && Object.keys(root.soundIndex).length)
      return
    root.themeName = name
    generatePack(name, true)
  }

  function writeEnabled(value) {
    var next = Sounds.setEnabledInConfig(root.configText || "enabled=true\nvolume=0.38\n", value)
    configFile.setText(next)
    applyConfig(next)
  }

  function applySoundIndex(text) {
    try {
      var parsed = JSON.parse(String(text || "{}"))
      root.soundIndex = parsed && typeof parsed === "object" ? parsed : {}
    } catch (error) {
      root.soundIndex = {}
    }
  }

  onPluginDirChanged: {
    if (root.pluginDir)
      generatePack(root.themeName || "default", false)
  }

  function generatePack(theme, force) {
    if (!root.pluginDir || generateProcess.running)
      return
    var args = ["python3", root.pluginDir + "/generate.py"]
    if (force)
      args.push("--force")
    args.push(theme || root.themeName || "default")
    root.generating = true
    generateStdout.text = ""
    generateProcess.command = args
    generateProcess.running = true
  }

  function soundUrl(event) {
    var path = root.soundIndex[event] || ""
    return Sounds.fileUrl(path)
  }

  function play(event) {
    if (!root.enabled || root.generating)
      return false
    if (root.config.events && root.config.events[event] === false)
      return false
    var index = root.eventNames.indexOf(event)
    if (index < 0)
      return false
    var fx = players.objectAt(index)
    if (!fx || !String(fx.source || ""))
      return false
    fx.volume = root.volume
    fx.play()
    return true
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
    if (play(name)) {
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
      pluginDir: root.pluginDir,
      sounds: root.soundIndex
    })
  }

  Instantiator {
    id: players
    model: root.eventNames
    delegate: SoundEffect {
      source: Sounds.fileUrl(root.soundIndex[modelData] || "")
      volume: root.volume
    }
  }

  Process {
    id: generateProcess
    stdout: StdioCollector {
      id: generateStdout
      waitForEnd: true
    }
    onExited: function() {
      root.applySoundIndex(generateStdout.text)
      root.generating = false
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: function() {
      var seed = "enabled=true\nvolume=0.38\nstartup_grace_ms=1500\nburst_ms=140\n"
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

    function status(): string {
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

    function play(event: string): string {
      return root.play(event) ? event : "missing"
    }

    function generate(): string {
      root.generatePack(root.themeName, true)
      return root.themeName
    }
  }
}
