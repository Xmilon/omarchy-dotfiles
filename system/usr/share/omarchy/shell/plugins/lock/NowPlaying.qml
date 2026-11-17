// "Now playing" pill for the Spotify desktop app, in a liquid-glass style:
// it blurs and lifts whatever is behind it (pass that layer as `backdrop`),
// with a soft shadow, a specular rim and a top sheen. Shared by the lock
// screen (plugins/lock) and the idle still screen (~/.config/xmilon/idle-still).
// Display only. Slides/fades in when Spotify has a track, out when it closes.
// Keep both copies identical (tests/test-now-playing.py checks).
import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris

Item {
  id: root

  property real s: 1
  property string fontFamily: "Outfit"
  property string iconFont: "JetBrainsMono Nerd Font"
  // The layer behind the pill (not containing it), used for the glass blur.
  property Item backdrop: null
  // Theme background; the glass is tinted with it, darkened a lot more on
  // light themes so the card always reads as dark smoked glass.
  property color themeBackground: "#101315"
  readonly property real themeLuma: 0.2126 * themeBackground.r + 0.7152 * themeBackground.g + 0.0722 * themeBackground.b
  readonly property color tint: Qt.darker(themeBackground, themeLuma > 0.5 ? 3.4 : 1.2)

  readonly property var player: {
    var list = Mpris.players.values
    for (var i = 0; i < list.length; ++i) {
      var p = list[i]
      if (String(p.identity).toLowerCase() === "spotify" || String(p.desktopEntry).toLowerCase() === "spotify") return p
    }
    return null
  }
  readonly property bool hasTrack: !!player && String(player.trackTitle || "") !== ""
  readonly property bool playing: !!player && player.isPlaying
  readonly property real length: player && player.lengthSupported ? Math.max(0, Number(player.length) || 0) : 0
  readonly property real position: player && player.positionSupported ? Math.max(0, Number(player.position) || 0) : 0
  readonly property string art: player ? String(player.trackArtUrl || "") : ""
  readonly property real radius: 20 * s

  function timeLabel(value) {
    var total = Math.floor(Math.max(0, value))
    return Math.floor(total / 60) + ":" + (total % 60 < 10 ? "0" : "") + total % 60
  }

  width: 430 * s
  height: 84 * s

  // MPRIS doesn't push position; ask for it while shown and playing.
  Timer {
    interval: 1000
    repeat: true
    running: root.visible && root.playing && !!root.player && root.player.positionSupported
    onTriggered: root.player.positionChanged()
  }

  // Appear / disappear: rise + fade + slight scale, like a system banner.
  opacity: hasTrack ? 1 : 0
  visible: opacity > 0.001
  scale: hasTrack ? 1 : 0.94
  Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

  // ------------------------------------------------------------ glass
  RectangularShadow {
    anchors.fill: glass
    radius: root.radius
    offset.y: 10 * root.s
    blur: 36 * root.s
    spread: -4 * root.s
    color: Qt.rgba(0, 0, 0, 0.45)
  }

  Item {
    id: glass
    anchors.fill: parent

    // What's behind the pill, kept in sync every frame (it can be moving).
    ShaderEffectSource {
      id: behind
      anchors.fill: parent
      sourceItem: root.backdrop
      live: true
      hideSource: false
      visible: false
      sourceRect: Qt.rect(0, 0, 1, 1)
    }
    FrameAnimation {
      running: root.visible && !!root.backdrop
      onTriggered: {
        var r = root.mapToItem(root.backdrop, 0, 0, root.width, root.height)
        behind.sourceRect = Qt.rect(r.x, r.y, r.width, r.height)
      }
    }
    Rectangle { id: pillMask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }
    MultiEffect {
      anchors.fill: parent
      source: behind
      visible: !!root.backdrop
      autoPaddingEnabled: false   // padding would stretch the rounded mask
      blurEnabled: true
      blur: 1.0
      blurMax: 48
      saturation: 0.3
      brightness: -0.12
      maskEnabled: true
      maskSource: pillMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    // Smoked tint (theme-aware) and a faint top sheen.
    Rectangle {
      anchors.fill: parent
      radius: root.radius
      color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.7)
    }
    Rectangle {
      anchors.fill: parent
      radius: root.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
        GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.03) }
      }
    }

    // Specular rim: bright along the top, fading, catching light again at the bottom.
    Item {
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: rimMask
        autoPaddingEnabled: false
      }
      Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: Math.max(1, 1.3 * root.s)
        border.color: "white"
      }
    }
    Rectangle {
      id: rimMask
      anchors.fill: parent
      visible: false
      layer.enabled: true
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.5) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.08) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.22) }
      }
    }
  }

  // ------------------------------------------------------------ content
  Item {
    id: cover
    x: 12 * root.s
    anchors.verticalCenter: parent.verticalCenter
    width: 60 * root.s
    height: width
    Rectangle {
      anchors.fill: parent
      radius: 12 * root.s
      color: Qt.rgba(1, 1, 1, 0.10)
      Text {
        anchors.centerIn: parent
        text: "󰎆"
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: root.iconFont
        font.pixelSize: 24 * root.s
        visible: coverImage.status !== Image.Ready
      }
    }
    Image {
      id: coverImage
      anchors.fill: parent
      source: root.art
      sourceSize: Qt.size(192, 192)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: false
      layer.enabled: true
    }
    Rectangle { id: coverMask; anchors.fill: parent; radius: 12 * root.s; visible: false; layer.enabled: true }
    MultiEffect {
      anchors.fill: parent
      source: coverImage
      visible: coverImage.status === Image.Ready
      autoPaddingEnabled: false
      maskEnabled: true
      maskSource: coverMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
    Rectangle {
      anchors.fill: parent
      radius: 12 * root.s
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.18)
    }
  }

  // Equalizer, right side.
  Row {
    id: eq
    anchors.right: parent.right
    anchors.rightMargin: 26 * root.s
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3 * root.s
    height: 22 * root.s
    Repeater {
      model: [0.55, 1.0, 0.7, 0.9, 0.6]
      Rectangle {
        required property var modelData
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        width: 3.5 * root.s
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.9)
        property real level: 0.18
        height: Math.max(width, eq.height * level)
        SequentialAnimation on level {
          running: root.playing && root.visible
          loops: Animation.Infinite
          NumberAnimation { to: modelData; duration: 260 + 60 * index; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.2 + 0.08 * index; duration: 320 + 45 * index; easing.type: Easing.InOutSine }
        }
        Connections {
          target: root
          function onPlayingChanged() { if (!root.playing) level = 0.18 }
        }
      }
    }
  }

  Column {
    anchors.left: cover.right
    anchors.leftMargin: 14 * root.s
    anchors.right: eq.left
    anchors.rightMargin: 18 * root.s
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1 * root.s

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.player ? String(root.player.trackTitle || "") : ""
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: 16 * root.s
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.player ? String(root.player.trackArtist || "") : ""
      color: Qt.rgba(1, 1, 1, 0.68)
      font.family: root.fontFamily
      font.pixelSize: 13 * root.s
      elide: Text.ElideRight
    }
    Item { width: 1; height: 7 * root.s }
    Item {
      width: parent.width
      height: 3 * root.s
      visible: root.length > 0
      Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.2) }
      Rectangle {
        height: parent.height
        radius: height / 2
        color: "white"
        width: root.length > 0 ? parent.width * Math.min(1, root.position / root.length) : 0
        Behavior on width { NumberAnimation { duration: 950 } }
      }
    }
    Item {
      width: parent.width
      height: 15 * root.s
      visible: root.length > 0
      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        text: root.timeLabel(root.position)
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: root.fontFamily
        font.pixelSize: 10.5 * root.s
        font.features: { "tnum": 1 }
      }
      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: "-" + root.timeLabel(Math.max(0, root.length - root.position))
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: root.fontFamily
        font.pixelSize: 10.5 * root.s
        font.features: { "tnum": 1 }
      }
    }
  }
}
