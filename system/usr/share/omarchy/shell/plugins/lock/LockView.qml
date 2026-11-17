// Xmilon lock screen: same look as the Thyx login screen (blurred wallpaper,
// clock, round avatar, name, password pill, power buttons), with the clock
// sliding in from the top and the card from the bottom.
//
// Drop-in replacement for Omarchy's plugins/lock/LockView.qml. The public
// interface (properties, signals, functions) and all password-input handling
// are unchanged from upstream; only the visuals differ. Installed by
// omarchy-lock-view-install, which refuses to overwrite an upstream file it
// was not written against.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool fingerprintUnavailable: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  readonly property string placeholderText: Commons.I18n.t("lock.enterPassword")
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0

  // A video wallpaper shows its still poster: nothing plays behind the lock.
  readonly property bool video: Util.isVideoPath(root.backgroundPath)

  // Look
  readonly property real s: Math.max(0.75, Math.min(width / 1920, height / 1080))
  readonly property color fg: "#f2f5f8"
  readonly property color dim: "#c3ccd5"
  readonly property string fontFamily: "Plus Jakarta Sans"
  readonly property string clockFont: "Outfit"
  readonly property string iconFont: "JetBrainsMono Nerd Font"
  readonly property string home: Quickshell.env("HOME")
  property string displayName: "Xmilon"
  property date now: new Date()

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  // Waking a DPMS-blanked display can stall the compositor for seconds while
  // the monitor modesets, so the wake key's release arrives late and client-side
  // key repeat floods the field with that character. A held key has no business
  // typing a password; only holding Backspace/Delete to clear stays useful.
  function dropsAutoRepeat(key) {
    return key !== Qt.Key_Backspace && key !== Qt.Key_Delete
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  // The field loses focus while a password is checked (it is disabled then),
  // and forcing focus onto it would not stick until the check ends.
  function restorePasswordFocus() {
    if (inputEnabled && passwordInput.enabled && !passwordInput.activeFocus) forcePasswordFocus()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  onFailedAttemptsChanged: if (failedAttempts > 0) shake.restart()

  // A VT switch, which the NVIDIA driver forces around every suspend, takes the
  // keyboard away and Qt drops the field's focus with it. Nothing gives it back
  // when the keyboard returns, so typing went nowhere until the field was clicked.
  Window.onActiveFocusItemChanged: Qt.callLater(restorePasswordFocus)
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    playIntro()
  }
  property bool introPlayed: false
  function playIntro() {
    if (introPlayed || height <= 0) return
    introPlayed = true
    intro.restart()
  }
  onHeightChanged: playIntro()

  Timer { interval: 1000; running: root.visible; repeat: true; onTriggered: root.now = new Date() }

  // Name shown under the avatar: same setting as the login screen.
  FileView {
    path: root.home + "/.config/thyx/settings.json"
    printErrors: false
    onLoaded: {
      try {
        var title = JSON.parse(text()).title
        if (title) root.displayName = String(title).slice(0, 64)
      } catch (e) {}
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background

    // Everything behind the UI; the now-playing glass samples this layer.
    Item {
      id: backdropLayer
      anchors.fill: parent

    BackgroundMedia {
      id: wallpaper
      objectName: "lockWallpaper"
      anchors.fill: parent
      path: root.loadBackground ? (root.video ? root.videoPosterPath : root.backgroundPath) : ""
      version: root.backgroundVersion
      // Decode only once sized, at the lock's own size (the lock service keeps
      // that size decoded ahead of the lock, so the first frame has it).
      cached: true
      constrainDecode: true
      decodeSize: Qt.size(width, height)
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.ready
      blur: 1.0
      blurMax: 64
      blurMultiplier: 1.0
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.28 }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // -------------------------------------------------------------- clock
    Column {
      id: clock
      transform: Translate { id: clockSlide }
      anchors.horizontalCenter: parent.horizontalCenter
      // Eases down to make room when the now-playing pill is shown above.
      y: root.height * 0.13 + (nowPlaying.hasTrack ? root.height * 0.065 : 0)
      Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      spacing: 2 * root.s
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.now, "HH:mm")
        color: root.fg
        font.family: root.clockFont
        font.pixelSize: 124 * root.s
        font.weight: Font.Thin
        font.letterSpacing: 2 * root.s
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.now, "dddd, d MMMM").toUpperCase()
        color: root.dim
        font.family: root.clockFont
        font.pixelSize: 15 * root.s
        font.letterSpacing: 4 * root.s
      }
    }

    // Spotify now playing, above the clock; moves and fades with it.
    Item {
      anchors.bottom: clock.top
      anchors.bottomMargin: 26 * root.s
      anchors.horizontalCenter: parent.horizontalCenter
      width: nowPlaying.width
      height: nowPlaying.height
      opacity: clock.opacity
      transform: Translate { y: clockSlide.y }
      NowPlaying { id: nowPlaying; s: root.s; iconFont: root.iconFont; backdrop: backdropLayer; themeBackground: Commons.Color.background }
    }

    // -------------------------------------------------------------- card
    Column {
      id: card
      transform: Translate { id: cardSlide }
      anchors.horizontalCenter: parent.horizontalCenter
      y: (root.height - height) / 2 + root.height * 0.08
      spacing: 14 * root.s

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 96 * root.s
        height: width
        visible: avatarImage.status === Image.Ready
        Image {
          id: avatarImage
          anchors.fill: parent
          source: "file://" + root.home + "/.config/thyx/solo.png"
          sourceSize: Qt.size(256, 256)
          fillMode: Image.PreserveAspectCrop
          visible: false
          layer.enabled: true
        }
        Rectangle {
          id: avatarMask
          anchors.fill: parent
          radius: width / 2
          visible: false
          layer.enabled: true
        }
        MultiEffect {
          anchors.fill: parent
          source: avatarImage
          maskEnabled: true
          maskSource: avatarMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.color: Qt.rgba(1, 1, 1, 0.55)
          border.width: 2
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.displayName
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: 22 * root.s
        font.weight: Font.DemiBold
      }

      Rectangle {
        id: inputField
        anchors.horizontalCenter: parent.horizontalCenter
        width: 300 * root.s
        height: 46 * root.s
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        border.color: root.errorState ? Commons.Color.lock.textError
          : (passwordInput.activeFocus ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(1, 1, 1, 0.22))
        Behavior on border.color { ColorAnimation { duration: 140 } }
        clip: true

        TextInput {
          id: passwordInput
          anchors.fill: parent
          anchors.leftMargin: 20 * root.s
          anchors.rightMargin: (root.fingerprintConfigured ? 44 : 20) * root.s
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          activeFocusOnPress: true
          clip: true
          enabled: root.inputEnabled && !root.authenticatingPassword
          readOnly: root.authenticatingPassword
          echoMode: TextInput.Password
          passwordCharacter: "•"
          passwordMaskDelay: 0
          color: root.fg
          selectionColor: Commons.Color.lock.selection
          selectedTextColor: root.fg
          font.family: root.fontFamily
          font.pixelSize: 18 * root.s
          font.letterSpacing: 2 * root.s
          cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
          cursorDelegate: Rectangle {
            width: 2
            color: root.fg
            visible: passwordInput.cursorVisible
          }

          onTextChanged: {
            if (!root.syncingPasswordText) root.passwordTextEdited(text)
            if (text.length > 0) {
              root.wakeRequested()
            }
            if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
          }

          onAccepted: {
            var submitted = root.passwordText
            root.passwordTextEdited("")
            if (submitted.length > 0) root.submitPassword(submitted)
          }

          Keys.onPressed: function(event) {
            root.wakeRequested()
            if (event.isAutoRepeat && root.dropsAutoRepeat(event.key)) {
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
              root.passwordTextEdited("")
              event.accepted = true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: passwordInput
          text: root.authenticatingPassword ? Commons.I18n.t("lock.checking") : root.placeholderText
          visible: passwordInput.text.length === 0
          color: Qt.rgba(1, 1, 1, 0.55)
          font.family: root.fontFamily
          font.pixelSize: 15 * root.s
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        // Fingerprint hint inside the field's right edge when a sensor is
        // enrolled; crossed out when the reader can't be reached.
        Text {
          id: fingerprintIcon
          objectName: "fingerprintIndicator"
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: 16 * root.s
          anchors.verticalCenter: parent.verticalCenter
          visible: root.fingerprintConfigured
          text: root.fingerprintUnavailable ? "󰺱" : "󰈷"
          color: root.fingerprintUnavailable ? Commons.Color.lock.textError : Qt.rgba(1, 1, 1, 0.55)
          font.family: root.iconFont
          font.pixelSize: 18 * root.s
        }

        SequentialAnimation {
          id: shake
          NumberAnimation { target: inputField; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
          NumberAnimation { target: inputField; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
          NumberAnimation { target: inputField; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
          NumberAnimation { target: inputField; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
        }
      }

      // Error / fingerprint status line, fixed height so nothing jumps.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 18 * root.s
        textFormat: Text.PlainText
        objectName: "fingerprintUnavailableNotice"
        text: root.errorState ? root.failureMessage
          : (root.fingerprintConfigured && root.fingerprintUnavailable ? Commons.I18n.t("lock.fingerprintUnavailable") : "")
        color: root.errorState || root.fingerprintUnavailable ? "#ffb4bd" : root.dim
        font.family: root.fontFamily
        font.pixelSize: 13 * root.s
      }
    }

    // -------------------------------------------------------------- power
    Row {
      id: power
      transform: Translate { id: powerSlide }
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.height - height - 56 * root.s
      spacing: 40 * root.s
      PowerButton { label: "Sleep"; glyph: "󰤄"; command: ["systemctl", "suspend"] }
      PowerButton { label: "Restart"; glyph: "󰜉"; command: ["systemctl", "reboot"] }
      PowerButton { label: "Shut Down"; glyph: "󰐥"; command: ["systemctl", "poweroff"] }
    }
  }

  // ---------------------------------------------------------------- intro
  // Clock drops in from the top, card and power buttons rise from the bottom.
  ParallelAnimation {
    id: intro
    NumberAnimation { target: clockSlide; property: "y"; from: -root.height * 0.35; to: 0; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { targets: [cardSlide, powerSlide]; property: "y"; from: root.height * 0.35; to: 0; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { targets: [clock, card, power]; property: "opacity"; from: 0; to: 1; duration: 500; easing.type: Easing.OutQuad }
  }

  component PowerButton: Column {
    id: button
    property string label
    property string glyph
    property var command: []
    spacing: 8 * root.s
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 44 * root.s
      height: width
      radius: width / 2
      color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.1)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.25)
      Behavior on color { ColorAnimation { duration: 120 } }
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: button.glyph
        color: root.fg
        font.family: root.iconFont
        font.pixelSize: 20 * root.s
      }
      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.inputEnabled
        onClicked: Quickshell.execDetached(button.command)
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: button.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 12 * root.s
    }
  }
}
