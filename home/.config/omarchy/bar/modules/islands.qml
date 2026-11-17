import QtQuick

// Draws the bar as rounded "islands": a pill behind each group of widgets.
// Groups are split at dividers and spacers, so put a divider wherever one
// island should end and the next begin. Takes no room itself; put it first in
// the left section. Use with the bar background set to clear ("none").
//
// It finds the bar's own section lists (the left, center and right rows of
// widgets) and draws behind them, without changing Omarchy's bar code. If a
// later Omarchy update changes how the bar is built, it simply draws nothing.
//
// Settings (on its bar entry, all optional):
//   inset    space above and below each island, px (default 3)
//   pad      how far an island reaches past its first and last widget (4)
//   radius   corner rounding, px (default 9)
//   opacity  island background opacity, 0-1 (default 0.92)
Item {
  id: islands

  property var bar
  property string moduleName
  property var settings

  implicitWidth: 0
  implicitHeight: bar ? bar.barSize : 26

  function setting(name, fallback) {
    return settings && settings[name] !== undefined ? settings[name] : fallback
  }
  readonly property real inset: setting("inset", 3)
  readonly property real pad: setting("pad", 4)
  readonly property real radius: setting("radius", 9)
  readonly property real fillOpacity: setting("opacity", 0.92)
  readonly property color fg: bar ? bar.foreground : "white"
  readonly property color bg: bar ? bar.background : "black"

  property var layers: []

  function isGap(key) { return /^(divider|islands)|spacer/.test(String(key || "")) }

  function surfaceRoot() {
    var p = islands
    while (p && p.parent) p = p.parent
    return p
  }

  // The bar's section lists: GridLayouts with the bar's region and keys.
  function findLists(item, out) {
    if (!item) return
    if (item.listRows !== undefined && item.region !== undefined && item.keys !== undefined
        && item.region !== "tray") out.push(item)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) findLists(kids[i], out)
  }

  function scan() {
    var found = []
    findLists(surfaceRoot(), found)
    var same = found.length === layers.length
    for (var i = 0; same && i < found.length; i++) if (!layers[i] || layers[i].list !== found[i]) same = false
    if (same) {
      for (var r = 0; r < layers.length; r++) layers[r].regroup()
      return
    }
    clearLayers()
    var made = []
    for (var j = 0; j < found.length; j++) {
      var layer = layerComponent.createObject(found[j].parent, { list: found[j] })
      if (layer) made.push(layer)
    }
    layers = made
  }

  function clearLayers() {
    for (var i = 0; i < layers.length; i++) if (layers[i]) layers[i].destroy()
    layers = []
  }

  Component.onCompleted: Qt.callLater(scan)
  Component.onDestruction: clearLayers()

  // The bar builds its sections after its widgets; look again until they
  // are all there, then now and then in case the bar rebuilt them.
  Timer {
    interval: 1500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: islands.scan()
  }

  Component {
    id: layerComponent

    Item {
      id: sectionLayer
      property var list: null
      property var segments: []
      property string signature: ""

      z: -1
      x: list ? list.x : 0
      y: list ? list.y : 0
      width: list ? list.width : 0
      height: list ? list.height : 0
      visible: !!list && list.visible

      // Split the list's widgets into islands at dividers and spacers.
      function regroup() {
        if (!list) { segments = []; return }
        var slots = []
        var kids = list.children
        for (var i = 0; i < kids.length; i++) {
          var k = kids[i]
          if (k.widgetKey !== undefined && k.widgetKey !== "" && k.visible && k.width > 0.5) slots.push(k)
        }
        slots.sort(function(a, b) { return a.x - b.x })
        var out = [], current = null
        for (var j = 0; j < slots.length; j++) {
          if (islands.isGap(slots[j].widgetKey)) { current = null; continue }
          if (!current) { current = { first: slots[j], last: slots[j] }; out.push(current) }
          else current.last = slots[j]
        }
        // Only rebuild the islands when the grouping really changed; their
        // positions and sizes follow the widgets live through bindings.
        var sig = out.map(function(s) { return s.first.widgetKey + ">" + s.last.widgetKey }).join("|")
        if (sig === signature) return
        signature = sig
        segments = out
      }

      Timer { id: regroupTimer; interval: 40; onTriggered: sectionLayer.regroup() }
      Connections {
        target: sectionLayer.list
        function onChildrenChanged() { regroupTimer.restart() }
        function onWidthChanged() { regroupTimer.restart() }
        function onKeysChanged() { regroupTimer.restart() }
        function onVisibleChanged() { regroupTimer.restart() }
      }
      Component.onCompleted: regroup()

      Repeater {
        model: sectionLayer.segments

        Rectangle {
          required property var modelData
          readonly property real startX: modelData.first.x - islands.pad
          readonly property real endX: modelData.last.x + modelData.last.width + islands.pad

          x: startX
          width: endX - startX
          y: islands.inset
          height: sectionLayer.height - islands.inset * 2
          radius: Math.min(islands.radius, height / 2)
          color: Qt.rgba(islands.bg.r, islands.bg.g, islands.bg.b, islands.fillOpacity)
          border.width: 1
          border.color: Qt.rgba(islands.fg.r, islands.fg.g, islands.fg.b, 0.09)
          antialiasing: true

          // Islands appear with a small grow-and-fade.
          opacity: 0
          scale: 0.92
          Component.onCompleted: { opacity = 1; scale = 1 }
          Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        }
      }
    }
  }
}
