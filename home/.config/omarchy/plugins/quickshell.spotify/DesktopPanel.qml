import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "../xmilon.media/Timeline.js" as Timeline

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  function open(payloadJson) { opened = true; if (service) service.panelVisible = true }
  function close() { opened = false; if (service) service.panelVisible = false }
  function requestClose() { if (shell) shell.hide("quickshell.spotify"); else close() }

  FloatingWindow {
    id: window
    title: "Spotify player"
    visible: root.opened
    implicitWidth: 680
    implicitHeight: 420
    minimumSize: Qt.size(620, 390)
    color: Commons.Color.background
    onVisibleChanged: if (!visible && root.opened) root.requestClose()
    FocusScope {
      anchors.fill: parent
      anchors.margins: 28
      focus: true
      Keys.onEscapePressed: root.requestClose()
      ColumnLayout {
        anchors.fill: parent
        spacing: 18
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "Spotify"
            textFormat: Text.PlainText
            color: Commons.Color.foreground
            font.pixelSize: 22
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: root.service && root.service.connected ? "Connected to desktop app" : "Desktop app is closed"
            textFormat: Text.PlainText
            color: Commons.Color.foreground
            opacity: 0.6
            font.pixelSize: 12
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: 22
          SizedImage {
            Layout.preferredWidth: 144
            Layout.preferredHeight: 144
            crop: true
            url: root.service && root.service.player ? root.service.player.trackArtUrl || "" : ""
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
              Layout.fillWidth: true
              text: root.service ? root.service.title : "Spotify"
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Commons.Color.foreground
              font.pixelSize: 20
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              text: root.service ? root.service.artist : ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Commons.Color.foreground
              opacity: 0.65
              font.pixelSize: 14
            }
            RowLayout {
              Layout.fillWidth: true
              Button { text: "Previous"; focusable: true; enabled: !!root.service?.player?.canGoPrevious; onClicked: root.service.previous() }
              Button { text: root.service?.player?.isPlaying ? "Pause" : "Play"; focusable: true; enabled: !!root.service?.player?.canTogglePlaying; onClicked: root.service.playPause() }
              Button { text: "Next"; focusable: true; enabled: !!root.service?.player?.canGoNext; onClicked: root.service.next() }
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          Text { text: Timeline.timeLabel(seek.dragging ? seek.liveValue : root.service?.position || 0); textFormat: Text.PlainText; color: Commons.Color.foreground }
          PanelSlider {
            id: seek
            Layout.fillWidth: true
            enabled: !!root.service?.canSeek
            minimum: 0
            maximum: Math.max(1, root.service?.length || 0)
            value: root.service?.position || 0
            step: 10
            fillColor: Commons.Color.accent
            onReleased: value => root.service.seek(value)
          }
          Text { text: Timeline.timeLabel(root.service?.length || 0); textFormat: Text.PlainText; color: Commons.Color.foreground }
        }
        RowLayout {
          Layout.fillWidth: true
          Text { text: "Volume"; textFormat: Text.PlainText; color: Commons.Color.foreground }
          PanelSlider {
            Layout.fillWidth: true
            enabled: !!root.service?.player?.volumeSupported
            minimum: 0
            maximum: 1
            value: root.service?.player?.volume || 0
            onMoved: value => { if (root.service?.player?.volumeSupported) root.service.player.volume = value }
          }
          Button { text: "Library"; focusable: true; onClicked: root.service.launch("spotify:collection:tracks") }
          Button { text: "Open Spotify"; focusable: true; onClicked: root.service.launch("") }
        }
        RowLayout {
          Layout.fillWidth: true
          TextField {
            id: search
            Layout.fillWidth: true
            placeholderText: "Search in Spotify…"
            onAccepted: root.service.search(text)
          }
          Button { text: "Search"; focusable: true; onClicked: root.service.search(search.text) }
        }
      }
    }
  }
}
