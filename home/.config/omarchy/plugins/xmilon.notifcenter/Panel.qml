import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Notification Center: a bell in the bar with an unread count. Clicking it
// opens the day's notifications (Omarchy keeps 24 h / 100 of them), newest
// first, with Do Not Disturb, Clear all, and per-app mute.
//
// Reads Omarchy's own files in ~/.local/state/omarchy/notifications/ and never
// writes them: "clear" and "dismiss" are remembered here, in
// ~/.local/state/xmilon/notifcenter.json. Muted apps live in
// ~/.config/xmilon/notifications-muted.json, which Omarchy's notification
// service reads through the omarchy-notif-mute-patch.
Panel {
  id: root
  moduleName: "xmilon.notifcenter"
  ipcTarget: "xmilon.notifcenter"

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string home: Quickshell.env("HOME")
  readonly property string omarchyDir: home + "/.local/state/omarchy/notifications"

  property var history: []
  property var live: []
  property bool dnd: false
  property var mutedApps: []
  // Own state: when the list was last looked at / cleared, and dismissed keys.
  property real lastSeen: 0
  property real clearedAt: 0
  property var hidden: []
  property bool stateLoaded: false
  property real now: Date.now() / 1000

  implicitWidth: bell.implicitWidth + Style.space(14)
  implicitHeight: bar ? bar.barSize : 26

  // ------------------------------------------------------------- data

  function parseList(text) {
    try {
      var v = JSON.parse(text)
      return Array.isArray(v) ? v : []
    } catch (e) { return [] }
  }

  function isMuted(app) { return mutedApps.indexOf(String(app || "").toLowerCase()) >= 0 }

  // Everything to list, newest first: on screen now, then history.
  readonly property var entries: {
    var seen = {}, out = []
    var all = live.slice().reverse().map(function(e) { return Object.assign({ onScreen: true }, e) }).concat(history)
    for (var i = 0; i < all.length; i++) {
      var e = all[i]
      if (!e || !e.key || seen[e.key]) continue
      seen[e.key] = true
      var t = Number(e.ts) || Number(e.closed_ts) || 0
      if (t <= clearedAt || hidden.indexOf(e.key) >= 0) continue
      out.push(Object.assign({}, e, { time: t }))
    }
    out.sort(function(a, b) { return b.time - a.time })
    return out
  }

  readonly property int unread: {
    var n = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].time > lastSeen && entries[i].closed_reason !== "muted" && !entries[i].onScreen) n++
    return n
  }

  // Apps that sent something recently, for the mute list.
  readonly property var knownApps: {
    var seen = {}, out = []
    var all = live.concat(history)
    for (var i = 0; i < all.length; i++) {
      var a = String(all[i].app || "")
      if (!a || a === "omarchy-action" || seen[a.toLowerCase()]) continue
      seen[a.toLowerCase()] = true
      out.push(a)
    }
    for (var j = 0; j < mutedApps.length; j++) if (!seen[mutedApps[j]]) out.push(mutedApps[j])
    return out.sort(function(x, y) { return x.toLowerCase().localeCompare(y.toLowerCase()) })
  }

  function ago(t) {
    var s = Math.max(0, now - t)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  function iconFor(name) {
    name = String(name || "")
    if (!name) return ""
    if (name.indexOf("/") === 0) return "file://" + name
    if (name.indexOf("file://") === 0) return name
    return Quickshell.iconPath(name, true) || ""
  }

  function saveState() {
    stateFile.setText(JSON.stringify({ lastSeen: lastSeen, clearedAt: clearedAt, hidden: hidden.slice(-300) }))
  }

  function markSeen() {
    lastSeen = Date.now() / 1000
    saveState()
  }

  function clearAll() {
    clearedAt = Date.now() / 1000
    hidden = []
    saveState()
    Quickshell.execDetached(["omarchy-shell", "notifications", "dismissAll"])
  }

  function dismiss(key) {
    hidden = hidden.concat([key])
    saveState()
  }

  function setMuted(app, on) {
    var a = String(app).toLowerCase()
    var list = mutedApps.filter(function(x) { return x !== a })
    if (on) list.push(a)
    mutedApps = list
    mutedFile.setText(JSON.stringify({ apps: list }, null, 2) + "\n")
  }

  function toggleDnd() {
    dnd = !dnd
    Quickshell.execDetached(["omarchy", "toggle", "notification", "silencing"])
  }

  onOpenedChanged: {
    now = Date.now() / 1000
    reloadAll()
    if (!opened) markSeen()
  }

  function reloadAll() {
    historyFile.reload()
    liveFile.reload()
    quietFile.reload()
  }

  FileView {
    id: historyFile
    path: root.omarchyDir + "/history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.history = root.parseList(text())
  }
  FileView {
    id: liveFile
    path: root.omarchyDir + "/live.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.live = root.parseList(text())
  }
  FileView {
    id: quietFile
    path: root.omarchyDir + "/quiet.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.dnd = JSON.parse(text()).dnd === true } catch (e) {}
    }
  }
  FileView {
    id: mutedFile
    path: root.home + "/.config/xmilon/notifications-muted.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var a = JSON.parse(text()).apps
        root.mutedApps = Array.isArray(a) ? a.map(function(x) { return String(x).toLowerCase() }) : []
      } catch (e) {}
    }
  }
  FileView {
    id: stateFile
    path: root.home + "/.local/state/xmilon/notifcenter.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        root.lastSeen = Number(s.lastSeen) || 0
        root.clearedAt = Number(s.clearedAt) || 0
        root.hidden = Array.isArray(s.hidden) ? s.hidden.map(String) : []
      } catch (e) {}
      root.stateLoaded = true
    }
    onLoadFailed: {
      // First run: everything already in history counts as seen.
      root.lastSeen = Date.now() / 1000
      root.stateLoaded = true
      Quickshell.execDetached(["mkdir", "-p", root.home + "/.local/state/xmilon"])
    }
  }

  // Omarchy replaces its files atomically, which a file watch can miss; a slow
  // poll keeps the count honest. Faster while the panel is open.
  Timer {
    interval: root.opened ? 2000 : 8000
    running: true
    repeat: true
    onTriggered: {
      root.now = Date.now() / 1000
      root.reloadAll()
      if (root.opened) root.lastSeen = root.now
    }
  }

  // ------------------------------------------------------------- bar

  Item {
    id: bell
    anchors.centerIn: parent
    implicitWidth: glyph.implicitWidth + (badge.visible ? badge.width * 0.55 : 0)
    implicitHeight: glyph.implicitHeight

    Text {
      id: glyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.dnd ? "󰂛" : (root.unread > 0 ? "󰂚" : "󰂜")
      color: root.barForeground
      opacity: root.dnd ? 0.6 : 1
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
    Rectangle {
      id: badge
      visible: root.unread > 0 && !root.dnd
      anchors.left: glyph.right
      anchors.leftMargin: -width * 0.45
      anchors.top: glyph.top
      anchors.topMargin: -Style.space(3)
      width: Math.max(height, badgeText.implicitWidth + Style.space(6))
      height: Style.space(13)
      radius: height / 2
      color: root.accent
      Text {
        id: badgeText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.unread > 9 ? "9+" : String(root.unread)
        color: Commons.Color.background !== undefined ? Commons.Color.background : "black"
        font.family: Style.font.family
        font.pixelSize: Style.space(9)
        font.bold: true
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.toggleDnd()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: Item {
      id: body
      implicitHeight: col.implicitHeight
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
      property bool showMutes: false

      ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Notifications"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Button {
            iconText: root.dnd ? "󰂛" : "󰂚"
            text: root.dnd ? "Silenced" : "On"
            tooltipText: root.dnd ? "Do Not Disturb is on: click to show notifications again"
                                  : "Click for Do Not Disturb (right-click the bell does it too)"
            active: root.dnd
            foreground: root.fg
            onClicked: root.toggleDnd()
          }
          Button {
            iconText: "󰂠"
            tooltipText: "Mute apps"
            active: body.showMutes
            foreground: root.fg
            onClicked: body.showMutes = !body.showMutes
          }
          Button {
            iconText: "󰎟"
            text: "Clear"
            tooltipText: "Clear all"
            foreground: root.fg
            visible: root.entries.length > 0
            onClicked: root.clearAll()
          }
        }

        // Per-app mute list
        ColumnLayout {
          Layout.fillWidth: true
          visible: body.showMutes
          spacing: Style.space(4)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.knownApps.length
                  ? "Muted apps don't pop up. Their notifications still show here, marked muted."
                  : "Apps show up here once they've sent a notification."
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.knownApps
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(8)
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: modelData
                elide: Text.ElideRight
                color: root.fg
                opacity: root.isMuted(modelData) ? 0.5 : 1
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              ToggleSwitch {
                checked: !root.isMuted(modelData)
                onToggled: root.setMuted(modelData, !root.isMuted(modelData))
              }
            }
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(4)
            height: 1
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
          }
        }

        // Empty state
        ColumnLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(18)
          Layout.bottomMargin: Style.space(18)
          visible: root.entries.length === 0 && !body.showMutes
          spacing: Style.space(6)
          Text {
            Layout.alignment: Qt.AlignHCenter
            textFormat: Text.PlainText
            text: "󰂜"
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.title * 1.6
          }
          Text {
            Layout.alignment: Qt.AlignHCenter
            textFormat: Text.PlainText
            text: "You're all caught up"
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        // The list
        ListView {
          id: list
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(500))
          visible: root.entries.length > 0
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          model: root.entries
          delegate: Card {
            required property var modelData
            width: list.width
            entry: modelData
          }
        }
      }
    }
  }

  // One notification.
  component Card: Rectangle {
    id: card
    property var entry: ({})
    readonly property bool muted: entry.closed_reason === "muted"
    readonly property bool fresh: entry.time > root.lastSeen && !muted
    readonly property string icon: root.iconFor(entry.appIcon)
    implicitHeight: row.implicitHeight + Style.space(20)
    radius: Style.space(10)
    color: hover.hovered ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.09) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
    border.width: 1
    border.color: fresh ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
    opacity: muted ? 0.6 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    HoverHandler { id: hover }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(10)
      spacing: Style.space(10)

      // App icon, or its initial.
      Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: Style.space(30)
        Layout.preferredHeight: Style.space(30)
        radius: Style.space(8)
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        Image {
          id: appIcon
          anchors.centerIn: parent
          width: Style.space(20)
          height: width
          source: card.icon
          sourceSize: Qt.size(64, 64)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          visible: status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          visible: !appIcon.visible
          textFormat: Text.PlainText
          text: card.entry.glyph || String(card.entry.app || "?").charAt(0).toUpperCase()
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: (card.entry.app || "") + (card.muted ? "  ·  muted" : "")
            elide: Text.ElideRight
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: root.ago(card.entry.time)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          // Hover actions: mute this app, dismiss.
          Text {
            visible: hover.hovered
            textFormat: Text.PlainText
            text: root.isMuted(card.entry.app) ? "󰂚" : "󰂛"
            color: root.fg
            opacity: muteHit.containsMouse ? 1 : 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              id: muteHit
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setMuted(card.entry.app, !root.isMuted(card.entry.app))
            }
            PanelToolTip { visible: muteHit.containsMouse; text: root.isMuted(card.entry.app) ? "Unmute " + card.entry.app : "Mute " + card.entry.app }
          }
          Text {
            visible: hover.hovered
            textFormat: Text.PlainText
            text: "󰅖"
            color: root.fg
            opacity: closeHit.containsMouse ? 1 : 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              id: closeHit
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss(card.entry.key)
            }
          }
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          text: card.entry.summary || ""
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          text: String(card.entry.body || "").replace(/<[^>]*>/g, "")
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.75)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
