// Xmilon login screen for SDDM, built on the Thyx theme folder.
// Blurred current wallpaper, clock, round avatar, a single password field and
// labelled power buttons. Colours come from theme.conf.user, which
// thyx-sync-background rewrites whenever the wallpaper changes.
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#0b1118"

    readonly property var cfg: typeof config !== "undefined" ? config : ({})
    readonly property var sddmApi: typeof sddm !== "undefined" ? sddm : null
    readonly property color accent: cfg.AccentColor || "#a6bfd1"
    readonly property color fg: "#f2f5f8"
    readonly property color dim: "#c3ccd5"
    readonly property string fontFamily: cfg.Font || "Plus Jakarta Sans"
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property real s: Math.max(0.75, Math.min(width / 1920, height / 1080) * 1.0)

    readonly property string lastUser: typeof userModel !== "undefined" && userModel.lastUser ? userModel.lastUser : ""
    readonly property string userName: lastUser !== "" ? lastUser : userField.text
    readonly property int sessionIndex: typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

    property date now: new Date()
    property bool busy: false
    property string error: ""

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    function login() {
        if (busy || !sddmApi || userName === "" || passwordField.text === "") return
        busy = true
        error = ""
        sddmApi.login(userName, passwordField.text, sessionIndex)
    }

    Connections {
        target: root.sddmApi
        ignoreUnknownSignals: true
        function onLoginFailed() {
            root.busy = false
            root.error = "Wrong password"
            passwordField.text = ""
            passwordField.forceActiveFocus()
            shake.restart()
        }
        function onLoginSucceeded() { root.busy = false }
    }

    // ------------------------------------------------------------ background
    Image {
        id: wallpaper
        anchors.fill: parent
        source: Qt.resolvedUrl("../" + (root.cfg.Background || "backgrounds/xmilon-current.jpg"))
        sourceSize: Qt.size(Math.round(root.width / 2), Math.round(root.height / 2))
        fillMode: Image.PreserveAspectCrop
        cache: false
        visible: false
    }
    FastBlur {
        anchors.fill: parent
        source: wallpaper
        radius: 64
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.28 }

    // ------------------------------------------------------------ clock
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.13
        spacing: 2 * root.s
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "HH:mm")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 112 * root.s
            font.weight: Font.Light
            textFormat: Text.PlainText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "dddd, d MMMM")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 20 * root.s
            textFormat: Text.PlainText
        }
    }

    // ------------------------------------------------------------ login
    Column {
        id: form
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.height * 0.08
        spacing: 14 * root.s

        Item {
            id: avatarBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96 * root.s
            height: width
            Image {
                id: avatar
                anchors.fill: parent
                source: Qt.resolvedUrl("../" + (root.cfg.Avatar || "avatars/xmilon-current.png"))
                sourceSize: Qt.size(256, 256)
                fillMode: Image.PreserveAspectCrop
                cache: false
                visible: false
            }
            Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; visible: false }
            OpacityMask { anchors.fill: parent; source: avatar; maskSource: avatarMask }
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
            text: root.cfg.DisplayName || root.userName || "Welcome"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 22 * root.s
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }

        // Only shown when SDDM has no remembered user.
        Pill {
            id: userPill
            visible: root.lastUser === ""
            TextField {
                id: userField
                anchors.fill: parent
                anchors.leftMargin: 18 * root.s
                anchors.rightMargin: 18 * root.s
                placeholderText: "Username"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.55)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 15 * root.s
                background: null
                verticalAlignment: TextInput.AlignVCenter
                KeyNavigation.tab: passwordField
                onAccepted: passwordField.forceActiveFocus()
            }
        }

        Pill {
            id: passwordPill
            border.color: passwordField.activeFocus ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(1, 1, 1, 0.22)
            TextField {
                id: passwordField
                anchors.fill: parent
                anchors.leftMargin: 18 * root.s
                anchors.rightMargin: 46 * root.s
                placeholderText: "Enter password"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.55)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 15 * root.s
                echoMode: TextInput.Password
                passwordCharacter: "•"
                background: null
                verticalAlignment: TextInput.AlignVCenter
                enabled: !root.busy
                focus: true
                onAccepted: root.login()
                onTextChanged: if (text !== "") root.error = ""
            }
            Rectangle {
                id: goButton
                anchors.right: parent.right
                anchors.rightMargin: 6 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 12 * root.s
                height: width
                radius: width / 2
                color: goArea.containsMouse ? root.fg : Qt.rgba(1, 1, 1, 0.85)
                opacity: passwordField.text === "" ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "…" : "→"
                    color: "#0d1721"
                    font.family: root.fontFamily
                    font.pixelSize: 16 * root.s
                    font.weight: Font.Bold
                }
                MouseArea {
                    id: goArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.login()
                }
            }
            SequentialAnimation {
                id: shake
                loops: 1
                NumberAnimation { target: passwordPill; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
                NumberAnimation { target: passwordPill; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
                NumberAnimation { target: passwordPill; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
                NumberAnimation { target: passwordPill; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18 * root.s
            text: root.error !== "" ? root.error
                : (typeof keyboard !== "undefined" && keyboard.capsLock ? "Caps Lock is on" : "")
            color: root.error !== "" ? "#ffb4bd" : root.dim
            font.family: root.fontFamily
            font.pixelSize: 13 * root.s
            textFormat: Text.PlainText
        }
    }

    // ------------------------------------------------------------ power
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56 * root.s
        spacing: 40 * root.s
        PowerButton { label: "Sleep"; glyph: "󰤄"; shown: root.sddmApi && root.sddmApi.canSuspend; onActivated: root.sddmApi.suspend() }
        PowerButton { label: "Restart"; glyph: "󰜉"; shown: root.sddmApi && root.sddmApi.canReboot; onActivated: root.sddmApi.reboot() }
        PowerButton { label: "Shut Down"; glyph: "󰐥"; shown: root.sddmApi && root.sddmApi.canPowerOff; onActivated: root.sddmApi.powerOff() }
    }

    Component.onCompleted: (root.lastUser === "" ? userField : passwordField).forceActiveFocus()

    // ------------------------------------------------------------ components
    component Pill: Rectangle {
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        width: 300 * root.s
        height: 46 * root.s
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }

    component PowerButton: Column {
        id: button
        property string label
        property string glyph
        property bool shown: true
        signal activated()
        visible: shown
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
                onClicked: button.activated()
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: button.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 12 * root.s
        }
    }
}
