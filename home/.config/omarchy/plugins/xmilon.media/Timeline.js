function seconds(value) {
  var number = Number(value)
  return isFinite(number) ? Math.max(0, number) : 0
}

function timeLabel(value) {
  var total = Math.floor(seconds(value))
  var minutes = Math.floor(total / 60)
  return minutes + ":" + (total % 60 < 10 ? "0" : "") + total % 60
}

function seekTarget(value, duration) {
  return Math.min(seconds(duration), seconds(value))
}

function tooltip(value) {
  return String(value || "").slice(0, 512).replace(/&/g, "&amp;")
    .replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
