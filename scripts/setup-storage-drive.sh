#!/usr/bin/env bash
# Turn a second drive into ~/Storage, like a "D:" drive on Windows.
#
#   scripts/setup-storage-drive.sh /dev/nvme1n1     ERASES THE WHOLE DRIVE
#
# One encrypted partition (LUKS2). It unlocks at boot with a key file kept on the
# main drive (/etc/cryptsetup-keys.d/storage.key), which is itself encrypted, so
# there is no second password. Without the main drive (or that key file) the data
# can't be read, so keep a copy of the key somewhere safe if you want a fallback:
#   sudo cryptsetup luksAddKey /dev/<disk>p1 --key-file /etc/cryptsetup-keys.d/storage.key
# adds a password you can type instead.
#
# ext4 mounted at ~/Storage, with nofail: if the drive is missing, boot carries on.
set -euo pipefail
dev=${1:?usage: $0 /dev/<disk>}
[ -b "$dev" ] || { echo "$dev is not a disk" >&2; exit 1; }
root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /boot)")
[ "/dev/$root_disk" != "$dev" ] || { echo "$dev holds /boot, refusing" >&2; exit 1; }

lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "$dev"
read -rp "Erase everything on $dev? Type YES: " ok
[ "$ok" = YES ] || exit 1

for p in $(lsblk -lnpo NAME "$dev" | tail -n +2); do
  findmnt -rn -S "$p" >/dev/null && udisksctl unmount -b "$p"
done
case $dev in *[0-9]) part=${dev}p1 ;; *) part=${dev}1 ;; esac

printf 'label: gpt\ntype=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="Storage"\n' |
  sudo sfdisk -q --wipe always --wipe-partitions always "$dev"
sudo udevadm settle
sudo blkdiscard -f "$part" || true

key=/etc/cryptsetup-keys.d/storage.key
sudo install -d -m700 /etc/cryptsetup-keys.d
sudo test -f $key || sudo sh -c "umask 077; head -c 64 /dev/urandom > $key"
sudo cryptsetup luksFormat -q --type luks2 --label Storage --key-file $key "$part"
sudo cryptsetup open --key-file $key --allow-discards --persistent "$part" storage
sudo mkfs.ext4 -q -L Storage -m 0 /dev/mapper/storage

uuid=$(sudo cryptsetup luksUUID "$part")
sudo sed -i '/^storage /d' /etc/crypttab
echo "storage UUID=$uuid $key luks,discard,nofail" | sudo tee -a /etc/crypttab >/dev/null
mkdir -p "$HOME/Storage"
sudo sed -i '\|^/dev/mapper/storage |d' /etc/fstab
echo "/dev/mapper/storage $HOME/Storage ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2" |
  sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload
sudo mount "$HOME/Storage"
sudo chown "$USER:$USER" "$HOME/Storage"

bm="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$bm")"
grep -qs "file://$HOME/Storage " "$bm" || echo "file://$HOME/Storage Storage" >> "$bm"
df -h "$HOME/Storage"
