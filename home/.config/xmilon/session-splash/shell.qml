// Loading screen between the login screen and the desktop.
// Continues the login look (same blurred wallpaper, avatar, name) and shows a
// loading bar that moves as the desktop really comes up: compositor, wallpaper,
// bar, notifications. When all are up it fills, then fades into the desktop.
// Never traps you: gives up after 25 s, and a click skips it.
// Started first thing by hypr/autostart.lua.
//
//   XMILON_SPLASH_DEMO=1 qs -n -p ~/.config/xmilon/session-splash   preview
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: shell

  readonly property string home: Quickshell.env("HOME")
  readonly property bool demo: Quickshell.env("XMILON_SPLASH_DEMO") === "1"
  readonly property string backgroundPath: "/var/lib/thyx-xmilon/background.jpg"
  readonly property string avatarPath: home + "/.config/thyx/solo.png"
  readonly property string fontFamily: "Plus Jakarta Sans"
  property string displayName: "Xmilon"

  // Milestones, in the order they normally arrive.
  readonly property var steps: [
    { key: "omarchy-background", label: "Painting your wallpaper" },
    { key: "omarchy-bar", label: "Loading the bar" },
    { key: "omarchy-notifications", label: "Starting notifications" }
  ]
  property var ready: ({})
  readonly property int readyCount: {
    var n = 0
    for (var i = 0; i < steps.length; ++i) if (ready[steps[i].key]) n++
    return n
  }
  readonly property bool allReady: readyCount === steps.length
  readonly property string status: {
    if (allReady) return "Ready"
    for (var i = 0; i < steps.length; ++i) if (!ready[steps[i].key]) return steps[i].label
    return "Starting"
  }

  // Shown progress: jumps toward each milestone and creeps toward the next one
  // while waiting, so it never looks frozen. 1.0 only once everything is up.
  property real target: 0.08 + 0.84 * readyCount / steps.length
  property real progress: 0
  property real creep: 0
  readonly property real elapsedMin: 1.4   // never flash by
  property real elapsed: 0
  property bool leaving: false
  property real level: 0

  Behavior on level { NumberAnimation { duration: shell.leaving ? 750 : 380; easing.type: Easing.OutCubic } }

  Component.onCompleted: {
    level = 1
    nameFile.reload()
  }

  FileView {
    id: nameFile
    path: shell.home + "/.config/thyx/settings.json"
    printErrors: false
    onLoaded: {
      try {
        var t = JSON.parse(text()).title
        if (t) shell.displayName = String(t)
      } catch (e) {}
    }
  }

  Timer {
    interval: 16; running: !shell.leaving; repeat: true
    onTriggered: {
      shell.elapsed += 0.016
      var goal = shell.allReady ? 1.0 : Math.min(shell.target + 0.1, shell.target + shell.creep)
      shell.creep = Math.min(0.1, shell.creep + 0.0009)
      shell.progress += (goal - shell.progress) * (shell.allReady ? 0.12 : 0.06)
      if (shell.allReady && shell.progress > 0.995 && shell.elapsed > shell.elapsedMin) shell.finish()
      if (shell.elapsed > 25) shell.finish()
    }
  }
  onReadyCountChanged: creep = 0

  function finish() {
    if (leaving) return
    progress = 1
    leaving = true
    level = 0
    quitTimer.start()
  }
  Timer { id: quitTimer; interval: 850; onTriggered: Qt.quit() }

  // Watch the desktop's layers appear.
  Process {
    id: probe
    command: ["hyprctl", "layers", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = {}
        try {
          var mons = JSON.parse(text)
          for (var m in mons) {
            var levels = mons[m].levels || {}
            for (var l in levels) for (var i = 0; i < levels[l].length; ++i) found[levels[l][i].namespace] = true
          }
        } catch (e) {}
        var next = {}
        for (var j = 0; j < shell.steps.length; ++j) next[shell.steps[j].key] = !!found[shell.steps[j].key] || !!shell.ready[shell.steps[j].key]
        shell.ready = next
      }
    }
  }
  Timer {
    interval: 250; running: !shell.demo && !shell.allReady && !shell.leaving; repeat: true; triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }

  // Preview mode: fake milestones.
  Timer {
    interval: 1300; running: shell.demo && !shell.allReady; repeat: true
    onTriggered: {
      var next = {}
      var done = false
      for (var i = 0; i < shell.steps.length; ++i) {
        var k = shell.steps[i].key
        next[k] = !!shell.ready[k] || !done
        if (!shell.ready[k]) done = true
      }
      shell.ready = next
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "xmilon-session-splash"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property real s: Math.max(0.75, Math.min(width / 1920, height / 1080))

      Item {
        anchors.fill: parent
        opacity: shell.level

        // Same backdrop as the login screen.
        Rectangle { anchors.fill: parent; color: "#0b1118" }
        Image {
          id: wallpaper
          anchors.fill: parent
          source: "file://" + shell.backgroundPath
          sourceSize: Qt.size(Math.round(panel.width / 2), Math.round(panel.height / 2))
          fillMode: Image.PreserveAspectCrop
          cache: false
          visible: false
        }
        MultiEffect {
          anchors.fill: parent
          source: wallpaper
          visible: wallpaper.status === Image.Ready
          autoPaddingEnabled: false
          blurEnabled: true
          blur: 1.0
          blurMax: 64
        }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.28 + 0.12 * shell.progress }

        Column {
          id: card
          anchors.centerIn: parent
          anchors.verticalCenterOffset: panel.height * 0.02
          spacing: 16 * panel.s
          scale: shell.leaving ? 1.04 : 1
          Behavior on scale { NumberAnimation { duration: 750; easing.type: Easing.OutCubic } }

          // Avatar with a slow glowing ring.
          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 112 * panel.s
            height: width
            Rectangle {
              anchors.centerIn: parent
              width: parent.width + 18 * panel.s
              height: width
              radius: width / 2
              color: "transparent"
              border.width: 2
              border.color: Qt.rgba(1, 1, 1, 0.5)
              SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 0.15; to: 0.7; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.7; to: 0.15; duration: 1100; easing.type: Easing.InOutSine }
              }
            }
            Image {
              id: avatar
              anchors.fill: parent
              source: "file://" + shell.avatarPath
              sourceSize: Qt.size(256, 256)
              fillMode: Image.PreserveAspectCrop
              visible: false
              layer.enabled: true
            }
            Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
            MultiEffect {
              anchors.fill: parent
              source: avatar
              autoPaddingEnabled: false
              maskEnabled: true
              maskSource: avatarMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1.0
            }
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              border.color: Qt.rgba(1, 1, 1, 0.55)
              border.width: 2
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Welcome back, " + shell.displayName
            color: "#f2f5f8"
            font.family: shell.fontFamily
            font.pixelSize: 26 * panel.s
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
          }

          Item { width: 1; height: 6 * panel.s }

          // Loading bar: glass track, gradient fill with a moving shine.
          Item {
            id: bar
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300 * panel.s
            height: 6 * panel.s

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.14)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.1)
            }
            // Glow under the fill.
            Rectangle {
              x: 0
              anchors.verticalCenter: parent.verticalCenter
              width: fill.width
              height: parent.height * 3
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.10)
              layer.enabled: true
              layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 24 }
            }
            Item {
              id: fill
              height: parent.height
              width: Math.max(height, parent.width * shell.progress)
              clip: true
              Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.55) }
                  GradientStop { position: 1.0; color: "white" }
                }
              }
              Rectangle {
                id: shine
                width: 70 * panel.s
                height: parent.height
                radius: height / 2
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                  GradientStop { position: 0.5; color: Qt.rgba(0.75, 0.85, 1, 0.9) }
                  GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
                NumberAnimation on x {
                  from: -70 * panel.s; to: bar.width
                  duration: 1300; loops: Animation.Infinite
                  easing.type: Easing.InOutQuad
                }
              }
            }
          }

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: bar.width
            height: 18 * panel.s
            Text {
              id: statusText
              anchors.left: parent.left
              text: shell.status + "…"
              color: Qt.rgba(1, 1, 1, 0.7)
              font.family: shell.fontFamily
              font.pixelSize: 13 * panel.s
              textFormat: Text.PlainText
              Behavior on text {
                SequentialAnimation {
                  NumberAnimation { target: statusText; property: "opacity"; to: 0; duration: 120 }
                  PropertyAction {}
                  NumberAnimation { target: statusText; property: "opacity"; to: 1; duration: 180 }
                }
              }
            }
            Text {
              anchors.right: parent.right
              text: Math.round(shell.progress * 100) + "%"
              color: Qt.rgba(1, 1, 1, 0.5)
              font.family: shell.fontFamily
              font.pixelSize: 13 * panel.s
              font.features: { "tnum": 1 }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: shell.finish()
        }
      }
    }
  }
}
