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
  manageIpc: false   // we own the IPC target to add "clipboard"

  // 0 = Notes, 1 = Clipboard (Omarchy's clipboard history; see ClipboardView.qml)
  property int tab: 0
  function openTab(t) {
    tab = t
    if (t === 1 && panel.loadedContent) panel.loadedContent.resetClipboard()
    if (!opened) { open(); return }
    // Already open: take keyboard focus back (another window may have it),
    // then focus the right field.
    if (typeof panel.beginFocusPrime === "function") panel.beginFocusPrime()
    if (panel.loadedContent) {
      if (t === 1) panel.loadedContent.focusClipboard()
      else panel.loadedContent.editor.forceActiveFocus()
    }
  }

  ShellIpc {
    target: "xmilon.notes"
    function open() { root.openTab(0) }
    function close() { root.close() }
    function toggle() { if (root.opened) root.close(); else root.openTab(0) }
    function clipboard() { if (root.opened && root.tab === 1) root.close(); else root.openTab(1) }
    function show() { root.openTab(0) }
    function hide() { root.close() }
  }

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
  signal pasteText()
  signal insertMarkdown(string md)

  // Notes folder; the editor resolves media links relative to it.
  readonly property string notesDir: (Quickshell.env("QUICK_NOTES_DIR") || (Quickshell.env("HOME") + "/Notes/Quick"))
  property bool loadingText: false

  // Markdown for an attachment, placed inline at the cursor. Images and videos
  // show their preview and link to the full file; other files are links.
  function attachmentMarkdown(a) {
    var label = String(a.name).replace(/[\[\]]/g, "")
    if (a.thumb) {
      var cap = a.kind === "video" ? "🎬 " + label : label
      return "[![" + cap + "](" + a.thumb + ")](" + a.url + ")"
    }
    var icon = a.kind === "video" ? "🎬" : a.kind === "audio" ? "🎵"
             : a.mime === "application/pdf" ? "📄" : a.kind === "image" ? "🖼" : "📎"
    return "[" + icon + " " + label + "](" + a.url + ")"
  }

  // Link colour: the text colour with a hint of the theme accent. Qt's Markdown
  // reader paints links in the GTK theme's bright blue, so for display each
  // link becomes a small HTML link carrying this colour; saving turns them
  // back into plain Markdown links.
  readonly property color linkColor: Qt.tint(root.fg, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35))
  function displayMarkdown(md) {
    var c = "#" + [linkColor.r, linkColor.g, linkColor.b].map(function(v) {
      var h = Math.round(v * 255).toString(16); return h.length < 2 ? "0" + h : h
    }).join("")
    function a(href, label) {
      return '<a href="' + href.replace(/"/g, "%22") + '" style="color:' + c + '">' + label + '</a>'
    }
    // Leave code spans alone.
    return String(md).split(/(`[^`]*`)/).map(function(part, i) {
      if (i % 2 === 1) return part
      return part
        .replace(/(^|[^!\]])\[([^\]]+)\]\(([^)\s]+)\)/g, function(m, pre, label, href) { return pre + a(href, label) })
        .replace(/<((?:https?|mailto):[^>\s]+)>/g, function(m, href) { return a(href, href) })
        .replace(/(^|[\s(])((?:https?:\/\/|www\.)[^\s<>()"']+)/g, function(m, pre, url) {
          return pre + a(url.indexOf("www.") === 0 ? "https://" + url : url, url)
        })
    }).join("")
  }

  // The full file behind an inline preview at (x, y): images show as one
  // object character each, so count them up to the click and take that image
  // from the Markdown. Previews live in .thumbs/ next to the original.
  function imageAt(edit, x, y) {
    var pos = edit.positionAt(x, y)
    var hit = -1
    for (var p = pos; p >= Math.max(0, pos - 1); p--) {
      if (edit.getText(p, p + 1) === "\ufffc") { hit = p; break }
    }
    if (hit < 0) return ""
    var index = (edit.getText(0, hit).match(/\ufffc/g) || []).length
    var re = /!\[[^\]]*\]\(([^)\s]+)\)/g, m, i = 0
    while ((m = re.exec(edit.text)) !== null) {
      if (i === index) return m[1].replace(/\/\.thumbs\/(.+)\.jpg$/, "/$1")
      i++
    }
    return ""
  }

  // Ctrl+click: open a link (relative ones are files in the notes folder).
  function openLink(link) {
    link = String(link)
    if (link === "") return
    if (!/^[a-z][a-z0-9+.-]*:/i.test(link)) link = root.notesDir + "/" + decodeURIComponent(link)
    Quickshell.execDetached(["xdg-open", link])
  }

  // ------------------------------------------------------------- attachments
  // Files live in ~/Notes/Quick/media/<page id>/ (see notes.py).
  readonly property var attachments: currentNote && currentNote.attachments ? currentNote.attachments : []
  property var attachQueue: []

  function setAttachments(list) {
    var id = currentId
    notes = notes.map(function(n) {
      return n.id === id ? Object.assign({}, n, { attachments: list }) : n
    })
  }
  function needsSavedPage() {
    if (currentId) return false
    status = "Write something or name the page first"
    return true
  }
  function attachFiles(paths) {
    if (needsSavedPage()) return
    attachQueue = attachQueue.concat(paths.map(function(p) { return String(p) }).filter(function(p) { return p !== "" }))
    runAttachQueue()
  }
  function runAttachQueue() {
    if (attachProc.running || attachQueue.length === 0) return
    var next = attachQueue[0]
    attachQueue = attachQueue.slice(1)
    attachProc.command = ["python3", "-I", root.helper, "attach", root.currentId, next]
    attachProc.running = true
    status = "Attaching…"
  }
  function pasteImage() {
    if (needsSavedPage() || attachProc.running) return
    attachProc.command = ["python3", "-I", root.helper, "paste-image", root.currentId]
    attachProc.running = true
    status = "Pasting image…"
  }
  function detach(name) {
    if (!currentId || attachProc.running) return
    attachProc.command = ["python3", "-I", root.helper, "detach", root.currentId, name]
    attachProc.running = true
  }
  function openAttachment(path) {
    Quickshell.execDetached(["xdg-open", path])
  }
  function pickFiles() {
    if (needsSavedPage() || pickProc.running) return
    pickProc.running = true
  }
  // Ctrl+V in the editor: an image on the clipboard becomes an attachment,
  // anything else pastes as text.
  function smartPaste() {
    if (!clipTypesProc.running) clipTypesProc.running = true
  }

  Process {
    id: attachProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var out = JSON.parse(text)
          if (out && out.error) root.status = out.error
          else if (out && Array.isArray(out.attachments)) {
            root.setAttachments(out.attachments)
            if (out.added) root.insertMarkdown(root.attachmentMarkdown(out.added))
            root.status = "Saved"
          }
        } catch (e) { root.status = "Couldn't attach" }
      }
    }
    onRunningChanged: if (!running) Qt.callLater(root.runAttachQueue)
  }

  Process {
    id: pickProc
    command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Attach files to note"]
    stdout: StdioCollector {
      onStreamFinished: {
        var files = text.split("\n").filter(function(l) { return l.trim() !== "" })
        if (files.length > 0) root.attachFiles(files)
      }
    }
  }

  Process {
    id: clipTypesProc
    command: ["wl-paste", "--list-types"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (/(^|\n)image\//.test(text)) root.pasteImage()
        else root.pasteText()
      }
    }
  }

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
          else if (root.currentId && !root.dirty && !saveTimer.running) {
            // Pick up changes made to the open page outside the panel.
            var fresh = parsed.filter(function(n) { return n.id === root.currentId })[0]
            if (fresh && (fresh.body !== root.draftBody || fresh.title !== root.draftTitle)) root.selectNote(fresh)
            else if (!fresh) root.selectNote(parsed.length > 0 ? parsed[0] : null)
          }
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
    // Left-click: notes. Right-click: clipboard.
    onPressed: function(b) {
      var want = b === Qt.RightButton ? 1 : 0
      if (root.opened && root.tab === want) root.close()
      else root.openTab(want)
    }
  }

  // ------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent ? (root.tab === 1 ? panel.loadedContent.clipboardSearch : panel.loadedContent.editor) : null
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(Style.space(470), Style.space(560))

    content: Item {
      id: body
      implicitHeight: Style.space(470)
      anchors.fill: parent
      // Open/close animation comes from the shared popup (omarchy-popup-anim-patch); popT stays 1.
      property real popT: 1
      opacity: Math.min(1, popT * 1.4)
      transform: [
        Scale { origin.x: body.width / 2; origin.y: 0; xScale: 0.94 + 0.06 * body.popT; yScale: 0.9 + 0.1 * body.popT },
        Translate { y: -12 * (1 - body.popT) }
      ]
      Keys.onEscapePressed: root.close()
      property alias editor: bodyArea
      property Item clipboardSearch: clipView.searchField
      function focusClipboard() { clipView.focusSearch() }
      function resetClipboard() { clipView.reset() }
      Connections {
        target: root
        function onTabChanged() {
          if (root.tab === 1) clipView.focusSearch()
          else bodyArea.forceActiveFocus()
        }
      }

      function loadBody() {
        root.loadingText = true
        titleField.text = root.draftTitle
        bodyArea.text = root.displayMarkdown(root.draftBody)
        root.loadingText = false
      }
      Component.onCompleted: loadBody()
      Connections {
        target: root
        function onNoteLoaded() { body.loadBody() }
        function onFocusBody() { bodyArea.forceActiveFocus() }
      }

      Shortcut { sequence: "Ctrl+N"; enabled: root.tab === 0; onActivated: root.newNote() }
      Shortcut { sequence: "Ctrl+P"; enabled: root.tab === 0; onActivated: root.togglePin() }
      Shortcut { sequence: "Ctrl+1"; onActivated: root.tab = 0 }
      Shortcut { sequence: "Ctrl+2"; onActivated: root.tab = 1 }

      // ---- tabs
      Row {
        id: tabBar
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: Style.space(4)
        Repeater {
          model: [{ label: "Notes", icon: "󰠮", key: "Ctrl+1" }, { label: "Clipboard", icon: "󰅇", key: "Ctrl+2" }]
          Button {
            required property var modelData
            required property int index
            text: modelData.label
            iconText: modelData.icon
            tooltipText: modelData.key
            selected: root.tab === index
            foreground: root.fg
            onClicked: root.tab = index
          }
        }
      }
      Rectangle {
        id: tabRule
        anchors.top: tabBar.bottom
        anchors.topMargin: Style.space(6)
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
      }

      ClipboardView {
        id: clipView
        visible: root.tab === 1
        anchors.top: tabRule.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        bar: root.bar
        fg: root.fg
        accent: root.accent
        onCloseRequested: root.close()
      }

      RowLayout {
        visible: root.tab === 0
        anchors.top: tabRule.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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
              iconText: "󰏢"
              foreground: root.fg
              tooltipText: "Insert a file at the cursor (or drop files here, or paste an image)"
              enabled: root.currentId !== ""
              opacity: enabled ? 1 : 0.4
              onClicked: root.pickFiles()
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
                // Markdown so images/videos show inline and links work.
                textFormat: TextEdit.MarkdownText
                baseUrl: "file://" + root.notesDir + "/"
                wrapMode: TextEdit.Wrap
                placeholderText: root.currentId || root.creatingNew ? "Write something…" : "Press New page (Ctrl+N) to start"
                placeholderTextColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
                color: root.fg
                selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                selectedTextColor: root.fg
                // Shown in JetBrains Mono like the rest of the bar. Qt saves text
                // set in a monospace font as Markdown code (`...`), so markdown()
                // reads the text back with a proportional font for a moment.
                font.family: "JetBrainsMono Nerd Font"
                property bool switchingFont: false
                function markdown() {
                  var family = font.family
                  switchingFont = true
                  font.family = "Inter Variable"
                  var md = text
                  font.family = family
                  switchingFont = false
                  return md
                }
                font.pixelSize: Style.font.subtitle + 1
                background: null
                onTextChanged: {
                  if (root.loadingText || switchingFont) return
                  var md = markdown()
                  if (md === root.draftBody) return
                  root.draftBody = md
                  if (!root.currentId && !root.creatingNew) {
                    // Typing with no page open starts one automatically.
                    root.creatingNew = true
                    root.draftTitle = Qt.formatDateTime(new Date(), "d MMM, HH:mm")
                    titleField.text = root.draftTitle
                  }
                  root.queueSave()
                }
                Keys.onEscapePressed: root.close()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)
                      && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true
                    root.smartPaste()
                  }
                }
                Connections {
                  target: root
                  function onPasteText() { bodyArea.paste() }
                  function onInsertMarkdown(md) {
                    var pos = bodyArea.cursorPosition
                    bodyArea.insert(pos, md + " ")
                    bodyArea.forceActiveFocus()
                  }
                }

                // Pointer over a link shows a hand.
                HoverHandler {
                  cursorShape: bodyArea.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                }

                // Ctrl+click opens links: Markdown links, media, or a plain
                // web address typed into the text.
                TapHandler {
                  acceptedModifiers: Qt.ControlModifier
                  onTapped: function(point) {
                    var link = bodyArea.linkAt(point.position.x, point.position.y)
                    if (!link) link = root.imageAt(bodyArea, point.position.x, point.position.y)
                    if (!link) {
                      var pos = bodyArea.positionAt(point.position.x, point.position.y)
                      var from = Math.max(0, pos - 300)
                      var chunk = bodyArea.getText(from, Math.min(bodyArea.length, pos + 300))
                      var re = /(https?:\/\/|www\.)[^\s<>()"']+/g, m
                      while ((m = re.exec(chunk)) !== null) {
                        if (from + m.index <= pos && pos <= from + m.index + m[0].length) {
                          link = m[0].indexOf("www.") === 0 ? "https://" + m[0] : m[0]
                          break
                        }
                      }
                    }
                    if (link) root.openLink(link)
                  }
                }
              }
            }
          }

        }
      }

      // Drop files anywhere on the panel: they are attached and placed at the cursor.
      DropArea {
        anchors.fill: parent
        enabled: root.tab === 0
        onDropped: function(drop) {
          if (drop.hasUrls) root.attachFiles(drop.urls)
        }
      }
    }
  }
}
