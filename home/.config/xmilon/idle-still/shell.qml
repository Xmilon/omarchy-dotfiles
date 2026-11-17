// Still screen shown after the Omarchy screensaver has animated for a while:
// the current wallpaper (videos play, muted) at low brightness with a clock on
// top. Fades in over the screensaver; any mouse movement or key fades it out
// and closes the screensaver underneath. Started by xmilon-screensaver-guard.
//
//   qs -p ~/.config/xmilon/idle-still                 run it by hand
//   qs ipc -p ~/.config/xmilon/idle-still call still dismiss
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: shell

  readonly property string home: Quickshell.env("HOME")
  readonly property string backgroundLink: home + "/.local/state/omarchy/current/background"
  property string background: ""
  // Same video list as Omarchy's Util.isVideoPath; GIF/WebP may be animated.
  readonly property bool isVideo: /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(background)
  readonly property bool isAnimated: /\.(gif|webp)$/i.test(background)
  property bool leaving: false
  property real level: 0          // 0 = invisible, 1 = fully shown
  property date now: new Date()

  Behavior on level { NumberAnimation { duration: shell.leaving ? 700 : 1600; easing.type: Easing.InOutQuad } }

  Component.onCompleted: resolve.running = true

  function dismiss() {
    if (leaving) return
    leaving = true
    // Close the screensaver underneath first, so the fade reveals the desktop.
    Quickshell.execDetached(["bash", "-c",
      "pkill -CONT -x ttfx; pkill -x ttfx; pkill -f '[o]rg.omarchy.screensaver'"])
    level = 0
    quitTimer.start()
  }

  Timer { id: quitTimer; interval: 750; onTriggered: Qt.quit() }
  Timer { interval: 1000; running: true; repeat: true; onTriggered: shell.now = new Date() }

  Process {
    id: resolve
    command: ["readlink", "-f", "--", shell.backgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        shell.background = text.trim()
        shell.level = 1
      }
    }
  }

  IpcHandler {
    target: "still"
    function dismiss(): void { shell.dismiss() }
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
      WlrLayershell.namespace: "xmilon-idle-still"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      readonly property real s: Math.max(0.75, Math.min(width / 1920, height / 1080))

      Item {
        id: stage
        anchors.fill: parent
        opacity: shell.level
        focus: true
        Keys.onPressed: function(event) { event.accepted = true; shell.dismiss() }

        Rectangle { anchors.fill: parent; color: "black" }

        // Wallpaper with a very slow drift so it feels alive (and spares OLEDs).
        Item {
          anchors.fill: parent
          clip: true
          Image {
            id: still
            anchors.fill: parent
            visible: !shell.isVideo && !shell.isAnimated && shell.background !== ""
            source: visible ? "file://" + shell.background : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(panel.width, panel.height)
            asynchronous: true
            transformOrigin: Item.Center
            SequentialAnimation on scale {
              running: still.visible
              loops: Animation.Infinite
              NumberAnimation { from: 1.0; to: 1.07; duration: 45000; easing.type: Easing.InOutSine }
              NumberAnimation { from: 1.07; to: 1.0; duration: 45000; easing.type: Easing.InOutSine }
            }
          }
          AnimatedImage {
            id: animated
            anchors.fill: parent
            visible: shell.isAnimated
            source: visible ? "file://" + shell.background : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            playing: visible
          }
          Video {
            anchors.fill: parent
            visible: shell.isVideo
            source: visible ? "file://" + shell.background : ""
            fillMode: VideoOutput.PreserveAspectCrop
            loops: MediaPlayer.Infinite
            muted: true
            autoPlay: true
          }
        }

        // Low brightness.
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.62 }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: "#99000000" }
          }
        }

        // Clock, drifting a little each minute so nothing burns in.
        Column {
          id: clock
          spacing: 6 * panel.s
          property real driftX: 0
          property real driftY: 0
          x: (parent.width - width) / 2 + driftX
          y: (parent.height - height) / 2 - parent.height * 0.04 + driftY
          Behavior on driftX { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
          Behavior on driftY { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
          Timer {
            interval: 60000; running: true; repeat: true
            onTriggered: {
              clock.driftX = (Math.random() - 0.5) * panel.width * 0.12
              clock.driftY = (Math.random() - 0.5) * panel.height * 0.10
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            Text {
              text: Qt.formatDateTime(shell.now, "HH")
              color: "#f4f6f8"
              font.family: "Plus Jakarta Sans"
              font.pixelSize: 168 * panel.s
              font.weight: Font.ExtraLight
            }
            Text {
              text: ":"
              color: "#f4f6f8"
              font.family: "Plus Jakarta Sans"
              font.pixelSize: 168 * panel.s
              font.weight: Font.ExtraLight
              // Colon breathes once a second.
              SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 0.9; to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.25; to: 0.9; duration: 500; easing.type: Easing.InOutSine }
              }
            }
            Text {
              text: Qt.formatDateTime(shell.now, "mm")
              color: "#f4f6f8"
              font.family: "Plus Jakarta Sans"
              font.pixelSize: 168 * panel.s
              font.weight: Font.ExtraLight
            }
          }

          // Seconds as a thin line filling across the clock's width.
          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * panel.s
            height: 2
            Rectangle { anchors.fill: parent; radius: 1; color: Qt.rgba(1, 1, 1, 0.15) }
            Rectangle {
              height: parent.height
              radius: 1
              color: Qt.rgba(1, 1, 1, 0.7)
              width: parent.width * shell.now.getSeconds() / 59
              Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 10 * panel.s
            text: Qt.formatDateTime(shell.now, "dddd · d MMMM").toUpperCase()
            color: Qt.rgba(1, 1, 1, 0.62)
            font.family: "Plus Jakarta Sans"
            font.pixelSize: 15 * panel.s
            font.letterSpacing: 5 * panel.s
          }
        }

        // Mouse: ignore the first sample (cursor already there), then any
        // real movement dismisses.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          property point origin: Qt.point(-1, -1)
          onPositionChanged: function(mouse) {
            if (origin.x < 0) { origin = Qt.point(mouse.x, mouse.y); return }
            if (Math.abs(mouse.x - origin.x) + Math.abs(mouse.y - origin.y) > 12) shell.dismiss()
          }
          onPressed: shell.dismiss()
          onWheel: shell.dismiss()
        }
      }
    }
  }
}
