#!/usr/bin/env bash
# Unlock the encrypted root disk with the TPM at boot (like BitLocker), so the
# only password you type is on the login screen. The disk password keeps
# working as a fallback (shown automatically if the TPM refuses, e.g. after a
# firmware or Secure Boot change).
#
#   scripts/enable-tpm-unlock.sh [KEYFILE]   KEYFILE holds the current disk password
#
# Undo: sudo systemd-cryptenroll --wipe-slot=tpm2 <luks partition>,
# remove /etc/mkinitcpio.conf.d/zz-xmilon-tpm-unlock.conf and tpm2-device=auto
# from /etc/default/limine, then sudo limine-mkinitcpio.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)

[[ -e /dev/tpmrm0 ]] || { echo "No TPM 2.0 found; nothing to do."; exit 0; }
dev=$(lsblk -nrpo NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')
[[ -n $dev ]] || { echo "No LUKS disk found; nothing to do."; exit 0; }
uuid=$(sudo cryptsetup luksUUID "$dev")

# 1. TPM key slot, sealed to PCR 7 (Secure Boot state).
if sudo cryptsetup luksDump "$dev" | grep -q 'systemd-tpm2'; then
  echo "TPM key already enrolled on $dev."
elif [[ -n ${1:-} ]]; then
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --unlock-key-file="$1" "$dev"
else
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$dev"
fi

# 2. systemd initramfs (busybox's encrypt hook can't use a TPM).
sudo install -Dm644 "$repo/system/etc/mkinitcpio.conf.d/zz-xmilon-tpm-unlock.conf" \
  /etc/mkinitcpio.conf.d/zz-xmilon-tpm-unlock.conf

# 3. Tell systemd-cryptsetup to try the TPM first.
if ! grep -q "rd.luks.options=$uuid=[^ \"]*tpm2-device=auto" /etc/default/limine; then
  sudo sed -i -E "s/(rd\.luks\.options=$uuid=[^ \"]*)/\1,tpm2-device=auto/" /etc/default/limine
fi
grep -q 'tpm2-device=auto' /etc/default/limine || { echo "Could not add tpm2-device=auto to /etc/default/limine" >&2; exit 1; }

# 4. Rebuild the boot image.
sudo limine-mkinitcpio
echo "TPM unlock enabled. Reboot to use it."
