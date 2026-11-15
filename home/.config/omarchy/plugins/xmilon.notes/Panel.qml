import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Quick Notes: a bar icon that opens a panel of named pages.
// Pages are plain Markdown files in ~/Notes/Quick (see notes.py) and save
// themselves half a second after you stop typing.
Panel {
  id: root
  moduleName: "xmilon.notes"
  ipcTarget: "xmilon.notes"

  readonly property string helper: String(Qt.resolvedUrl("notes.py")).replace(/^file:\/\//, "")
  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent

  property var notes: []           // [{id, title, created, updated, pinned, body}]
  property string currentId: ""
  property string draftTitle: ""
  property string draftBody: ""
  property bool draftPinned: false
  property bool dirty: false
  property string status: ""       // "Saving…", "Saved", or an error

  // Save queue: one save at a time; the newest draft wins.
  property var pendingSave: null
  property bool creatingNew: false

  // The editor lives inside the panel's lazily loaded content, so the panel
  // talks to it through these signals instead of by id.
  signal noteLoaded()
  signal focusBody()

  readonly property var currentNote: {
    for (var i = 0; i < notes.length; i++) if (notes[i].id === currentId) return notes[i]
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------- storage

  function reload() { if (!listProc.running) listProc.running = true }

  function selectNote(note) {
    flushNow()
    if (!note) {
      currentId = ""; draftTitle = ""; draftBody = ""; draftPinned = false
    } else {
      currentId = note.id; draftTitle = note.title; draftBody = note.body; draftPinned = note.pinned
    }
    dirty = false
    status = ""
    noteLoaded()
  }

  function newNote() {
    flushNow()
    currentId = ""
    draftTitle = Qt.formatDateTime(new Date(), "d MMM, HH:mm")
    draftBody = ""
    draftPinned = false
    creatingNew = true
    noteLoaded()
    queueSave()
    focusBody()
  }

  function queueSave() {
    dirty = true
    status = "Editing…"
    saveTimer.restart()
  }

  function flushNow() {
    if (saveTimer.running) { saveTimer.stop(); startSave() }
  }

  function startSave() {
    if (!dirty && !creatingNew) return
    var payload = JSON.stringify({ id: currentId, title: draftTitle, body: draftBody, pinned: draftPinned })
    if (saveProc.running) { pendingSave = payload; return }
    saveProc.command = ["python3", "-I", root.helper, "save", payload]
    saveProc.running = true
    dirty = false
    status = "Saving…"
  }

  function togglePin() {
    if (!currentId && !creatingNew) return
    draftPinned = !draftPinned
    dirty = true
    flushNow()
    startSave()
  }

  function trashCurrent() {
    if (!currentId) return
    saveTimer.stop()
    dirty = false
    trashProc.command = ["python3", "-I", root.helper, "trash", currentId]
    trashProc.running = true
  }

  Timer {
    id: saveTimer
    interval: 500
    onTriggered: root.startSave()
  }

  Process {
    id: listProc
    command: ["python3", "-I", root.helper, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (!Array.isArray(parsed)) return
          root.notes = parsed
          if (!root.currentId && parsed.length > 0 && !root.creatingNew) root.selectNote(parsed[0])
        } catch (e) { root.status = "Couldn't read notes" }
      }
    }
  }

  Process {
    id: saveProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var saved = JSON.parse(text)
          if (saved.error) { root.status = "Not saved: " + saved.error; return }
          if (!root.currentId) root.currentId = saved.id
          root.creatingNew = false
          root.status = "Saved"
          var next = root.notes.filter(function(n) { return n.id !== saved.id })
          next.push(saved)
          next.sort(function(a, b) {
            if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
            return a.updated < b.updated ? 1 : (a.updated > b.updated ? -1 : 0)
          })
          root.notes = next
        } catch (e) { root.status = "Not saved" }
      }
    }
    onRunningChanged: {
      if (!running && root.pendingSave) {
        var payload = JSON.parse(root.pendingSave)
        root.pendingSave = null
        if (!payload.id) payload.id = root.currentId
        command = ["python3", "-I", root.helper, "save", JSON.stringify(payload)]
        running = true
      }
    }
  }

  Process {
    id: trashProc
    stdout: StdioCollector {
      onStreamFinished: {
        var gone = root.currentId
        root.notes = root.notes.filter(function(n) { return n.id !== gone })
        root.currentId = ""
        root.selectNote(root.notes.length > 0 ? root.notes[0] : null)
        root.status = "Moved to trash"
      }
    }
  }

  function prettyDate(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return iso
    var today = new Date()
    if (d.toDateString() === today.toDateString()) return "Today " + Qt.formatTime(d, "HH:mm")
    return Qt.formatDateTime(d, "d MMM yyyy, HH:mm")
  }

  onOpenedChanged: {
    if (opened) reload()
    else flushNow()
  }
  Component.onCompleted: reload()

  // ------------------------------------------------------------- bar icon

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰠮"
    onPressed: function(b) { root.toggle() }
  }

  // ------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent ? panel.loadedContent.editor : null
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(Style.space(420), Style.space(520))

    content: Item {
      id: body
      implicitHeight: Style.space(420)
      anchors.fill: parent
      Keys.onEscapePressed: root.close()
      property alias editor: bodyArea

      Component.onCompleted: { titleField.text = root.draftTitle; bodyArea.text = root.draftBody }
      Connections {
        target: root
        function onNoteLoaded() { titleField.text = root.draftTitle; bodyArea.text = root.draftBody }
        function onFocusBody() { bodyArea.forceActiveFocus() }
      }

      Shortcut { sequence: "Ctrl+N"; onActivated: root.newNote() }
      Shortcut { sequence: "Ctrl+P"; onActivated: root.togglePin() }

      RowLayout {
        anchors.fill: parent
        spacing: Style.space(12)

        // ---- page list
        ColumnLayout {
          Layout.fillWidth: false
          Layout.preferredWidth: Style.space(180)
          Layout.maximumWidth: Style.space(180)
          Layout.fillHeight: true
          spacing: Style.space(6)

          Button {
            Layout.fillWidth: true
            text: "New page"
            iconText: "󰐕"
            leftAlign: true
            foreground: root.fg
            tooltipText: "Ctrl+N"
            onClicked: root.newNote()
          }

          ListView {
            id: pageList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(2)
            model: root.notes
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property var modelData
              readonly property bool selected: modelData.id === root.currentId
              width: pageList.width
              height: rowCol.implicitHeight + Style.space(10)
              radius: Style.space(8)
              color: selected ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
                   : rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07) : "transparent"

              Column {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(1)

                Row {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    visible: row.modelData.pinned
                    textFormat: Text.PlainText
                    text: "󰐃"
                    color: root.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    width: parent.width - (row.modelData.pinned ? Style.space(16) : 0)
                    textFormat: Text.PlainText
                    text: row.modelData.title
                    color: root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: row.selected
                    elide: Text.ElideRight
                  }
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.prettyDate(row.modelData.updated)
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectNote(row.modelData)
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.notes.length === 0
              textFormat: Text.PlainText
              text: "No pages yet"
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Rectangle {
          Layout.fillHeight: true
          width: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        }

        // ---- editor
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            TextField {
              id: titleField
              Layout.fillWidth: true
              placeholderText: "Page name"
              font.pixelSize: Style.font.heading
              font.bold: true
              maximumLength: 120
              onTextEdited: { root.draftTitle = text; root.queueSave() }
              Keys.onReturnPressed: bodyArea.forceActiveFocus()
              Keys.onEscapePressed: root.close()
            }

            Button {
              iconText: root.draftPinned ? "󰐃" : "󰤱"
              foreground: root.draftPinned ? root.accent : root.fg
              tooltipText: root.draftPinned ? "Unpin (Ctrl+P)" : "Pin to top (Ctrl+P)"
              enabled: root.currentId !== "" || root.creatingNew
              opacity: enabled ? 1 : 0.4
              onClicked: root.togglePin()
            }

            Button {
              iconText: "󰩺"
              foreground: root.fg
              tooltipText: "Move page to trash"
              enabled: root.currentId !== ""
              opacity: enabled ? 1 : 0.4
              onClicked: root.trashCurrent()
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: {
              var n = root.currentNote
              var parts = []
              if (n) parts.push("Created " + root.prettyDate(n.created))
              if (n && n.updated !== n.created) parts.push("Edited " + root.prettyDate(n.updated))
              if (root.status) parts.push(root.status)
              return parts.join("  ·  ")
            }
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.space(10)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
            border.width: 1
            border.color: bodyArea.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                                               : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)

            ScrollView {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              clip: true
              ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

              TextArea {
                id: bodyArea
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                placeholderText: root.currentId || root.creatingNew ? "Write something…" : "Press New page (Ctrl+N) to start"
                placeholderTextColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
                color: root.fg
                selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                selectedTextColor: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                background: null
                onTextChanged: {
                  if (text === root.draftBody) return
                  root.draftBody = text
                  if (!root.currentId && !root.creatingNew) {
                    // Typing with no page open starts one automatically.
                    root.creatingNew = true
                    root.draftTitle = Qt.formatDateTime(new Date(), "d MMM, HH:mm")
                    titleField.text = root.draftTitle
                  }
                  root.queueSave()
                }
                Keys.onEscapePressed: root.close()
              }
            }
          }
        }
      }
    }
  }
}
