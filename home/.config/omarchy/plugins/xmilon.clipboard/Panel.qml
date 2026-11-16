import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Clipboard: a bar icon for Omarchy's clipboard history.
// Left-click: the 8 most recent items. Click one to put it back on the
// clipboard (ready for Ctrl+V). Right-click, or the button at the bottom,
// opens Omarchy's full clipboard manager (also Super+Ctrl+V).
// History is read live from Omarchy's own file; copying uses Omarchy's own
// commands, so it behaves exactly like the built-in manager.
Panel {
  id: root
  moduleName: "xmilon.clipboard"
  ipcTarget: "xmilon.clipboard"

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  readonly property int maxItems: 8

  property var items: []      // [{index, type, text, mime, path, capturedAt}]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function rebuild(raw) {
    var list = []
    try {
      var all = JSON.parse(raw || "[]")
      if (!Array.isArray(all)) all = []
      for (var i = 0; i < all.length && list.length < maxItems; i++) {
        var e = all[i]
        if (!e) continue
        if (e.type === "image" && e.path) {
          list.push({ index: i, type: "image", text: "", mime: e.mime || "image/png", path: String(e.path), capturedAt: e.capturedAt || "" })
        } else if (e.type === "text" && typeof e.text === "string" && e.text.trim() !== "") {
          list.push({ index: i, type: "text", text: e.text, mime: "", path: "", capturedAt: e.capturedAt || "" })
        }
      }
    } catch (err) {}
    items = list
  }

  function preview(text) {
    var oneLine = String(text).replace(/\s+/g, " ").trim()
    return oneLine.length > 90 ? oneLine.slice(0, 90) + "…" : oneLine
  }

  function copyItem(item) {
    if (!item) return
    if (item.type === "image")
      Quickshell.execDetached(["omarchy-clipboard-paste-file", "--copy-only", item.mime, item.path])
    else
      Quickshell.execDetached(["omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(item.index)])
    root.close()
  }

  function openManager() {
    root.close()
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omarchy.clipboard", "{}"])
  }

  FileView {
    id: history
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.rebuild(text())
  }

  onOpenedChanged: if (opened) history.reload()

  // ------------------------------------------------------------- bar icon

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅇"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openManager()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: Item {
      implicitHeight: col.implicitHeight
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(4)

        Text {
          Layout.fillWidth: true
          Layout.bottomMargin: Style.space(4)
          textFormat: Text.PlainText
          text: "Clipboard  ·  click to copy"
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.items.length === 0
          Layout.fillWidth: true
          Layout.topMargin: Style.space(10)
          Layout.bottomMargin: Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "Nothing copied yet"
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.items

          Rectangle {
            id: row
            required property var modelData
            readonly property bool isImage: modelData.type === "image"
            Layout.fillWidth: true
            Layout.preferredHeight: isImage ? Style.space(64) : Style.space(36)
            radius: Style.space(8)
            color: rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10) : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(10)

              Text {
                visible: !row.isImage
                textFormat: Text.PlainText
                text: "󰈙"
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              Rectangle {
                visible: row.isImage
                Layout.preferredWidth: Style.space(80)
                Layout.preferredHeight: Style.space(54)
                radius: Style.space(6)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                clip: true
                Image {
                  anchors.fill: parent
                  source: row.isImage ? "file://" + row.modelData.path : ""
                  sourceSize.width: 160
                  sourceSize.height: 108
                  asynchronous: true
                  fillMode: Image.PreserveAspectCrop
                }
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: row.isImage ? "Image" : root.preview(row.modelData.text)
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Text {
                visible: text !== ""
                textFormat: Text.PlainText
                text: row.modelData.capturedAt
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyItem(row.modelData)
            }
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          foreground: root.fg
        }

        Button {
          Layout.fillWidth: true
          text: "Open clipboard manager  (Super+Ctrl+V)"
          iconText: "󰅌"
          foreground: root.fg
          onClicked: root.openManager()
        }
      }
    }
  }
}
