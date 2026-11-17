import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Timeline.js" as Timeline

BarWidget {
  id: root
  moduleName: "omarchy.media"
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: !!activePlayer && !!activePlayer.isPlaying
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property real trackLength: activePlayer && activePlayer.lengthSupported ? Timeline.seconds(activePlayer.length) : 0
  readonly property real trackPosition: activePlayer && activePlayer.positionSupported ? Timeline.seconds(activePlayer.position) : 0
  readonly property bool canSeek: !!activePlayer && activePlayer.canSeek && activePlayer.positionSupported && trackLength > 0

  property bool popupOpen: false

  function close() { popupOpen = false }
  function seekTo(value) {
    if (canSeek) activePlayer.position = Timeline.seekTarget(value, trackLength)
  }
  function openSpotify(nativePlayer) {
    popupOpen = false
    spotifyLauncher.command = nativePlayer
      ? ["omarchy", "shell", "shell", "toggle", "quickshell.spotify", "{}"]
      : ["spotify"]
    spotifyLauncher.running = true
  }
  Process { id: spotifyLauncher }
  Timer {
    interval: 500
    repeat: true
    running: root.popupOpen && root.isPlaying && !!root.activePlayer && root.activePlayer.positionSupported
    onTriggered: root.activePlayer.positionChanged()
  }
  property real maxLabelWidth: 180

  // Audio visualizer. cava runs in this plugin's service (Service.qml), which
  // outlives bar rebuilds; the widget only draws what the service reports.
  readonly property int vizBars: 12            // bars drawn in the bar itself
  readonly property var levels: mediaService && mediaService.vizLevels ? mediaService.vizLevels : []        // 48 values, 0..1
  readonly property var barLevels: mediaService && mediaService.vizBarLevels ? mediaService.vizBarLevels : [] // 12 values, 0..1
  // Shift the bars later to line up with what you hear, in milliseconds.
  // Set "vizDelayMs" on this widget's entry in ~/.config/omarchy/shell.json.
  Binding {
    target: root.mediaService
    when: !!root.mediaService
    property: "vizDelayMs"
    value: Math.max(0, Math.min(1000, Number(root.settings && root.settings.vizDelayMs) || 0))
  }

  // Volume of the playing app: its own PipeWire stream when found (Spotify,
  // browsers...), otherwise the player's MPRIS volume.
  readonly property var volumeStream: mediaService && mediaService.activeStream ? mediaService.activeStream : null
  readonly property bool streamVolume: !!(volumeStream && volumeStream.audio)
  readonly property bool volumeAvailable: streamVolume || !!(activePlayer && activePlayer.volumeSupported && activePlayer.canControl)
  readonly property real playerVolume: streamVolume ? volumeStream.audio.volume
    : (activePlayer && activePlayer.volumeSupported ? Number(activePlayer.volume) || 0 : 0)
  readonly property bool playerMuted: streamVolume ? volumeStream.audio.muted : false
  function setPlayerVolume(v) {
    v = Math.max(0, Math.min(1, v))
    if (streamVolume) volumeStream.audio.volume = v
    else if (activePlayer && activePlayer.volumeSupported) activePlayer.volume = v
  }

  // Always on the bar, even with nothing playing (bars rest flat, label says so).
  visible: true
  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // Sound bars: always shown; they move with the music and rest flat
    // (dimmer) when nothing is playing.
    Row {
      id: viz
      visible: !Style.reduceMotion
      opacity: root.isPlaying ? 1 : 0.45
      anchors.verticalCenter: parent.verticalCenter
      height: Math.round(root.barSize * 0.55)
      spacing: 2

      Repeater {
        model: root.vizBars

        Rectangle {
          required property int index
          width: 2
          radius: 1
          anchors.bottom: parent.bottom
          readonly property real level: root.barLevels[index] || 0
          height: Math.max(2, viz.height * level)
          color: root.bar.barForeground
          opacity: 0.55 + 0.45 * level
        }
      }
    }

    Text {
      id: glyph
      visible: !viz.visible
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: Style.duration(160) }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.title !== "" ? root.title + (root.artist ? "  ·  " + root.artist : "") : I18n.t("media.nothingPlaying")
        color: root.title !== "" ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.6)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        // Each frame of the scroll redraws the bar, so it only runs while the
        // track is playing and the bar is on screen to show it.
        NumberAnimation on x {
          id: scrollAnim
          running: labelText.needsScroll && root.isPlaying && root.visible && !root.bar.barHidden && !root.popupOpen && !root.bar.vertical && !Style.reduceMotion
          // Stopped, the title reads from its start again.
          onRunningChanged: if (!running) labelText.x = 0
          loops: Animation.Infinite
          duration: Style.duration(Math.max(6000, labelText.implicitWidth * 25))
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      // Left-click opens the popup even with nothing playing.
      if (!root.activePlayer && mouse.button !== Qt.LeftButton) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else if (mouse.button === Qt.RightButton) {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, Timeline.tooltip(root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : ""))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Item {
      anchors.fill: parent
      anchors.margins: -popup.padding
      clip: true
      Image {
        anchors.fill: parent
        source: root.popupOpen && root.activePlayer ? root.activePlayer.trackArtUrl || "" : ""
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.18
        layer.enabled: root.popupOpen && status === Image.Ready
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1 }
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.15) }
          GradientStop { position: 1; color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.85) }
        }
      }
    }

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)

          // Decode the art at the size it is drawn, not the size the player
          // serves it at. The popup is built on every monitor at startup.
          SizedImage {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            crop: true
            url: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: url != ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            textFormat: Text.PlainText
            text: root.title || I18n.t("media.nothingPlaying")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      // Big visualizer: a smooth filled wave over all 48 cava bands, drawn
      // only while the popup is open.
      Canvas {
        id: bigViz
        width: parent.width
        height: Style.space(64)
        visible: !Style.reduceMotion
        opacity: root.isPlaying ? 1 : 0.5
        renderStrategy: Canvas.Cooperative
        readonly property color waveColor: Commons.Color.accent

        Connections {
          target: root
          enabled: root.popupOpen && bigViz.visible
          function onLevelsChanged() { bigViz.requestPaint() }
          function onIsPlayingChanged() { bigViz.requestPaint() }
        }
        Connections {
          target: root
          function onPopupOpenChanged() { if (root.popupOpen) bigViz.requestPaint() }
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          // Nothing playing: a flat resting line.
          var pts = root.levels.length >= 2 ? root.levels : new Array(48).fill(0)
          var n = pts.length
          var w = width, h = height, step = w / (n - 1)
          function y(i) { return h - Math.max(2, h * pts[i]) }

          ctx.beginPath()
          ctx.moveTo(0, h)
          ctx.lineTo(0, y(0))
          for (var i = 0; i < n - 1; i++) {
            var xMid = (i + 0.5) * step
            var yMid = (y(i) + y(i + 1)) / 2
            ctx.quadraticCurveTo(i * step, y(i), xMid, yMid)
          }
          ctx.lineTo(w, y(n - 1))
          ctx.lineTo(w, h)
          ctx.closePath()

          var grad = ctx.createLinearGradient(0, 0, 0, h)
          grad.addColorStop(0, Qt.rgba(waveColor.r, waveColor.g, waveColor.b, 0.85))
          grad.addColorStop(1, Qt.rgba(waveColor.r, waveColor.g, waveColor.b, 0.10))
          ctx.fillStyle = grad
          ctx.fill()
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        Row {
          width: parent.width
          Text {
            textFormat: Text.PlainText
            text: Timeline.timeLabel(seekSlider.dragging ? seekSlider.liveValue : root.trackPosition)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width / 2
          }
          Text {
            textFormat: Text.PlainText
            text: Timeline.timeLabel(root.trackLength)
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
          }
        }
        PanelSlider {
          id: seekSlider
          bar: root.bar
          width: parent.width
          enabled: root.canSeek
          opacity: enabled ? 1 : 0.35
          minimum: 0
          maximum: Math.max(1, root.trackLength)
          step: 10
          integer: true
          value: root.trackPosition
          activeFocusOnTab: true
          Accessible.name: strings.t("seek.position")
          fillColor: Commons.Color.accent
          knobColor: Commons.Color.accent
          onReleased: function(value) { root.seekTo(value) }
          Keys.onLeftPressed: root.seekTo(root.trackPosition - 10)
          Keys.onRightPressed: root.seekTo(root.trackPosition + 10)
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)
        height: Style.space(40)
        // Transport controls keep previous, play, next in every language,
        // matching their glyphs; media controls are not mirrored.
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Button {
          text: strings.t("seek.back")
          anchors.verticalCenter: parent.verticalCenter
          focusable: true
          horizontalPadding: Style.space(6)
          foreground: root.bar.foreground
          enabled: root.canSeek
          opacity: enabled ? 1 : 0.4
          onClicked: root.seekTo(root.trackPosition - 10)
        }

        Button {
          iconText: "󰒮"
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: "󰒭"
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
        }
        Button {
          text: strings.t("seek.forward")
          anchors.verticalCenter: parent.verticalCenter
          focusable: true
          horizontalPadding: Style.space(6)
          foreground: root.bar.foreground
          enabled: root.canSeek
          opacity: enabled ? 1 : 0.4
          onClicked: root.seekTo(root.trackPosition + 10)
        }
      }

      // Volume of the playing app. Click the speaker (or right-click the
      // slider) to mute; scroll over the row to nudge it.
      Row {
        id: volumeRow
        width: parent.width
        spacing: Style.space(8)
        visible: root.volumeAvailable
        opacity: root.playerMuted ? 0.5 : 1.0

        Text {
          id: volumeIcon
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.playerMuted || root.playerVolume <= 0 ? "󰝟" : (root.playerVolume < 0.5 ? "󰖀" : "󰕾")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.icon
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.streamVolume) root.volumeStream.audio.muted = !root.volumeStream.audio.muted
          }
        }

        PanelSlider {
          id: volumeSlider
          bar: root.bar
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - volumeIcon.width - volumePct.width - parent.spacing * 2
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.playerVolume
          onMoved: function(v) { root.setPlayerVolume(v) }
          onRightClicked: if (root.streamVolume) root.volumeStream.audio.muted = !root.volumeStream.audio.muted
        }

        Text {
          id: volumePct
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: Math.round(root.playerVolume * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        WheelHandler {
          onWheel: function(event) {
            root.setPlayerVolume(root.playerVolume + (event.angleDelta.y > 0 ? 0.05 : -0.05))
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Row {
        id: spotifyActions
        width: parent.width
        spacing: Style.space(6)
        height: Math.max(openSpotifyButton.implicitHeight, nativeSpotifyButton.implicitHeight)
        Button {
          id: openSpotifyButton
          width: (spotifyActions.width - spotifyActions.spacing) / 2
          height: spotifyActions.height
          text: strings.t("spotify.open")
          fontSize: Style.font.caption
          horizontalPadding: Style.space(6)
          focusable: true
          iconText: ""
          foreground: root.bar.foreground
          onClicked: root.openSpotify(false)
        }
        Button {
          id: nativeSpotifyButton
          width: (spotifyActions.width - spotifyActions.spacing) / 2
          height: spotifyActions.height
          text: strings.t("spotify.native")
          fontSize: Style.font.caption
          horizontalPadding: Style.space(6)
          focusable: true
          foreground: root.bar.foreground
          onClicked: root.openSpotify(true)
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || I18n.t("media.mediaSource")) : I18n.t("media.mediaSource")
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Commons.Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }
}
