import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// hchat monitor: a chat icon with the number of unread DMs and @mentions for
// the website, game and main agents, and a popup with the newest messages per
// agent and whether hchat-relay is alive.
//
// Read-only and local: hchat_bar.py reads what hchat-relay already wrote to
// ~/.hchat/inbox/ and never connects to the hchat server (too many connections
// get the address suspended for an hour). Agents answer for themselves, so
// there is no send button. Its read position is its own ("bar"); the agents'
// read positions are never touched. Closing the popup marks what it showed as
// read for the bar.
//
// Click a message to copy its id (for `hchat get ID`).
Panel {
  id: root
  moduleName: "xmilon.hchat"
  ipcTarget: "xmilon.hchat"

  readonly property string helper: String(Qt.resolvedUrl("hchat_bar.py")).replace(/^file:\/\//, "")
  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color hot: Commons.Color.urgent !== undefined ? Commons.Color.urgent : "#e05252"

  property var info: ({ relay: { alive: true, age: 0 }, agents: [], unread: 0 })
  property string copiedId: ""
  readonly property bool relayAlive: !!(info.relay && info.relay.alive)
  property real now: Date.now() / 1000

  implicitWidth: label.implicitWidth + Style.space(14)
  implicitHeight: bar ? bar.barSize : 26

  function ago(t) {
    var s = Math.max(0, now - Number(t || 0))
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  // Local file reads only, every 3 seconds (a fraction of a millisecond each).
  Process {
    id: statusProc
    command: ["python3", "-I", root.helper, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var v = JSON.parse(text)
          if (v && v.agents) root.info = v
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.now = Date.now() / 1000
      if (!statusProc.running) statusProc.running = true
    }
  }

  Process { id: readProc }
  function markRead() {
    readProc.command = ["python3", "-I", root.helper, "read", "website", "game", "main"]
    readProc.running = true
  }
  onOpenedChanged: {
    if (opened) { now = Date.now() / 1000; statusProc.running = true }
    else if (info.unread > 0) { markRead(); refreshAfterRead.restart() }
  }
  Timer { id: refreshAfterRead; interval: 300; onTriggered: statusProc.running = true }

  function copyId(id) {
    Quickshell.execDetached(["wl-copy", "--", String(id)])
    copiedId = String(id)
    copiedTimer.restart()
  }
  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedId = "" }

  // ------------------------------------------------------------- bar

  Row {
    id: label
    anchors.centerIn: parent
    spacing: Style.space(4)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰭹"
      color: root.info.unread > 0 ? root.accent : root.barForeground
      opacity: root.relayAlive ? 1 : 0.45
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.icon
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.info.unread > 0
      textFormat: Text.PlainText
      text: root.info.unread > 99 ? "99+" : String(root.info.unread)
      color: root.accent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    // Relay down: a small red dot.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.relayAlive
      width: Style.space(5); height: width; radius: width / 2
      color: root.hot
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.relayAlive
                 ? (root.info.unread > 0 ? root.info.unread + " unread on hchat" : "hchat: nothing unread")
                 : "hchat relay is not running")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    hoverEnabled: true
  }

  // ------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: Item {
      id: hbody
      implicitHeight: col.implicitHeight
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      // Pops in when the popup opens: slides down, grows and bounces a little.
      property real popT: 1
      opacity: Math.min(1, popT * 1.4)
      transform: [
        Scale { origin.x: hbody.width / 2; origin.y: 0; xScale: 0.94 + 0.06 * hbody.popT; yScale: 0.9 + 0.1 * hbody.popT },
        Translate { y: -12 * (1 - hbody.popT) }
      ]
      NumberAnimation on popT { id: popIn; from: 0; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6; running: false }
      Connections { target: root; function onOpenedChanged() { if (root.opened) popIn.restart() } }
      Component.onCompleted: if (root.opened) popIn.restart()

      // Scrolls when the messages don't fit the popup.
      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

      ColumnLayout {
        id: col
        width: scroller.width
        spacing: Style.space(10)

        // Header: title and relay health.
        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "hchat"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Rectangle {
            width: Style.space(7); height: width; radius: width / 2
            color: root.relayAlive ? "#5fb36b" : root.hot
          }
          Text {
            textFormat: Text.PlainText
            text: root.relayAlive ? "relay alive · " + root.info.relay.age + "s ago"
                : (root.info.relay && root.info.relay.age !== null ? "relay stale · " + root.info.relay.age + "s" : "relay not running")
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: root.info.agents

          ColumnLayout {
            id: agentBlock
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(4)

            RowLayout {
              Layout.fillWidth: true
              Text {
                textFormat: Text.PlainText
                text: "@xmilon/" + agentBlock.modelData.name
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Rectangle {
                visible: agentBlock.modelData.unread > 0
                radius: height / 2
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                implicitWidth: unreadText.implicitWidth + Style.space(12)
                implicitHeight: unreadText.implicitHeight + Style.space(4)
                Text {
                  id: unreadText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: agentBlock.modelData.unread + " new"
                  color: root.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
              Item { Layout.fillWidth: true }
            }

            Text {
              visible: agentBlock.modelData.recent.length === 0
              textFormat: Text.PlainText
              text: "Nothing yet"
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: agentBlock.modelData.recent.slice(0, agentBlock.modelData.unread > 3 ? Math.min(8, agentBlock.modelData.unread) : 3)

              Rectangle {
                id: msg
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: msgCol.implicitHeight + Style.space(12)
                radius: Style.space(8)
                color: msgHit.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.09)
                     : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                border.width: 1
                border.color: msg.modelData.unread ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
                                                   : "transparent"

                ColumnLayout {
                  id: msgCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(6)
                  spacing: Style.space(2)
                  RowLayout {
                    Layout.fillWidth: true
                    Text {
                      Layout.fillWidth: true
                      textFormat: Text.PlainText
                      text: "@" + msg.modelData.from + (String(msg.modelData.to).indexOf("#") === 0 ? "  in " + msg.modelData.to : "")
                            + (msg.modelData.kind && msg.modelData.kind !== "msg" ? "  · " + msg.modelData.kind : "")
                      elide: Text.ElideRight
                      color: root.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: root.copiedId === String(msg.modelData.id) ? "✓ copied" : "id:" + msg.modelData.id + " · " + root.ago(msg.modelData.at)
                      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: msg.modelData.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: msgHit
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.copyId(msg.modelData.id)
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: "Click a message to copy its id  ·  read-only: agents answer for themselves"
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      }
    }
  }
}
