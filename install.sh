#!/usr/bin/env bash
# Put this Omarchy setup on a fresh machine.
#
#   ./install.sh            everything
#   ./install.sh --configs  only copy config files (no packages)
#
# Existing files are backed up to ~/.dotfiles-backup/<timestamp>/ before being replaced.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
ONLY_CONFIGS=0
[[ ${1-} == --configs ]] && ONLY_CONFIGS=1

say()  { printf '\e[36m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[33m !\e[0m %s\n' "$*"; }
list() { grep -vE '^\s*(#|$)' "$1"; }

command -v omarchy >/dev/null || { echo "This setup is for Omarchy; omarchy was not found." >&2; exit 1; }

# ---------------------------------------------------------------- packages
if ((ONLY_CONFIGS == 0)); then
  say "Installing packages from the official repos"
  mapfile -t pkgs < <(list "$REPO/packages/pacman.txt")
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"

  say "Installing AUR packages"
  mapfile -t aur < <(list "$REPO/packages/aur.txt")
  for p in "${aur[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || omarchy pkg aur add "$p" || warn "Could not install $p"
  done

  say "Installing Flathub apps"
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  while read -r app; do
    flatpak install --user -y --noninteractive flathub "$app" || warn "Could not install $app"
  done < <(list "$REPO/packages/flatpak.txt")

  say "Installing ble.sh (command-line completion and selection)"
  if [[ ! -r $HOME/.local/share/blesh/ble.sh ]]; then
    tmp=$(mktemp -d)
    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "$tmp/ble.sh"
    make -C "$tmp/ble.sh" install PREFIX="$HOME/.local"
    rm -rf "$tmp"
  fi

  say "Installing the Conflux icon theme"
  icons="$HOME/.local/share/icons/Conflux"
  [[ -d $icons ]] || git clone --depth 1 https://github.com/MoshiurRahmanAdib/Conflux-Icon-Theme.git "$icons"
  # Apps Conflux doesn't theme keep their own icons; Papirus fills any gaps.
  sed -i 's/^Inherits=.*/Inherits=hicolor,Adwaita,breeze,Papirus-Dark/' "$icons/index.theme"
  rm -f "$icons/icon-theme.cache" "$icons/.icon-theme.cache"

  say "Installing themes"
  while read -r url; do
    name=$(basename "$url" .git)
    ls "$HOME/.config/omarchy/themes" 2>/dev/null | grep -qix "${name#omarchy-}" \
      || omarchy theme install "$url" </dev/null >/dev/null 2>&1 || warn "Could not install theme $url"
  done < <(list "$REPO/packages/themes.txt")

  say "Installing appimage-integrator (right-click AppImages in Files)"
  if ! command -v appimage-integrator >/dev/null; then
    tmp=$(mktemp -d)
    git clone --depth 1 https://github.com/Xmilon/appimage-integrator.git "$tmp/ai"
    (cd "$tmp/ai" && ./install.sh)
    rm -rf "$tmp"
  fi
fi

# Install the complete upstream plugins before copying our small local overrides.
if ((ONLY_CONFIGS == 0)); then
  while IFS='|' read -r plugin_id plugin_url plugin_ref; do
    plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
    if [[ ! -d $plugin_dir ]]; then
      omarchy plugin add "$plugin_url" --yes
      git -C "$plugin_dir" fetch --depth 1 origin "$plugin_ref"
      git -C "$plugin_dir" checkout --detach "$plugin_ref"
    fi
  done < <(list "$REPO/packages/plugins.txt")

  say "Installing the Thyx login screen (keeps the current session running)"
  thyx_source="$HOME/.local/share/thyx"
  if [[ ! -d $thyx_source ]]; then
    git clone https://github.com/rccyx/thyx.git "$thyx_source"
    git -C "$thyx_source" checkout --detach "$(head -1 "$REPO/packages/thyx-ref.txt")"
  fi
  (cd "$thyx_source" && ./scripts/install --yes)
fi

# ---------------------------------------------------------------- configs
say "Copying config files (backups go to $BACKUP)"
while read -r rel; do
  src="$REPO/home/$rel"
  dst="$HOME/$rel"
  [[ -e $src ]] || { warn "Not in repo: $rel"; continue; }
  if [[ -e $dst ]]; then
    mkdir -p "$(dirname "$BACKUP/$rel")"
    cp -a "$dst" "$BACKUP/$rel"
    rm -rf "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
done < <(list "$REPO/paths.txt")
chmod +x "$HOME/.config/omarchy/hooks/theme-set.d/conflux-icons.sh"
chmod +x "$HOME/.local/bin/omarchy-app-updates"
chmod +x "$HOME/.local/bin/xmilon-screensaver-guard"
if ((ONLY_CONFIGS == 0)); then
  bash "$REPO/scripts/install-thyx-custom.sh"
fi

# Iotas starts over D-Bus by default, which can't find Flatpak apps here;
# a local launcher entry starts it directly.
iotas="$HOME/.local/share/flatpak/exports/share/applications/org.gnome.World.Iotas.desktop"
if [[ -f $iotas ]]; then
  sed 's/^DBusActivatable=true/DBusActivatable=false/' "$iotas" > "$HOME/.local/share/applications/org.gnome.World.Iotas.desktop"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# ---------------------------------------------------------------- system files
if ((ONLY_CONFIGS == 0)) && command -v spotify >/dev/null; then
  say "SpotX: patch Spotify and re-apply it after every Spotify update"
  sudo install -d /usr/local/share/spotx
  sudo curl -fsSL -o /usr/local/share/spotx/spotx.sh \
    https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh
  sudo install -Dm755 "$REPO/system/usr/local/bin/spotx-reapply" /usr/local/bin/spotx-reapply
  sudo install -Dm644 "$REPO/system/etc/pacman.d/hooks/spotx.hook" /etc/pacman.d/hooks/spotx.hook
  sudo /usr/local/bin/spotx-reapply || warn "SpotX did not apply; run spotx-reapply later"
fi

if ((ONLY_CONFIGS == 0)); then
  say "Super+Space menu: Back returns to the row you came from (re-applied after Omarchy updates)"
  sudo install -Dm755 "$REPO/system/usr/local/bin/omarchy-menu-back-patch" /usr/local/bin/omarchy-menu-back-patch
  sudo install -Dm644 "$REPO/system/etc/pacman.d/hooks/omarchy-menu-back.hook" /etc/pacman.d/hooks/omarchy-menu-back.hook
  sudo /usr/local/bin/omarchy-menu-back-patch || warn "Menu Back patch skipped (Omarchy's menu changed)"

  say "Bar popups: bouncy open / quick close (re-applied after Omarchy updates)"
  sudo install -Dm755 "$REPO/system/usr/local/bin/omarchy-popup-anim-patch" /usr/local/bin/omarchy-popup-anim-patch
  sudo install -Dm644 "$REPO/system/etc/pacman.d/hooks/omarchy-popup-anim.hook" /etc/pacman.d/hooks/omarchy-popup-anim.hook
  sudo /usr/local/bin/omarchy-popup-anim-patch || warn "Popup animation patch skipped (Omarchy changed)"

  say "Bar: stays on the background set in shell.json (double-click no longer cycles it)"
  sudo install -Dm755 "$REPO/system/usr/local/bin/omarchy-bar-lock-patch" /usr/local/bin/omarchy-bar-lock-patch
  sudo install -Dm644 "$REPO/system/etc/pacman.d/hooks/omarchy-bar-lock.hook" /etc/pacman.d/hooks/omarchy-bar-lock.hook
  sudo /usr/local/bin/omarchy-bar-lock-patch || warn "Bar background lock skipped (Omarchy's bar changed)"
  # Per-app notification mute (read by the notification center).
  sudo install -Dm755 "$REPO/system/usr/local/bin/omarchy-notif-mute-patch" /usr/local/bin/omarchy-notif-mute-patch
  sudo install -Dm644 "$REPO/system/etc/pacman.d/hooks/omarchy-notif-mute.hook" /etc/pacman.d/hooks/omarchy-notif-mute.hook
  sudo /usr/local/bin/omarchy-notif-mute-patch || warn "Per-app notification mute skipped (Omarchy's notifications changed)"

  say "Pamac: AUR enabled"
  [[ -f /etc/pamac.conf ]] && sudo sed -i -E 's/^#(EnableAUR|CheckAURUpdates)$/\1/' /etc/pamac.conf

  say "Outfit font (clocks)"
  sudo install -Dm644 "$REPO/system/usr/local/share/fonts/outfit/Outfit.ttf" /usr/local/share/fonts/outfit/Outfit.ttf
  sudo install -Dm644 "$REPO/system/usr/local/share/fonts/outfit/OFL.txt" /usr/local/share/fonts/outfit/OFL.txt
  sudo fc-cache -f /usr/local/share/fonts >/dev/null

  say "Lock screen: same look as the login screen (re-applied after Omarchy updates)"
  sudo install -Dm644 "$REPO/system/usr/share/omarchy/shell/plugins/lock/LockView.qml" /usr/local/share/xmilon/LockView.qml
  sudo install -Dm644 "$REPO/system/usr/share/omarchy/shell/plugins/lock/NowPlaying.qml" /usr/local/share/xmilon/NowPlaying.qml
  sudo install -Dm755 "$REPO/system/usr/local/bin/omarchy-lock-view-install" /usr/local/bin/omarchy-lock-view-install
  sudo install -Dm644 "$REPO/system/etc/pacman.d/hooks/omarchy-lock-view.hook" /etc/pacman.d/hooks/omarchy-lock-view.hook
  sudo /usr/local/bin/omarchy-lock-view-install
fi

# ---------------------------------------------------------------- apply
say "Applying"
if [[ -s $REPO/packages/current-theme.txt ]]; then
  omarchy theme set "$(head -1 "$REPO/packages/current-theme.txt")" >/dev/null 2>&1 || warn "Set your theme with: omarchy theme set <name>"
fi
gsettings set org.gnome.desktop.interface icon-theme 'Conflux' || true
hyprctl reload >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
omarchy restart terminal >/dev/null 2>&1 || true

printf '\e[32m ✓\e[0m Done. Open a new terminal to get the new shell settings.\n'
echo "   Manual steps are listed in README.md (Artcraft, Liner and spotifast AppImages, theme)."
