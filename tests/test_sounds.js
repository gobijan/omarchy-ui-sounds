#!/usr/bin/env node

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const root = path.resolve(__dirname, "..")
const soundsPath = path.join(root, "Sounds.js")
const servicePath = path.join(root, "Service.qml")
const source = fs.readFileSync(soundsPath, "utf8").replace(/^\.pragma library\s*/, "")
const Sounds = { console }
vm.createContext(Sounds)
vm.runInContext(source, Sounds, { filename: soundsPath })

function event(name, data) {
  return { name, data }
}

const ignored = Sounds.newIgnoredWindowTracker()

assert.equal(
  Sounds.soundForEvent(event("openwindow", "0x1,1,org.omarchy.screensaver,Screensaver"), ignored),
  ""
)
assert.equal(Sounds.ignoredWindowCount(ignored), 1)
assert.equal(Sounds.soundForEvent(event("changefloatingmode", "0x1,1"), ignored), "")
assert.equal(Sounds.soundForEvent(event("minimized", "0x1,1"), ignored), "")
assert.equal(Sounds.soundForEvent(event("closewindow", "0x1"), ignored), "")
assert.equal(Sounds.ignoredWindowCount(ignored), 0)

assert.equal(
  Sounds.soundForEvent(event("openwindow", "0x2,1,xdph-picker,Portal"), ignored),
  ""
)
assert.equal(Sounds.soundForEvent(event("closewindow", "0x2"), ignored), "")

assert.equal(
  Sounds.soundForEvent(event("openwindow", "0x3,1,foot,Terminal"), ignored),
  "openwindow"
)

const healthyState = {
  configLoaded: true,
  enabled: true,
  eventMuted: false,
  startupGraceComplete: true,
  screens: [{ name: "DP-1", width: 2560, height: 1440 }],
  sessionLocked: false,
  sessionIdle: false,
  chromeActive: false,
  audioCoolingDown: false,
  audioAvailable: true,
  playersReady: true,
  requireReady: false,
  effectReady: false,
  effectPlaying: false
}

const completeIndex = {}
for (const name of Sounds.EVENT_NAMES)
  completeIndex[name] = `/sounds/${name}.wav`
assert.equal(Sounds.hasAllSounds(completeIndex, Sounds.EVENT_NAMES), true)
assert.equal(Sounds.hasAllSounds({ ...completeIndex, openwindow: "" }, Sounds.EVENT_NAMES), false)

const playerModel = Sounds.playerModel(Sounds.EVENT_NAMES)
assert.equal(playerModel.filter(name => name === "openwindow").length, 4)
assert.equal(playerModel.filter(name => name === "closewindow").length, 4)
assert.equal(playerModel.filter(name => name === "workspace").length, 1)
assert.equal(playerModel.length, 16)

assert.equal(Sounds.canPlay(healthyState), true)
assert.equal(Sounds.canPlay({ ...healthyState, realScreenAvailable: true, screens: [] }), true)
assert.equal(Sounds.canPlay({ ...healthyState, realScreenAvailable: false }), false)
assert.equal(Sounds.canPlay({ ...healthyState, screens: [{ name: "", width: 1920, height: 1080 }] }), false)
assert.equal(Sounds.canPlay({ ...healthyState, screens: [{ name: "FALLBACK", width: 0, height: 0 }] }), false)
assert.equal(Sounds.canPlay({ ...healthyState, screens: [{ name: "FALLBACK", width: 1920, height: 1080 }] }), false)
assert.equal(Sounds.canPlay({ ...healthyState, enabled: false }), false)
assert.equal(Sounds.canPlay({ ...healthyState, configLoaded: false }), false)
assert.equal(Sounds.canPlay({ ...healthyState, sessionLocked: true }), false)
assert.equal(Sounds.canPlay({ ...healthyState, sessionIdle: true }), false)
assert.equal(Sounds.canPlay({ ...healthyState, audioCoolingDown: true }), false)
assert.equal(Sounds.canPlay({ ...healthyState, audioAvailable: false }), false)
assert.equal(Sounds.canPlay({ ...healthyState, playersReady: false }), false)
assert.equal(Sounds.canPlay({ ...healthyState, playersReady: false, requirePlayers: false }), true)
assert.equal(Sounds.canPlay({ ...healthyState, requireReady: true, effectReady: false }), false)
assert.equal(Sounds.canPlay({ ...healthyState, requireReady: true, effectReady: true }), true)
assert.equal(Sounds.canPlay({ ...healthyState, requireReady: true, effectReady: true, effectPlaying: true }), false)

// Lifecycle guards are intentionally checked in the QML source because the
// repository has no QML test harness. Together with canPlay(), these assertions
// prevent disabled playback from retaining a handler, player, or bound source.
const service = fs.readFileSync(servicePath, "utf8")
assert.match(service, /readonly property bool playbackEnabled: configLoaded && config\.enabled === true/)
assert.match(service, /readonly property bool eventListeningEnabled: root\.playbackEnabled && root\.realScreensAvailable/)
assert.match(service, /Connections\s*{\s*target: Hyprland\s*enabled: root\.eventListeningEnabled/s)
assert.match(service, /Instantiator\s*{\s*id: players\s*active: root\.playersActive/s)
assert.match(service, /SoundEffect\s*{[\s\S]*?source: root\.playersActive \?/)
assert.match(service, /readonly property bool playbackReady: Sounds\.canPlay/)
assert.match(service, /if \(root\.canPlay\(event, fx\)\)/)
assert.match(service, /fx\.status === SoundEffect\.Ready && !fx\.playing/)
assert.match(service, /if \(root\.playersActive\)\s*root\.enterAudioCooldown\("sound effect error"\)/)
assert.match(service, /if \(firstFailure\) \{[\s\S]*?audioCooldownTimer\.restart\(\)/)
assert.match(service, /generatingTheme === root\.themeName/)
assert.match(service, /generatingPack === \(root\.config\.pack \|\| ""\)/)
assert.doesNotMatch(service, /root\.canPlay\(name, null\)/)
assert.doesNotMatch(service, /id: playerLoader/)
assert.doesNotMatch(service, /requireReady:\s*false/)

console.log("Sounds.js hardening tests passed")
