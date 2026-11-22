#!/usr/bin/env bash
#
# StardustArch Live-rootfs customization.
#
# archiso still supports this hook, but warns that it is deprecated. It is kept
# because the StardustArch specification requires an auditable
# customize_airootfs.sh and because Live-only account/autologin setup belongs
# to the image build, not to Calamares.
#
# SECURITY: this script creates the empty-password Live account "stardust" and
# enables passwordless sudo for it. Both are removed from the target by the
# Calamares post-install scripts. Never copy this image's /etc/shadow or
# /etc/sudoers.d into a real installation.
#
set -euo pipefail

LIVE_USER="${LIVE_USER:-stardust}"

enable_if_present() {
    local unit="$1"
    if systemctl list-unit-files "${unit}" --no-legend >/dev/null 2>&1 &&
       [[ -n "$(systemctl list-unit-files "${unit}" --no-legend 2>/dev/null)" ]]; then
        systemctl enable "${unit}"
    fi
}

# ---------------------------------------------------------------------------
# Live account
# ---------------------------------------------------------------------------
if ! id "${LIVE_USER}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups wheel "${LIVE_USER}"
fi

# Live convenience groups that actually exist in this image.
for group in wheel video audio input network storage lp optical rfkill power uucp; do
    if getent group "${group}" >/dev/null 2>&1; then
        usermod --append --groups "${group}" "${LIVE_USER}"
    fi
done

# Empty password is intentional for the autologin Live session. The account is
# deleted from the installed target; see target-cleanup.sh.
passwd --delete "${LIVE_USER}" >/dev/null

install -d -m 0755 -o "${LIVE_USER}" -g "${LIVE_USER}" "/home/${LIVE_USER}/Desktop"
install -m 0644 -o "${LIVE_USER}" -g "${LIVE_USER}" \
    /usr/share/applications/stardustarch-calamares.desktop \
    "/home/${LIVE_USER}/Desktop/stardustarch-calamares.desktop"

chown -R "${LIVE_USER}:${LIVE_USER}" "/home/${LIVE_USER}"
chmod 0755 /usr/bin/stardustarch-launch-calamares
chmod 0440 /etc/sudoers.d/10-stardust-live
chmod 0644 /etc/sddm.conf.d/autologin.conf

# ---------------------------------------------------------------------------
# Locale / session
# ---------------------------------------------------------------------------
# Keep the full glibc /etc/locale.gen so Calamares can enable any language the
# user selects. For the Live session, generate en_US and zh_CN.
if [[ -f /etc/locale.gen ]]; then
    sed -i 's/^#[[:space:]]*en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/^#[[:space:]]*zh_CN\.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
fi
locale-gen

# Archiso deliberately ships /etc/machine-id as "uninitialized", which makes
# systemd-firstboot.service run on the Live ISO. With no /etc/localtime it
# blocks the boot at a text-mode "Initial Setup" timezone prompt, so SDDM never
# starts. Configure the Live timezone and mask firstboot for the Live image.
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
systemctl mask systemd-firstboot.service

systemctl set-default graphical.target
systemctl enable sddm.service
systemctl enable NetworkManager.service

# Boot-time and desktop services that are useful and cheap. Missing units are
# skipped, so optional package groups can be disabled in user.conf.
enable_if_present systemd-timesyncd.service
enable_if_present fstrim.timer
enable_if_present apparmor.service
enable_if_present bluetooth.service
enable_if_present power-profiles-daemon.service

# Never wait for an address before bringing up the graphical target.
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

# Keep the Live session on Wayland; the SDDM greeter itself is X11.
# (Plasma X11 session is deliberately not installed.)
rm -f /etc/sddm.conf.d/10-wayland.conf

# Sanity check: the one autologin file is exactly the one shipped by the ISO.
if ! grep -q '^User=stardust$' /etc/sddm.conf.d/autologin.conf; then
    printf 'stardustarch: autologin.conf is missing the Live user\n' >&2
    exit 1
fi

printf 'stardustarch: Live user and passwordless autologin prepared\n'
