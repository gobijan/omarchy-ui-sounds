pragma ComponentBehavior: Bound

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
  readonly property var playerModel: Sounds.playerModel(root.eventNames)

  property string themeName: "default"
  property var config: Sounds.defaultConfig()
  property bool configLoaded: false
  property string configText: ""
  property var soundIndex: ({})
  property var catalog: Sounds.fallbackCatalog()
  property bool generating: false
  property string queuedTheme: ""
  property bool queuedForce: false
  property string pendingTheme: ""
  property bool pendingForce: false
  property string generatingTheme: ""
  property string generatingPack: ""
  property bool generatingForce: false
  property var lastPlayed: ({})

  property bool realScreensAvailable: false
  property bool startupGraceComplete: false
  property bool audioCoolingDown: false
  property bool audioSinkAvailable: false
  property int readyPlayerCount: 0
  property var ignoredWindows: Sounds.newIgnoredWindowTracker()
  property int ignoredWindowCount: 0

  readonly property bool playbackEnabled: configLoaded && config.enabled === true
  readonly property bool muted: root.configLoaded && !root.playbackEnabled
  readonly property string barToggleStatePath: home + "/.local/state/omarchy/ui-sounds.bar-widget"
  property bool barToggleStateLoaded: false
  property bool barToggleAlreadyPlaced: false
  property bool barToggleEnsured: false
  readonly property real volume: {
    var value = Number(config.volume)
    return isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
  }

  // null when the host has no lock/idle service
  readonly property var lockService: shell && shell._services ? shell._services["omarchy.lock"] : null
  readonly property var idleService: shell && shell._services ? shell._services["omarchy.idle"] : null
  readonly property bool sessionLocked: !!(lockService && lockService.locked)
  readonly property bool sessionIdle: !!(idleService && (
    idleService.idledThisCycle
    || idleService.screensaverStartedThisCycle
    || Number(idleService.screensaverWindowCount || 0) > 0
  ))
  readonly property bool audioProbeAllowed: root.playbackEnabled
    && root.realScreensAvailable
    && !root.sessionLocked
    && !root.sessionIdle
    && !root.audioCoolingDown
  readonly property bool playersActive: root.audioProbeAllowed
    && root.audioSinkAvailable
    && root.ignoredWindowCount === 0
    && Sounds.hasAllSounds(root.soundIndex, root.eventNames)
  readonly property bool playersReady: root.playersActive
    && players.count === root.playerModel.length
    && root.readyPlayerCount === root.playerModel.length
  readonly property bool playbackReady: Sounds.canPlay({
    configLoaded: root.configLoaded,
    enabled: root.playbackEnabled,
    eventMuted: false,
    startupGraceComplete: root.startupGraceComplete,
    realScreenAvailable: root.realScreensAvailable,
    sessionLocked: root.sessionLocked,
    sessionIdle: root.sessionIdle,
    chromeActive: root.ignoredWindowCount > 0,
    audioCoolingDown: root.audioCoolingDown,
    audioAvailable: root.audioSinkAvailable,
    playersReady: root.playersReady
  })

  // Stay subscribed while playback is enabled so ignored chrome is recorded
  // even when the player bank is down; canPlay() still drops the samples.
  readonly property bool eventListeningEnabled: root.playbackEnabled && root.realScreensAvailable

  function applyConfig(text) {
    var previousPack = root.config.pack || ""
    var next = Sounds.parseConfig(text)
    root.configText = text || ""
    root.config = next
    root.configLoaded = true

    var packChanged = (next.pack || "") !== previousPack
    if (packChanged) {
      root.stopAndUnloadPlayers()
      root.soundIndex = ({})
    }

    if (!next.enabled) {
      root.stopAndUnloadPlayers()
      return
    }

    if (packChanged)
      root.scheduleGenerate(root.themeName, false)
  }

  function applyThemeName(text) {
    var name = String(text || "").trim() || "default"
    if (name === root.themeName) {
      if (root.playbackEnabled && !Object.keys(root.soundIndex).length)
        root.scheduleGenerate(name, false)
      return
    }
    root.stopAndUnloadPlayers()
    root.soundIndex = ({})
    root.themeName = name
    root.scheduleGenerate(name, false)
  }

  function writeEnabled(value) {
    var next = Sounds.setEnabledInConfig(root.configText || Sounds.DEFAULT_CONFIG_TEXT, value)
    configFile.setText(next)
    root.applyConfig(next)
  }

  function pluginId() {
    return root.manifest && root.manifest.id ? String(root.manifest.id) : "gobijan.ui-sounds"
  }

  function markBarTogglePlaced() {
    root.barToggleAlreadyPlaced = true
    root.barToggleEnsured = true
    barToggleStateFile.setText("1\n")
  }

  function ensureBarToggle() {
    if (root.barToggleEnsured || !root.barToggleStateLoaded)
      return
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function")
      return
    if (root.barToggleAlreadyPlaced) {
      root.barToggleEnsured = true
      return
    }
    var id = root.pluginId()
    var config = root.shell.shellConfig
    var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
    if (Sounds.layoutHasWidget(layout, id)) {
      root.markBarTogglePlaced()
      return
    }
    var preview = Sounds.placeCenterToggle(layout, id)
    if (!preview.changed) {
      root.markBarTogglePlaced()
      return
    }
    root.shell.mutateShellConfig(function(next) {
      if (!next.bar)
        next.bar = {}
      var result = Sounds.placeCenterToggle(next.bar.layout || {}, id)
      if (result.changed)
        next.bar.layout = result.layout
    })
    root.markBarTogglePlaced()
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
      enabled: root.playbackEnabled,
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

  function clearIgnoredWindows() {
    root.ignoredWindows = Sounds.newIgnoredWindowTracker()
    root.ignoredWindowCount = 0
  }

  function refreshRealScreens() {
    var available = Sounds.hasRealScreen(Quickshell.screens || [])
    if (!available)
      root.clearIgnoredWindows()
    root.realScreensAvailable = available
  }

  function armStartupGrace() {
    startupGraceTimer.stop()
    root.startupGraceComplete = false
    var delay = Math.max(0, Number(root.config.startup_grace_ms) || 0)
    if (delay === 0) {
      root.startupGraceComplete = true
      return
    }
    startupGraceTimer.interval = delay
    startupGraceTimer.restart()
  }

  function scheduleGenerate(theme, force) {
    if (!root.playbackEnabled || !root.pluginDir)
      return
    root.queuedTheme = theme || root.themeName || "default"
    root.queuedForce = root.queuedForce || !!force
    generateCoalesceTimer.restart()
  }

  function generatePack(theme, force) {
    if (!root.playbackEnabled || !root.pluginDir)
      return
    theme = theme || root.themeName || "default"
    if (generateProcess.running) {
      var sameRequest = theme === root.generatingTheme
        && (root.config.pack || "") === root.generatingPack
      if (sameRequest && (!force || root.generatingForce))
        return
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
    root.generatingTheme = theme
    root.generatingPack = root.config.pack || ""
    root.generatingForce = !!force
    root.generating = true
    generateProcess.command = args
    generateProcess.running = true
  }

  function finishGenerate() {
    if (!root.generating)
      return
    root.generating = false
    root.generatingTheme = ""
    root.generatingPack = ""
    root.generatingForce = false
    if (!root.playbackEnabled) {
      root.pendingTheme = ""
      root.pendingForce = false
      return
    }
    if (!root.pendingTheme)
      return
    var theme = root.pendingTheme
    var force = root.pendingForce
    root.pendingTheme = ""
    root.pendingForce = false
    root.scheduleGenerate(theme, force)
  }

  function soundPath(event) {
    return root.soundIndex[event] ? String(root.soundIndex[event]) : ""
  }

  function canPlay(event, fx) {
    if (!root.playbackReady)
      return false
    if (root.config.events && root.config.events[event] === false)
      return false
    return !!fx && fx.status === SoundEffect.Ready && !fx.playing
  }

  function stopAndUnloadPlayers() {
    playerWarmupTimeout.stop()
    for (var i = 0; i < players.count; i++) {
      var fx = players.objectAt(i) as SoundEffect
      if (!fx)
        continue
      if (fx.playing)
        fx.stop()
      fx.source = ""
    }
    root.readyPlayerCount = 0
  }

  function refreshPlayerReadiness() {
    if (!root.playersActive) {
      root.readyPlayerCount = 0
      playerWarmupTimeout.stop()
      return
    }
    var ready = 0
    for (var i = 0; i < players.count; i++) {
      var fx = players.objectAt(i) as SoundEffect
      if (fx && fx.status === SoundEffect.Ready)
        ready += 1
    }
    root.readyPlayerCount = ready
    if (ready === root.playerModel.length)
      playerWarmupTimeout.stop()
  }

  function probeAudioSink() {
    if (!root.audioProbeAllowed || root.audioSinkAvailable || audioProbeProcess.running)
      return
    audioProbeProcess.command = ["/usr/bin/wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"]
    audioProbeTimeout.restart()
    audioProbeProcess.running = true
  }

  function enterAudioCooldown(reason) {
    var firstFailure = !root.audioCoolingDown
    root.audioCoolingDown = true
    root.audioSinkAvailable = false
    if (firstFailure) {
      console.warn("ui-sounds: audio playback failed; backing off for 10 seconds (" + reason + ")")
      audioCooldownTimer.restart()
    }
    root.stopAndUnloadPlayers()
  }

  function availablePlayer(event) {
    for (var i = 0; i < players.count; i++) {
      var fx = players.objectAt(i) as SoundEffect
      if (root.playerModel[i] === event && fx
          && fx.status === SoundEffect.Ready && !fx.playing)
        return fx
    }
    return null
  }

  function play(event) {
    event = String(event || "").trim().toLowerCase()
    var index = root.eventNames.indexOf(event)
    if (index < 0)
      return ""
    var fx = root.availablePlayer(event)
    if (root.canPlay(event, fx)) {
      fx.play()
      return event
    }
    if (!root.playbackEnabled)
      return "disabled"
    if (root.config.events && root.config.events[event] === false)
      return "muted"
    if (!root.playersReady)
      return "loading"
    if (!fx)
      return "busy"
    return "unavailable"
  }

  function handleHyprlandEvent(event) {
    if (!root.eventListeningEnabled)
      return

    var previousIgnoredCount = root.ignoredWindowCount
    var name = Sounds.soundForEvent(event, root.ignoredWindows)
    root.ignoredWindowCount = Sounds.ignoredWindowCount(root.ignoredWindows)
    if (root.ignoredWindowCount > previousIgnoredCount)
      root.stopAndUnloadPlayers()
    if (!name)
      return

    var now = Date.now()
    var last = root.lastPlayed[name] || 0
    if (now - last < (root.config.burst_ms || 0))
      return
    if (root.play(name) === name) {
      var next = {}
      for (var key in root.lastPlayed)
        next[key] = root.lastPlayed[key]
      next[name] = now
      root.lastPlayed = next
    }
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.playbackEnabled,
      muted: root.muted,
      volume: root.volume,
      theme: root.themeName,
      pack: root.config.pack || "",
      pluginDir: root.pluginDir,
      generating: root.generating,
      realScreens: root.realScreensAvailable,
      sessionLocked: root.sessionLocked,
      sessionIdle: root.sessionIdle,
      audioCoolingDown: root.audioCoolingDown,
      audioSinkAvailable: root.audioSinkAvailable,
      playersActive: root.playersActive,
      playersReady: root.playersReady,
      readyPlayers: root.readyPlayerCount,
      playerCount: players.count,
      packs: root.knownPacks(),
      events: root.eventNames,
      sounds: root.soundIndex
    })
  }

  onPlaybackEnabledChanged: {
    if (!root.playbackEnabled) {
      generateCoalesceTimer.stop()
      startupGraceTimer.stop()
      audioCooldownTimer.stop()
      root.queuedTheme = ""
      root.queuedForce = false
      root.pendingTheme = ""
      root.pendingForce = false
      root.startupGraceComplete = false
      root.audioCoolingDown = false
      root.audioSinkAvailable = false
      root.stopAndUnloadPlayers()
      return
    }
    root.armStartupGrace()
    root.scheduleGenerate(root.themeName, false)
  }

  onPluginDirChanged: root.scheduleGenerate(root.themeName, false)
  onShellChanged: Qt.callLater(root.ensureBarToggle)

  onAudioProbeAllowedChanged: {
    if (!root.audioProbeAllowed) {
      audioProbeTimeout.stop()
      if (audioProbeProcess.running)
        audioProbeProcess.running = false
      root.audioSinkAvailable = false
      root.stopAndUnloadPlayers()
      return
    }
    Qt.callLater(root.probeAudioSink)
  }

  onPlayersActiveChanged: {
    root.readyPlayerCount = 0
    if (!root.playersActive) {
      playerWarmupTimeout.stop()
      return
    }
    playerWarmupTimeout.restart()
    Qt.callLater(root.refreshPlayerReadiness)
  }

  onSessionLockedChanged: {
    if (root.sessionLocked)
      root.clearIgnoredWindows()
  }

  onSessionIdleChanged: {
    if (root.sessionIdle)
      root.clearIgnoredWindows()
  }

  Timer {
    id: startupGraceTimer
    repeat: false
    onTriggered: root.startupGraceComplete = true
  }

  Timer {
    id: generateCoalesceTimer
    interval: 250
    repeat: false
    onTriggered: {
      var theme = root.queuedTheme || root.themeName || "default"
      var force = root.queuedForce
      root.queuedTheme = ""
      root.queuedForce = false
      root.generatePack(theme, force)
    }
  }

  Timer {
    id: audioCooldownTimer
    interval: 10000
    repeat: false
    onTriggered: root.audioCoolingDown = false
  }

  Timer {
    id: audioProbeTimeout
    interval: 2000
    repeat: false
    onTriggered: root.enterAudioCooldown("default audio sink probe timed out")
  }

  Timer {
    id: playerWarmupTimeout
    interval: 5000
    repeat: false
    onTriggered: root.enterAudioCooldown("preloaded sounds did not become ready")
  }

  Instantiator {
    id: players
    active: root.playersActive
    asynchronous: false
    model: root.playerModel

    delegate: SoundEffect {
      required property string modelData
      readonly property string eventName: modelData
      source: root.playersActive ? Sounds.fileUrl(root.soundPath(eventName)) : ""
      volume: root.volume

      onStatusChanged: {
        if (status === SoundEffect.Error) {
          if (root.playersActive)
            root.enterAudioCooldown("sound effect error")
        } else {
          root.refreshPlayerReadiness()
        }
      }

      Component.onCompleted: Qt.callLater(root.refreshPlayerReadiness)
      Component.onDestruction: {
        if (playing)
          stop()
        source = ""
      }
    }

    onObjectAdded: function(index, object) { Qt.callLater(root.refreshPlayerReadiness) }
    onObjectRemoved: function(index, object) { Qt.callLater(root.refreshPlayerReadiness) }
  }

  Process {
    id: audioProbeProcess
    stdout: StdioCollector {
      waitForEnd: true
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(exitCode) {
      audioProbeTimeout.stop()
      if (!root.audioProbeAllowed)
        return
      if (exitCode === 0) {
        root.audioSinkAvailable = true
      } else {
        root.enterAudioCooldown("no usable default audio sink")
      }
    }
  }

  Process {
    id: generateProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.playbackEnabled
            && root.generatingTheme === root.themeName
            && root.generatingPack === (root.config.pack || ""))
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
    id: barToggleStateFile
    path: root.barToggleStatePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.barToggleAlreadyPlaced = String(text() || "").trim() !== ""
      root.barToggleStateLoaded = true
      root.ensureBarToggle()
    }
    onLoadFailed: function() {
      root.barToggleAlreadyPlaced = false
      root.barToggleStateLoaded = true
      root.ensureBarToggle()
    }
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
    target: Quickshell
    function onScreensChanged() { root.refreshRealScreens() }
  }

  Connections {
    target: Hyprland
    enabled: root.eventListeningEnabled
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Component.onCompleted: {
    root.refreshRealScreens()
    Qt.callLater(root.ensureBarToggle)
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
      root.writeEnabled(!root.playbackEnabled)
      return root.playbackEnabled ? "on" : "off"
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
      if (!root.playbackEnabled)
        return "disabled"
      root.scheduleGenerate(root.themeName, true)
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
