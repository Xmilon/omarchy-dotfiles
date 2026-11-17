import QtQuick

// A gap between bar widgets. With the islands module (islands.qml) each gap
// ends one rounded island and starts the next.
// Settings: "size" sets its width in px (default 14).
Item {
  property var bar
  property string moduleName
  property var settings

  implicitWidth: settings && settings.size !== undefined ? settings.size : 14
  implicitHeight: bar ? bar.barSize : 26
}
