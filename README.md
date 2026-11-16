# omarchy-dotfiles

My Omarchy (Arch + Hyprland) setup, ready to put on a new machine.

## New machine

Install Omarchy first, then:

```bash
git clone https://github.com/Xmilon/omarchy-dotfiles.git ~/Projects/omarchy-dotfiles
cd ~/Projects/omarchy-dotfiles
./install.sh
```

`./install.sh --configs` copies only the config files and skips packages.
Anything it replaces is backed up to `~/.dotfiles-backup/<date>/` first.

## Saving changes

After changing something on this machine:

```bash
cd ~/Projects/omarchy-dotfiles
./collect.sh
git add -A && git commit -m "Update setup" && git push
```

To track a new file, add its path (relative to your home folder) to `paths.txt`.

## What's in it

| Area | What |
|---|---|
| **Bar** (`.config/omarchy/shell.json`) | Centered middle group: indicators, music, clock, world clock, weather, notes (with the clipboard tab), with thin dividers. System info on the right. Floating windows get a restyled title bar (Inter, round buttons; `hypr/looknfeel.lua`). |
| **Music widget** (`plugins/xmilon.media`) | Left-click opens the popup, right-click play/pause. cava sound bars in the bar and a wave in the popup. `"vizDelayMs"` on its bar entry shifts the bars to match the sound. |
| **Quick Notes** (`plugins/xmilon.notes`) | Named pages that save as you type, with dates and pinning; images, videos and files inline at the cursor (paste, drop or attach); Ctrl+click opens links. Pages live in `~/Notes/Quick/` (not in this repo). A second **Clipboard** tab is Omarchy's clipboard history with search: click copies (the panel stays open), Enter or right-click pastes, Alt+Enter opens, Delete removes, Shift+Delete twice clears. Super+Alt+N opens notes, Super+Alt+V the clipboard; on the bar icon left-click = notes, right-click = clipboard. |
| **System Info** (`plugins/xmilon.sysinfo`) | CPU %, temperature and RAM in the bar; popup with GPU (nvidia-smi), VRAM, swap, disk, uptime. |
| **Indicators** (`plugins/xmilon.indicators`) | Always visible; only open when hovered themselves, with a slide animation. |
| **Ghostty** | Very translucent with blur, no title bar of its own (floating windows use the shared bar below), no animated shaders (idle ~0% CPU), grey-blue selection that doesn't copy on select; with a mouse selection, Backspace/Delete/Ctrl+X edit the command line; Ctrl+C copies a selection. |
| **Command line** (`.blerc`, ble.sh) | IDE-like completion, no syntax colours, Shift+arrow selection and Ctrl+A select-all with Backspace / Ctrl+C / Ctrl+X / typing-replaces; Ctrl+V pastes (in the shell only, so nano/vim keep theirs). |
| **Files** (`.config/gtk-4.0/gtk.css`) | See-through panels over the blur, rounded hover and selection. |
| **Hyprland** | Super+scroll switches workspaces without the 300 ms delay and slides; Super+middle-click opens a new empty workspace; 1080p@180 external monitor; GDK scale 1 (normal-size Steam); digital vibrance at login. |
| **Wallpapers** (`.config/omarchy/backgrounds/gruvpink`) | My wallpapers added to the gruvpink theme, so Super+Ctrl+Space cycles through them along with its own. |
| **Icons** | Conflux, with Papirus-Dark as fallback; a theme hook keeps them after theme changes. |
| **fastfetch** | GitHub avatar, XMILON gradient banner. |
| **SpotX** | Pacman hook that re-applies SpotX after each Spotify update (`system/`). |

Packages are listed in `packages/` (official repos, AUR, Flathub, themes).

## Manual steps

These aren't automated:

- **AppImages** in `~/Applications`: Liner (from github.com/tryliner/desktop) and spotifast.
  Install each with `appimage-integrator install <file>` or right-click → AppImage → Install.
- **Artcraft**: install from its own launcher download (it isn't on Flathub).
- **Windows drive / migration data**: not part of this repo.
