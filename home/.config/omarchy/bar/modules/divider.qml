import QtQuick

// A thin vertical line that separates neighbouring bar widgets.
Item {
  property var bar
  property string moduleName
  property var settings

  implicitWidth: 17
  implicitHeight: bar ? bar.barSize : 26

  Rectangle {
    anchors.centerIn: parent
    width: 1
    height: Math.round(parent.height * 0.45)
    radius: 1
    color: bar ? bar.foreground : "white"
    opacity: 0.3
  }
}
