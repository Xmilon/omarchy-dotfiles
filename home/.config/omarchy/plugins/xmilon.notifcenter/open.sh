#!/bin/bash
# Brings up whatever a notification came from, when the Notification Center's
# card is clicked. The notification itself is usually gone by then (its app's
# own "click" action dies with it), so this tries, in order:
#   1. the command Omarchy stored with it (screenshots: open the image),
#   2. a handler for apps that have no window (hchat: open hchat-app),
#   3. the window of the process that sent it,
#   4. any window of that app,
#   5. launching the app.
# Usage: open.sh <app> <sender-pid> <exec-argv-json>
app=${1:-}
pid=${2:-0}
argv_json=${3:-}

focus_address() {
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
}

# 1. Omarchy's stored command, a JSON argv list. Run as a list, never a shell string.
if [[ -n $argv_json && $argv_json != "[]" ]]; then
  mapfile -d '' -t argv < <(jq -j '.[] | tostring + "\u0000"' <<<"$argv_json" 2>/dev/null)
  if (( ${#argv[@]} > 0 )); then
    setsid -f "${argv[@]}" >/dev/null 2>&1
    exit 0
  fi
fi

# 2. Apps without a window of their own.
case "${app,,}" in
  hchat)
    # The hchat app: focus it if open, else start it.
    if command -v hchat-app >/dev/null; then
      omarchy-hyprland-focus-app hchat-app || setsid -f uwsm-app -- hchat-app.desktop >/dev/null 2>&1
      exit 0
    fi
    ;;
esac

# 3. The window of the process that sent it, or of its parent (helpers often
#    notify on behalf of the app's main process).
p=$pid
for _ in 1 2 3; do
  [[ $p =~ ^[0-9]+$ ]] && (( p > 1 )) || break
  address=$(hyprctl clients -j 2>/dev/null | jq -r --argjson pid "$p" 'first(.[] | select(.pid == $pid)).address // empty')
  if [[ -n $address ]]; then
    focus_address "$address"
    exit 0
  fi
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done

[[ -n $app ]] || exit 1

# 4. Any window of that app.
omarchy-hyprland-focus-app "$app" && exit 0

# 5. Launch it: a desktop file named after it, or whose Name or StartupWMClass is it.
desktop=""
for dir in ~/.local/share/applications /usr/share/applications /var/lib/flatpak/exports/share/applications ~/.local/share/flatpak/exports/share/applications; do
  [[ -d $dir ]] || continue
  if [[ -f $dir/$app.desktop ]]; then desktop=$app; break; fi
  found=$(grep -l -i -E "^(Name|StartupWMClass)=${app//./\\.}\$" "$dir"/*.desktop 2>/dev/null | head -n1)
  if [[ -n $found ]]; then desktop=$(basename "$found" .desktop); break; fi
done
[[ -n $desktop ]] || exit 1
setsid -f uwsm-app -- "$desktop.desktop" >/dev/null 2>&1 || setsid -f gtk-launch "$desktop" >/dev/null 2>&1
