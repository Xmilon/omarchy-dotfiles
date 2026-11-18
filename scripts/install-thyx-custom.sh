#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
theme=/usr/share/sddm/themes/thyx
owner=$(id -un)
[[ -f $theme/metadata.desktop ]] || { echo "Install upstream Thyx first." >&2; exit 1; }
python -c 'from PIL import Image'
backup="/var/lib/thyx-backups/$(date +%Y%m%d-%H%M%S)"
sudo install -d -m 700 "$backup"
sudo cp -a "$theme/src/Main.qml" "$theme/theme.conf" "$backup/"
sudo install -Dm755 "$repo/system/usr/local/lib/thyx-sync-background" /usr/local/lib/thyx-sync-background
sudo install -Dm644 "$repo/system/etc/systemd/system/thyx-background@.service" /etc/systemd/system/thyx-background@.service
sudo install -Dm644 "$repo/system/etc/systemd/system/thyx-background@.path" /etc/systemd/system/thyx-background@.path
sudo install -Dm644 "$repo/system/usr/share/sddm/themes/thyx/src/Main.qml" "$theme/src/Main.qml"
sudo install -Dm644 "$repo/system/usr/share/sddm/themes/thyx/theme.conf" "$theme/theme.conf"
sudo install -d -m755 "$theme/avatars"
sudo ln -sfn "/var/lib/thyx-$owner/background.jpg" "$theme/backgrounds/xmilon-current.jpg"
sudo ln -sfn "/var/lib/thyx-$owner/avatar.png" "$theme/avatars/xmilon-current.png"
sudo ln -sfn "/var/lib/thyx-$owner/theme.conf.user" "$theme/theme.conf.user"
sudo systemctl daemon-reload
sudo systemctl start "thyx-background@$owner.service"
sudo systemctl enable --now "thyx-background@$owner.path"
sudo install -Dm644 "$repo/system/usr/local/share/xmilon/sddm-hyprland.lua" /usr/local/share/xmilon/sddm-hyprland.lua
sudo install -Dm644 "$repo/system/etc/sddm.conf.d/zz-thyx-login.conf" /etc/sddm.conf.d/zz-thyx-login.conf
# Boot screen (Plymouth) matching the login; images re-rendered on every boot-image build.
sudo install -Dm755 "$repo/system/usr/local/lib/xmilon-plymouth-render" /usr/local/lib/xmilon-plymouth-render
sudo install -Dm644 "$repo/system/etc/initcpio/install/xmilon-plymouth" /etc/initcpio/install/xmilon-plymouth
sudo install -Dm644 "$repo/system/usr/share/plymouth/themes/xmilon/xmilon.plymouth" /usr/share/plymouth/themes/xmilon/xmilon.plymouth
sudo install -Dm644 "$repo/system/usr/share/plymouth/themes/xmilon/xmilon.script" /usr/share/plymouth/themes/xmilon/xmilon.script
sudo /usr/local/lib/xmilon-plymouth-render
sudo plymouth-set-default-theme xmilon
echo "Installed custom Thyx. Autologin is off; the current session stays open."
