import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Plays key sounds whenever Hyprland reports a keypress or release through
// the global shortcuts in hypr/thock.lua. No device is opened and no key is
// identified: each shortcut only says which sound group to play.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  // Sound profiles built by tools/make-sounds.py into sounds/<id>/.
  readonly property var profiles: [
    { value: "q-cream", label: "Q Cream", tooltip: "Keychron Q, creamy lubed linears: deep and smooth" },
    { value: "keychron", label: "Clacky", tooltip: "Keychron with tactile switches: bright and poppy" },
    { value: "thock", label: "Thock", tooltip: "Low, muted knock with no release sound", noUpstroke: true }
  ]

  readonly property bool enabled: prefs.enabled
  readonly property real volume: prefs.volume
  readonly property string profile: profiles.some(function(p) { return p.value === prefs.profile }) ? prefs.profile : "q-cream"
  readonly property bool upstroke: prefs.upstroke
  // Depth: 0 (brightest) to 4 (deepest). Cream: 0 (crisp) to 4 (creamiest),
  // where 1 is the profile as tuned. Every combination is a pre-built sample
  // set, since SoundEffect can't reshape a sound at runtime.
  readonly property int depthLevels: 5
  readonly property int creamLevels: 5
  readonly property int depth: clampLevel(prefs.depth, depthLevels)
  readonly property int cream: clampLevel(prefs.cream, creamLevels)
  readonly property bool hasUpstroke: !profiles.some(function(p) { return p.value === profile && p.noUpstroke })
  readonly property string soundDir: "sounds/" + profile + "/depth" + depth + "-cream" + cream + "/"

  function clampLevel(value, levels) {
    return Math.max(0, Math.min(levels - 1, Math.round(Number(value) || 0)))
  }

  function setEnabled(value) {
    prefs.enabled = !!value
  }

  function toggle() {
    setEnabled(!prefs.enabled)
  }

  function setVolume(value) {
    prefs.volume = Math.max(0.05, Math.min(1, Math.round(value * 20) / 20))
  }

  function setProfile(value) {
    prefs.profile = String(value)
  }

  function setUpstroke(value) {
    prefs.upstroke = !!value
  }

  function setDepth(value) {
    prefs.depth = clampLevel(value, depthLevels)
  }

  function setCream(value) {
    prefs.cream = clampLevel(value, creamLevels)
  }

  // A short burst so a change of profile or volume can be heard right away,
  // even while typing sounds are switched off.
  function preview() {
    previewTimer.step = 0
    previewTimer.restart()
  }

  // Random variant from a pool, skipping any still sounding so fast typing
  // layers instead of cutting the previous sound short.
  function playFrom(pool, force) {
    var ready = []
    var idle = []
    for (var i = 0; i < pool.count; i++) {
      var s = pool.objectAt(i)
      if (!s || s.status !== SoundEffect.Ready) continue
      ready.push(s)
      if (!s.playing) idle.push(s)
    }
    var choices = idle.length > 0 ? idle : ready
    if (choices.length > 0) play(choices[Math.floor(Math.random() * choices.length)], force)
  }

  function playUp(pool, sound) {
    if (!prefs.upstroke) return
    if (sound) play(sound)
    else playFrom(pool)
  }

  function play(sound, force) {
    // Profiles without upstroke samples leave those effects with no source.
    if ((!prefs.enabled && !force) || !sound || sound.status !== SoundEffect.Ready) return
    // A slight per-press level wobble keeps repeats from sounding mechanical.
    sound.volume = prefs.volume * (0.85 + Math.random() * 0.15)
    sound.play()
  }

  Timer {
    id: previewTimer
    property int step: 0
    // key down/up, key down/up, space down/up
    readonly property var script: ["key", "up", "key", "up", "space", "space-up"]
    interval: 95
    repeat: true
    onTriggered: {
      var what = script[step]
      if (what === "key") root.playFrom(keySounds, true)
      else if (what === "space") root.play(spaceSound, true)
      else if (prefs.upstroke) {
        if (what === "up") root.playFrom(upSounds, true)
        else root.play(spaceUpSound, true)
      }
      step++
      if (step >= script.length) stop()
    }
  }

  FileView {
    id: store
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/thock.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) writeAdapter()
    }

    JsonAdapter {
      id: prefs
      property bool enabled: true
      property real volume: 0.6
      property string profile: "q-cream"
      property bool upstroke: true
      property int depth: 2
      property int cream: 3
    }
  }

  Instantiator {
    id: keySounds
    model: 6
    delegate: SoundEffect {
      required property int index
      source: Qt.resolvedUrl(root.soundDir + "key" + (index + 1) + ".wav")
    }
  }

  Instantiator {
    id: upSounds
    model: 4
    delegate: SoundEffect {
      required property int index
      source: root.hasUpstroke ? Qt.resolvedUrl(root.soundDir + "up" + (index + 1) + ".wav") : ""
    }
  }

  SoundEffect { id: spaceSound; source: Qt.resolvedUrl(root.soundDir + "space.wav") }
  SoundEffect { id: spaceUpSound; source: root.hasUpstroke ? Qt.resolvedUrl(root.soundDir + "space-up.wav") : "" }
  SoundEffect { id: enterSound; source: Qt.resolvedUrl(root.soundDir + "enter.wav") }
  SoundEffect { id: backspaceSound; source: Qt.resolvedUrl(root.soundDir + "backspace.wav") }

  GlobalShortcut {
    appid: "thock"; name: "key"; description: "Thock: key"
    onPressed: root.playFrom(keySounds)
    onReleased: root.playUp(upSounds)
  }
  GlobalShortcut {
    appid: "thock"; name: "space"; description: "Thock: space"
    onPressed: root.play(spaceSound)
    onReleased: root.playUp(null, spaceUpSound)
  }
  GlobalShortcut {
    appid: "thock"; name: "enter"; description: "Thock: enter"
    onPressed: root.play(enterSound)
    onReleased: root.playUp(upSounds)
  }
  GlobalShortcut {
    appid: "thock"; name: "backspace"; description: "Thock: backspace"
    onPressed: root.play(backspaceSound)
    onReleased: root.playUp(upSounds)
  }
}
