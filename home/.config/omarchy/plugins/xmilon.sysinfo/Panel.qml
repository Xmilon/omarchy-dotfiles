import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// System Info: "CPU% · temp · RAM" in the bar, and a popup with
// CPU, GPU (nvidia-smi, only polled while open), memory, swap, disk and uptime.
Panel {
  id: root
  moduleName: "xmilon.sysinfo"
  ipcTarget: "xmilon.sysinfo"

  readonly property string helper: String(Qt.resolvedUrl("sysinfo.py")).replace(/^file:\/\//, "")
  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color hot: Commons.Color.urgent !== undefined ? Commons.Color.urgent : "#e05252"

  property var info: ({})
  property var gpu: ({})

  implicitWidth: label.implicitWidth + Style.space(14)
  implicitHeight: bar ? bar.barSize : 26

  function gib(bytes) { return (bytes / 1073741824).toFixed(1) + " GiB" }
  function pct(used, total) { return total > 0 ? used / total : 0 }
  function uptimeText(s) {
    var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
    return (d > 0 ? d + "d " : "") + (h > 0 || d > 0 ? h + "h " : "") + m + "m"
  }
  function levelColor(fraction) {
    return fraction >= 0.9 ? root.hot : root.accent
  }

  // One long-running sampler; prints a JSON line every 2 seconds.
  Process {
    id: stream
    running: true
    command: ["python3", "-I", root.helper, "stream", "2"]
    stdout: SplitParser {
      onRead: function(line) {
        try { root.info = JSON.parse(line) } catch (e) {}
      }
    }
    onRunningChanged: if (!running) restartTimer.start()
  }
  Timer { id: restartTimer; interval: 5000; onTriggered: stream.running = true }

  // GPU only while the popup is open (nvidia-smi is the expensive part).
  Process {
    id: gpuProc
    command: ["python3", "-I", root.helper, "gpu"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.gpu = JSON.parse(text) } catch (e) {} }
    }
  }
  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: root.opened
    onTriggered: if (!gpuProc.running) gpuProc.running = true
  }

  // ------------------------------------------------------------- bar label

  // Compact: "7%  60°  9.7G" with small dimmed icons in front of each value.
  Row {
    id: label
    anchors.centerIn: parent
    spacing: Style.space(7)
    readonly property var i: root.info

    Repeater {
      model: [
        { icon: "󰍛", value: label.i.cpu === undefined ? "…" : label.i.cpu + "%" },
        { icon: "󰔏", value: label.i.temp === null || label.i.temp === undefined ? "" : label.i.temp + "°" },
        { icon: "󰘚", value: label.i.memUsed === undefined ? "" : (label.i.memUsed / 1073741824).toFixed(1) + "G" }
      ]

      Row {
        required property var modelData
        visible: modelData.value !== ""
        spacing: Style.space(2)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.icon
          color: root.barForeground
          opacity: 0.55
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.value
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  MouseArea {
    id: hit
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
  }

  // ------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: Item {
      implicitHeight: col.implicitHeight
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        // CPU
        StatBlock {
          icon: "󰍛"
          title: "CPU"
          subtitle: (root.info.cpuModel || "") + (root.info.cores ? "  ·  " + root.info.cores + " threads" : "")
          value: (root.info.cpu !== undefined ? root.info.cpu + "%" : "…")
                 + (root.info.temp !== null && root.info.temp !== undefined ? "   " + root.info.temp + "°C" : "")
          fraction: (root.info.cpu || 0) / 100
        }

        // GPU
        StatBlock {
          visible: root.gpu.available === true
          icon: "󰢮"
          title: "GPU"
          subtitle: (root.gpu.name || "") + (root.gpu.power ? "  ·  " + Math.round(root.gpu.power) + " W" : "")
          value: (root.gpu.util !== null && root.gpu.util !== undefined ? Math.round(root.gpu.util) + "%" : "…")
                 + (root.gpu.temp ? "   " + Math.round(root.gpu.temp) + "°C" : "")
          fraction: (root.gpu.util || 0) / 100
        }
        StatBlock {
          visible: root.gpu.available === true
          icon: "󰾆"
          title: "VRAM"
          subtitle: ""
          value: root.gpu.memTotal ? (root.gpu.memUsed / 1024).toFixed(1) + " / " + (root.gpu.memTotal / 1024).toFixed(0) + " GiB" : "…"
          fraction: root.pct(root.gpu.memUsed || 0, root.gpu.memTotal || 0)
        }

        // Memory
        StatBlock {
          icon: "󰘚"
          title: "Memory"
          subtitle: root.info.swapTotal ? "Swap " + root.gib(root.info.swapUsed) + " / " + root.gib(root.info.swapTotal) : ""
          value: root.info.memTotal ? root.gib(root.info.memUsed) + " / " + root.gib(root.info.memTotal) : "…"
          fraction: root.pct(root.info.memUsed || 0, root.info.memTotal || 0)
        }

        // Disk
        StatBlock {
          icon: "󰋊"
          title: "Disk  /"
          subtitle: ""
          value: root.info.diskTotal ? root.gib(root.info.diskUsed) + " / " + root.gib(root.info.diskTotal) : "…"
          fraction: root.pct(root.info.diskUsed || 0, root.info.diskTotal || 0)
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
        }

        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "󰔟  Up " + (root.info.uptime ? root.uptimeText(root.info.uptime) : "…")
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            textFormat: Text.PlainText
            text: root.info.load ? "Load " + root.info.load.join("  ") : ""
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Button {
          Layout.fillWidth: true
          text: "Open btop"
          iconText: "󰄪"
          foreground: root.fg
          onClicked: {
            root.close()
            Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
          }
        }
      }
    }
  }

  // A labelled row with a value and a thin usage bar.
  component StatBlock: ColumnLayout {
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string value: ""
    property real fraction: 0
    Layout.fillWidth: true
    spacing: Style.space(4)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        text: icon
        color: root.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
      Text {
        textFormat: Text.PlainText
        text: title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Item { Layout.fillWidth: true }
      Text {
        textFormat: Text.PlainText
        text: value
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }
    }
    Rectangle {
      Layout.fillWidth: true
      height: Style.space(5)
      radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, fraction))
        height: parent.height
        radius: parent.radius
        color: root.levelColor(fraction)
        Behavior on width { NumberAnimation { duration: Style.duration(250); easing.type: Easing.OutCubic } }
      }
    }
    Text {
      visible: subtitle !== ""
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: subtitle
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
