#!/usr/bin/env bash
# StardustArch archiso profile definition.
# shellcheck disable=SC2034

iso_name="stardustarch"
iso_label="STARDUST_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="StardustArch Project"
iso_application="StardustArch Live/Install ISO (derived from Arch Linux)"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="stardust"

# Order is intentional: the BIOS El Torito record must be registered before
# the UEFI El Torito record. mkarchiso/xorriso consumes bootmodes in order.
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')

pacman_conf="pacman.conf"
airootfs_image_type="squashfs"

# zstd trades a slightly larger ISO for much faster decompression at boot.
# This is the single largest deterministic Live-boot speed change.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# Do NOT add nowatchdog. Do NOT add mitigations=off.
# AppArmor is the only major LSM enabled here; SELinux/Smack are not used.
# The target bootloader configuration mirrors this list.
kernel_params_x86_64="quiet lsm=landlock,lockdown,yama,integrity,apparmor"

file_permissions=(
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-stardust-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
)
