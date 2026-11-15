#!/usr/bin/env bash
# Copy the current setup from this machine into the repo (run before committing).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

grep -vE '^\s*(#|$)' "$REPO/paths.txt" | while read -r rel; do
  src="$HOME/$rel"
  dst="$REPO/home/$rel"
  if [[ ! -e $src ]]; then
    printf '\e[33m skip\e[0m %s (missing)\n' "$rel"
    continue
  fi
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  printf '\e[32m  got\e[0m %s\n' "$rel"
done

# Never commit caches.
find "$REPO/home" -name '__pycache__' -type d -prune -exec rm -rf {} +

# System files (pacman hook that re-applies SpotX after Spotify updates).
cp /etc/pacman.d/hooks/spotx.hook "$REPO/system/etc/pacman.d/hooks/" 2>/dev/null || true
cp /usr/local/bin/spotx-reapply "$REPO/system/usr/local/bin/" 2>/dev/null || true

# Themes installed from git, and the one in use.
{
  echo "# Omarchy themes installed from git (URL per line). install.sh reinstalls them."
  for d in "$HOME/.config/omarchy/themes"/*/; do
    url=$(git -C "$d" remote get-url origin 2>/dev/null) && echo "$url"
  done
} > "$REPO/packages/themes.txt"
omarchy theme current > "$REPO/packages/current-theme.txt" 2>/dev/null || true

echo "Done. Review with: git -C \"$REPO\" status"
