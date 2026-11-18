#!/usr/bin/env bash
# Unlock the encrypted root disk with the TPM at boot (like BitLocker), so the
# only password you type is on the login screen. The disk password keeps
# working as a fallback (shown automatically if the TPM refuses, e.g. after a
# firmware or Secure Boot change).
#
#   scripts/enable-tpm-unlock.sh [--reseal] [KEYFILE]
#     KEYFILE  holds the current disk password (asked for if missing)
#     --reseal replace the TPM key, e.g. after turning Secure Boot on or
#              changing the kernel command line (both change what it's sealed to)
#
# Sealed to PCR 7 (Secure Boot state and keys) and PCR 12 (the kernel command
# line, measured by systemd-stub), so editing the command line at the boot menu
# can't unlock the disk. Both are measured before the disk is unlocked, which
# needs the systemd initramfs (it also records the os-separator in PCR 7/12
# there; the old busybox one didn't, which is why a key sealed under it broke).
#
# Undo: sudo systemd-cryptenroll --wipe-slot=tpm2 <luks partition>,
# remove /etc/mkinitcpio.conf.d/zz-xmilon-tpm-unlock.conf and tpm2-device=auto
# from /etc/default/limine, then sudo limine-mkinitcpio.
set -euo pipefail
reseal=0
[[ ${1:-} == --reseal ]] && { reseal=1; shift; }
pcrs=7+12
repo=$(cd "$(dirname "$0")/.." && pwd)

[[ -e /dev/tpmrm0 ]] || { echo "No TPM 2.0 found; nothing to do."; exit 0; }
dev=$(lsblk -nrpo NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')
[[ -n $dev ]] || { echo "No LUKS disk found; nothing to do."; exit 0; }
uuid=$(sudo cryptsetup luksUUID "$dev")

# 1. TPM key slot.
enroll=(--tpm2-device=auto "--tpm2-pcrs=$pcrs")
[[ -n ${1:-} ]] && enroll+=("--unlock-key-file=$1")
if sudo cryptsetup luksDump "$dev" | grep -q 'systemd-tpm2'; then
  if (( reseal )); then
    # Adds the new key first, then removes the old TPM slot.
    sudo systemd-cryptenroll "${enroll[@]}" --wipe-slot=tpm2 "$dev"
  else
    echo "TPM key already enrolled on $dev (use --reseal to replace it)."
  fi
else
  sudo systemd-cryptenroll "${enroll[@]}" "$dev"
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
