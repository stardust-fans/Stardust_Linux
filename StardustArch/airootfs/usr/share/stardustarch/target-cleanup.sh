#!/usr/bin/env bash
#
# Remove Live-only packages and the Live account from the installed target.
#
# Invoked from a copy in /run because the first package it removes is
# stardustarch-calamares-config, which owns this file in the target.
# The installation must already be bootable when this runs; it is after
# initcpiocfg/initcpio and bootloader in the Calamares sequence.
#
set -u

TARGET="${1:-${STARDUST_TARGET:-/target}}"
TARGET="${TARGET%/}"
LOG="${TARGET}/var/log/stardustarch-postinstall.log"

if [[ -z "${TARGET}" || "${TARGET}" == "/" ]]; then
    printf 'stardustarch: refusing to clean %q; pass the Calamares target root\n' "${TARGET}" >&2
    exit 0
fi

if [[ ! -d "${TARGET}/etc" ]]; then
    printf 'stardustarch: target root %q has no /etc; cleanup skipped\n' "${TARGET}" >&2
    exit 0
fi

mkdir -p "${TARGET}/var/log"
exec >> "${LOG}" 2>&1
printf '\n[%s] === StardustArch target cleanup ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

arch-chroot "${TARGET}" /usr/bin/bash <<'CHROOT' || true
set -u

# The target must boot into Plasma even if an earlier optional unit action
# failed; these are the two non-negotiable units from the specification.
systemctl set-default graphical.target || true
systemctl enable sddm.service NetworkManager.service || true
systemctl enable systemd-timesyncd.service fstrim.timer apparmor.service 2>/dev/null || true
systemctl enable bluetooth.service power-profiles-daemon.service 2>/dev/null || true
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

# Never ship the Live account or its passwordless sudo rule.
rm -f /etc/sddm.conf.d/autologin.conf
rm -f /etc/sudoers.d/10-stardust-live
rm -f /etc/mkinitcpio.conf.d/archiso.conf
rm -f /etc/xdg/autostart/stardustarch-calamares.desktop
rm -f /usr/share/applications/stardustarch-calamares.desktop
rm -f /usr/bin/stardustarch-launch-calamares
rm -rf /usr/share/stardustarch
rm -rf /usr/lib/calamares/modules/stardustarch_options

if id stardust >/dev/null 2>&1; then
    userdel -r stardust 2>/dev/null || true
fi
rm -rf /home/stardust

# Do not leave an empty-password login behind for any account.
awk -F: '($2 == "") { print $1 }' /etc/shadow | while IFS= read -r account; do
    if [[ -n "${account}" ]]; then
        passwd -l "${account}" 2>/dev/null || true
    fi
done

# The Live-only packages. Remove only those actually installed; keep package
# dependency resolution out of this step to avoid taking Plasma down with it.
packages=()
for pkg in stardustarch-calamares-config calamares archinstall mkinitcpio-archiso archiso syslinux; do
    if pacman -Q "${pkg}" >/dev/null 2>&1; then
        packages+=("${pkg}")
    fi
done
if ((${#packages[@]})); then
    pacman -R --noconfirm "${packages[@]}" || true
fi

# The configuration package may leave modified files as .pacsave; remove the
# whole installer config tree, it has no purpose on the installed system.
rm -rf /etc/calamares

# Keep the post-install log; it is the audit trail required by the spec.
ls -l /var/log/stardustarch-postinstall.log 2>/dev/null || true
echo "target cleanup finished"
CHROOT

printf '[%s] === cleanup shell finished ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
exit 0
