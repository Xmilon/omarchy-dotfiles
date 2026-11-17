import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../xmilon.media/Timeline.js" as Timeline

Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property var players: Mpris.players.values
  readonly property var player: {
    for (var i = 0; i < players.length; ++i)
      if (String(players[i].desktopEntry).toLowerCase() === "spotify"
          || String(players[i].identity).toLowerCase() === "spotify") return players[i]
    return null
  }
  readonly property bool connected: player !== null
  readonly property string title: player ? player.trackTitle || "Spotify" : "Open Spotify to connect"
  readonly property string artist: player ? player.trackArtist || "" : ""
  readonly property real length: player && player.lengthSupported ? Timeline.seconds(player.length) : 0
  readonly property real position: player && player.positionSupported ? Timeline.seconds(player.position) : 0
  readonly property bool canSeek: !!player && player.canSeek && player.positionSupported && length > 0
  property bool panelVisible: false
  function seek(value) { if (canSeek) player.position = Timeline.seekTarget(value, length) }
  function playPause() { if (player && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }
  function launch(uri) {
    Quickshell.execDetached(uri ? ["spotify", "--uri=" + uri] : ["spotify"])
  }
  function search(term) { if (term.trim()) launch("spotify:search:" + encodeURIComponent(term.trim().slice(0, 200))) }
  Timer {
    interval: 500
    repeat: true
    running: root.panelVisible && !!root.player && root.player.positionSupported && root.player.isPlaying
    onTriggered: root.player.positionChanged()
  }
  IpcHandler {
    target: "quickshell.spotify.player"
    function status(): string {
      return JSON.stringify({mode: "desktop", connected: root.connected, title: root.title,
        canSeek: root.canSeek, position: root.position, length: root.length})
    }
    function toggleFullPlayer(): string { root.shell.toggle("quickshell.spotify", "{}"); return "ok" }
    function togglePlayer(): string { root.shell.toggle("quickshell.spotify", "{}"); return "ok" }
    function playPause(): string { root.playPause(); return root.connected ? "ok" : "unavailable" }
  }
}
