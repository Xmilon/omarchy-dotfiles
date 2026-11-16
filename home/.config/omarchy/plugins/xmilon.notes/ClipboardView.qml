import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "ClipboardHistory.js" as ClipboardHistory  // link to Omarchy's own file

// Clipboard tab of the Notes panel: Omarchy's clipboard history with the same
// actions as its full manager (Super+Ctrl+V). It reads and writes Omarchy's own
// history file and reuses Omarchy's history logic and copy/paste commands.
//
//   type          search            Enter / right-click  paste into the window you were in
//   ↑ ↓ PgUp PgDn Home End  move    click / Shift+Enter  copy only (panel stays open)
//   Delete        remove item       Alt+Enter          open
//   Shift+Delete  clear history (press twice)          Esc  clear search, then close
Item {
  id: view

  property var bar: null
  property color fg: Commons.Color.foreground
  property color accent: Commons.Color.accent
  signal closeRequested()

  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  property var history: []
  property var rows: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool confirmClear: false
  property var pendingAction: null

  property alias searchField: search
  function focusSearch() { search.forceActiveFocus() }
  // Each time the tab is opened: empty search, first item selected.
  function reset() {
    filterText = ""
    search.text = ""
    selectedIndex = 0
    confirmClear = false
    rebuild()
    list.positionViewAtBeginning()
  }

  function loadHistory(raw) {
    try { history = ClipboardHistory.parseHistory(raw) } catch (e) { history = [] }
    rebuild()
  }
  function saveHistory() {
    historyFile.setText(JSON.stringify(history.slice(0, 500), null, 2) + "\n")
  }
  function rebuild() {
    rows = ClipboardHistory.displayRows(history, filterText, 500,
                                        Commons.I18n.t, Commons.I18n.tn, Commons.I18n.formatNumber)
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
  }
  function select(delta) {
    if (rows.length === 0) return
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + delta))
    list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  // Paste: close the panel first so the window you were in gets focus back,
  // then let Omarchy's paste command type into it.
  function run(argv) {
    pendingAction = argv
    closeRequested()
    actionTimer.restart()
  }
  function paste(row) {
    if (!row) return
    if (row.entryType === "image") run([omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    else if (row.fullText) run([omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.index)])
  }
  // Copy only: the panel stays open (nothing needs focus back), with a short
  // "Copied" note in the footer.
  function copy(row) {
    if (!row) return
    if (row.entryType === "image") Quickshell.execDetached([omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    else if (row.fullText) Quickshell.execDetached([omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.index)])
    else return
    copiedNote = row.entryType === "image" ? "Image copied" : "Copied"
    copiedTimer.restart()
  }
  property string copiedNote: ""
  function openRow(row) {
    if (!row) return
    run([omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.index)])
  }
  function removeRow(row) {
    if (!row) return
    history = ClipboardHistory.removeEntryAt(history, row.index)
    saveHistory()
    rebuild()
  }
  function clearAll() {
    if (!confirmClear) { confirmClear = true; confirmTimer.restart(); return }
    confirmClear = false
    history = ClipboardHistory.clearHistory()
    saveHistory()
    rebuild()
  }

  Timer {
    id: actionTimer
    interval: 160
    onTriggered: if (view.pendingAction) { Quickshell.execDetached(view.pendingAction); view.pendingAction = null }
  }
  Timer { id: confirmTimer; interval: 2500; onTriggered: view.confirmClear = false }
  Timer { id: copiedTimer; interval: 1500; onTriggered: view.copiedNote = "" }

  FileView {
    id: historyFile
    path: view.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: view.loadHistory(text())
    onLoadFailed: view.loadHistory("[]")
    onFileChanged: reload()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    TextField {
      id: search
      Layout.fillWidth: true
      placeholderText: "Search clipboard…"
      text: view.filterText
      onTextEdited: { view.filterText = text; view.selectedIndex = 0; view.rebuild() }
      Keys.onPressed: function(event) {
        var row = view.rows[view.selectedIndex]
        if (event.key === Qt.Key_Escape) {
          if (view.filterText) { view.filterText = ""; text = ""; view.rebuild() } else view.closeRequested()
        } else if (event.key === Qt.Key_Down) view.select(1)
        else if (event.key === Qt.Key_Up) view.select(-1)
        else if (event.key === Qt.Key_PageDown) view.select(6)
        else if (event.key === Qt.Key_PageUp) view.select(-6)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (event.modifiers & Qt.AltModifier) view.openRow(row)
          else if (event.modifiers & Qt.ShiftModifier) view.copy(row)
          else view.paste(row)
        } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) view.clearAll()
        // Delete removes the selected item (like Omarchy's manager), unless
        // there is search text after the cursor to delete.
        else if (event.key === Qt.Key_Delete && cursorPosition >= text.length) view.removeRow(row)
        else if (event.key === Qt.Key_Home && text === "") { view.selectedIndex = 0; view.select(0) }
        else if (event.key === Qt.Key_End && text === "") { view.selectedIndex = view.rows.length - 1; view.select(0) }
        else return
        event.accepted = true
      }
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(2)
      model: view.rows
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property bool selected: index === view.selectedIndex
        readonly property bool hasImage: modelData.previewImage !== ""
        width: list.width - Style.space(10)
        height: hasImage ? Style.space(64) : Style.space(38)
        radius: Style.space(8)
        color: selected ? Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.14)
             : rowMouse.containsMouse ? Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.07) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(10)

          Text {
            visible: !row.hasImage
            textFormat: Text.PlainText
            text: row.modelData.entryType === "file" ? "󰈔" : "󰈙"
            color: view.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }

          Rectangle {
            visible: row.hasImage
            Layout.preferredWidth: Style.space(80)
            Layout.preferredHeight: Style.space(54)
            radius: Style.space(6)
            color: Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.06)
            clip: true
            Image {
              anchors.fill: parent
              source: row.hasImage ? "file://" + row.modelData.previewImage : ""
              sourceSize.width: 160
              sourceSize.height: 108
              asynchronous: true
              fillMode: Image.PreserveAspectCrop
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: String(row.modelData.previewText || "").replace(/\s+/g, " ")
            color: view.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onEntered: view.selectedIndex = row.index
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) view.paste(row.modelData)
            else if (mouse.button === Qt.MiddleButton) view.removeRow(row.modelData)
            else view.copy(row.modelData)
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: view.rows.length === 0
        textFormat: Text.PlainText
        text: view.filterText ? "No matches" : "Nothing copied yet"
        color: Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: view.confirmClear ? "Press Shift+Delete again to clear the whole clipboard history"
          : view.copiedNote ? "✓ " + view.copiedNote
          : view.rows.length + (view.rows.length === 1 ? " item" : " items")
            + "  ·  Click copy  ·  Enter or right-click paste  ·  Alt+Enter open  ·  Del remove"
      color: view.confirmClear || view.copiedNote ? view.accent : Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
