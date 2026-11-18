#!/usr/bin/env bash
# Secure Boot with your own keys (sbctl) on Omarchy's Limine + UKI + snapshots,
# keeping Windows dual boot working, plus TPM disk unlock sealed to it.
#
#   scripts/enable-secure-boot.sh prepare   keys, sealed+signed Limine, auto re-seal
#   (reboot to firmware: clear Secure Boot keys / Setup Mode, keep Secure Boot off)
#   scripts/enable-secure-boot.sh enroll    enroll your keys + Microsoft's + firmware's
#   (reboot to firmware: turn Secure Boot on)
#   scripts/enable-secure-boot.sh finish    check, fresh signed snapshot, re-seal TPM
#
# Recovery if it won't boot: turn Secure Boot off in the firmware and pick
# "UEFI OS" (EFI/BOOT/BOOTX64.EFI, a stock unsealed Limine) from the firmware
# boot menu, then run `sudo limine-update`.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
step=${1:-}

install_file() { sudo install -Dm"$1" "$repo/system/$2" "/$2"; }

case $step in
  prepare)
    omarchy pkg add sbctl
    sudo test -d /var/lib/sbctl/keys || sudo sbctl create-keys
    # Seal limine.conf into the loader. Without it Limine 12 treats Secure Boot
    # as off and boots anything (the "fail-open" trap).
    grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=yes' /etc/default/limine ||
      echo 'ENABLE_ENROLL_LIMINE_CONFIG=yes' | sudo tee -a /etc/default/limine >/dev/null
    install_file 755 usr/local/bin/xmilon-limine-seal
    install_file 644 etc/pacman.d/hooks/99-zz-xmilon-limine-seal.hook
    install_file 644 etc/systemd/system/xmilon-limine-seal.path
    install_file 644 etc/systemd/system/xmilon-limine-seal.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now xmilon-limine-seal.path
    # Rebuilds the UKI (signed by sbctl's mkinitcpio hook), seals + signs Limine.
    # BOOTX64.EFI stays stock and unsigned on purpose: the rescue loader.
    sudo limine-update
    sudo sbctl verify || true
    echo "Next: reboot into the firmware (systemctl reboot --firmware-setup),"
    echo "clear the Secure Boot keys (Setup Mode), keep Secure Boot off, boot, then run: $0 enroll"
    ;;
  enroll)
    sudo sbctl status
    sudo sbctl status --json | grep -q '"setup_mode": *true' || {
      echo "Not in Setup Mode yet: clear the Secure Boot keys in the firmware first." >&2; exit 1; }
    # -m Microsoft keys: Windows and the GPU's option ROMs need them.
    # -f the firmware's own built-in db/KEK entries (OEM components).
    sudo sbctl enroll-keys -m -f
    sudo sbctl status
    echo "Next: reboot into the firmware, turn Secure Boot on, boot, then run: $0 finish"
    ;;
  finish)
    sudo sbctl status
    sudo sbctl status --json | grep -q '"secure_boot": *true' || {
      echo "Secure Boot is not on yet." >&2; exit 1; }
    # A snapshot whose boot image is signed (older ones aren't and won't boot).
    sudo snapper -c root create -c number -d "secure boot on"
    sudo limine-snapper-sync
    sudo sbctl verify || true
    # Secure Boot changed PCR 7: seal the TPM disk key again.
    bash "$repo/scripts/enable-tpm-unlock.sh" --reseal "${2:-}"
    ;;
  *)
    sed -n 2,14p "$0"; exit 1 ;;
esac
