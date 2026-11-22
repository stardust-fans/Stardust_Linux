#!/usr/bin/env bash
#
# Runs INSIDE the disposable privileged Arch container.
# Never writes build work to /src or /out: those are only source and artifact
# mounts. Everything else lives under /tmp or the persistent cache volume.
#
set -euo pipefail

SRC="${STARDUST_SRC:-/src}"
PROFILE_SRC="${STARDUST_PROFILE:-${SRC}/StardustArch}"
OUT="${STARDUST_OUT:-/out}"
CACHE="${STARDUST_CACHE:-/var/cache/stardustarch}"
WORK="${STARDUST_WORK:-/tmp/stardustarch}"
FORCE_CALAMARES="${STARDUST_FORCE_CALAMARES:-0}"
CLEAN="${STARDUST_CLEAN:-0}"

info() { printf '[stardustarch] %s\n' "$*" >&2; }
warn() { printf '[stardustarch] WARNING: %s\n' "$*" >&2; }
fatal() { printf '[stardustarch] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -r "${SRC}/user.conf" ]] || fatal "missing ${SRC}/user.conf"
[[ -r "${PROFILE_SRC}/profiledef.sh" ]] || fatal "missing ${PROFILE_SRC}/profiledef.sh"
[[ -d "${OUT}" ]] || fatal "missing output mount ${OUT}"

# shellcheck source=../user.conf
mkdir -p "${WORK}"
install -m 0644 "${SRC}/user.conf" "${WORK}/user.conf"
sed -i 's/\r$//' "${WORK}/user.conf"
source "${WORK}/user.conf"

export MAKEFLAGS="-j${BUILD_JOBS:-$(nproc)}"
export CMAKE_BUILD_PARALLEL_LEVEL="${BUILD_JOBS:-$(nproc)}"
export CCACHE_DIR="${CACHE}/ccache"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-8G}"
export SRCDEST="${CACHE}/srcdest"

if [[ "${CLEAN}" == "1" ]]; then
    info "clean requested: removing previous StardustArch artifacts from ${OUT}"
    find "${OUT}" -maxdepth 1 -type f \
        \( -name 'stardustarch-*.iso' -o -name 'stardustarch-*.iso.sha256' \) -delete || true
fi

rm -rf "${WORK}"
mkdir -p "${WORK}/profile" "${WORK}/customrepo" "${WORK}/pkgbuild" \
         "${WORK}/iso-work" "${WORK}/iso-out"
mkdir -p "${CACHE}/ccache" "${CACHE}/customrepo" "${CACHE}/srcdest" \
         "${CACHE}/pacman/pkg"
chown -R builder:builder "${CACHE}/ccache" "${CACHE}/srcdest"

# ---------------------------------------------------------------------------
# Optional build-time mirror selection. Only the throwaway container's
# mirrorlist changes; it is not copied into the finished ISO.
# ---------------------------------------------------------------------------
if [[ "${USE_REFLECTOR:-yes}" == "yes" && -n "${MIRROR_COUNTRY:-}" ]]; then
    if command -v reflector >/dev/null 2>&1; then
        info "selecting up to 20 HTTPS Arch mirrors in ${MIRROR_COUNTRY}"
        cp -a /etc/pacman.d/mirrorlist /tmp/mirrorlist.stardustarch-original
        if ! reflector --country "${MIRROR_COUNTRY}" --protocol https \
                --latest 20 --sort rate --save /etc/pacman.d/mirrorlist; then
            warn "reflector failed; restoring the original mirrorlist"
            cp -a /tmp/mirrorlist.stardustarch-original /etc/pacman.d/mirrorlist
        fi
    else
        warn "reflector is not installed; keeping the container mirrorlist"
    fi
fi

# ---------------------------------------------------------------------------
# Stage the archiso profile. The Windows bind mount is read-only and never a
# build directory; all generated files go to /tmp.
# ---------------------------------------------------------------------------
info "staging profile in ${WORK}/profile"
cp -a "${PROFILE_SRC}/." "${WORK}/profile/"

# A Windows/DrvFs checkout often reports every file as 0777. Normalize the
# profile so the ISO does not ship world-writable configuration. The few
# executable files are restored below and profiledef.file_permissions also
# pins the security-sensitive paths.
find "${WORK}/profile" -type d -exec chmod 0755 {} +
find "${WORK}/profile" -type f -exec chmod 0644 {} +
chmod 0755 \
    "${WORK}/profile/airootfs/root/customize_airootfs.sh" \
    "${WORK}/profile/airootfs/usr/share/stardustarch/post-install-syu.sh" \
    "${WORK}/profile/airootfs/usr/share/stardustarch/target-cleanup.sh" \
    "${WORK}/profile/airootfs/usr/bin/stardustarch-launch-calamares" \
    "${WORK}/profile/airootfs/usr/lib/calamares/modules/stardustarch_options/main.py"
chmod 0440 "${WORK}/profile/airootfs/etc/sudoers.d/10-stardust-live"

# Apply the squashfs design values from user.conf. Keep the syntax in sync
# with profiledef.sh; this is the only generated line in that file.
if [[ ! "${SQUASHFS_LEVEL:-15}" =~ ^[0-9]+$ ]]; then
    fatal "SQUASHFS_LEVEL must be numeric"
fi
case "${SQUASHFS_COMPRESSION:-zstd}" in
    zstd)
        squash_opts="'-comp' 'zstd' '-Xcompression-level' '${SQUASHFS_LEVEL:-15}' '-b' '1M'"
        ;;
    xz)
        squash_opts="'-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M'"
        ;;
    *)
        fatal "unsupported SQUASHFS_COMPRESSION=${SQUASHFS_COMPRESSION}; use zstd or xz"
        ;;
esac
sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=(${squash_opts})|" \
    "${WORK}/profile/profiledef.sh"

# Normalize CRLF on text files copied from a Windows checkout. Binary images
# are deliberately excluded.
while IFS= read -r -d '' file; do
    sed -i 's/\r$//' "${file}"
done < <(find "${WORK}/profile" -type f \
    \( -name '*.sh' -o -name '*.conf' -o -name '*.cfg' -o -name '*.desc' \
       -o -name '*.qml' -o -name '*.qss' -o -name '*.py' -o -name '*.desktop' \
       -o -name '*.x86_64' -o -name '*.kde' -o -name '*.gen' -o -name '*.issue' \
       -o -name '*.motd' -o -name '*.hosts' -o -name '*.hostname' \
       -o -name '*.environment' \) -print0)

# ---------------------------------------------------------------------------
# Assemble packages.x86_64 from the group files. Package names are sorted only
# for determinism; no comments are passed to pacstrap.
# ---------------------------------------------------------------------------
assemble_packages() {
    local speed_file="${WORK}/profile/packages.speed"

    if [[ "${INSTALL_SPEED_TWEAKS:-yes}" != "yes" || "${ENABLE_ZRAM:-yes}" != "yes" ]]; then
        # Produce a temporary filtered view without modifying the source file.
        grep -vx 'zram-generator' "${speed_file}" > "${WORK}/packages.speed.filtered" || true
        speed_file="${WORK}/packages.speed.filtered"
    fi

    {
        grep -vE '^[[:space:]]*(#|$)' "${WORK}/profile/packages.x86_64" || true
        grep -vE '^[[:space:]]*(#|$)' "${WORK}/profile/packages.kde" || true
        if [[ "${INSTALL_DESKTOP:-yes}" == "yes" ]]; then
            grep -vE '^[[:space:]]*(#|$)' "${WORK}/profile/packages.desktop" || true
        fi
        if [[ "${INSTALL_SPEED_TWEAKS:-yes}" == "yes" ]]; then
            grep -vE '^[[:space:]]*(#|$)' "${speed_file}" || true
        fi
        if [[ "${INSTALL_PARU:-no}" == "yes" ]]; then
            printf '%s\n' base-devel paru-bin
        fi
        if ((${#EXTRA_PKGS[@]})); then
            printf '%s\n' "${EXTRA_PKGS[@]}"
        fi
    } | awk 'NF {print $1}' | awk '!seen[$0]++' > "${WORK}/profile/packages.x86_64.assembled"

    mv "${WORK}/profile/packages.x86_64.assembled" "${WORK}/profile/packages.x86_64"
}

assemble_packages

# ---------------------------------------------------------------------------
# user.conf early-KMS choice. Keep this explicit and hardware-specific; generic
# ISOs should leave EARLY_KMS="none".
# ---------------------------------------------------------------------------
case "${EARLY_KMS:-none}" in
    none)
        ;;
    intel)
        printf 'MODULES=(i915)\n' > "${WORK}/profile/airootfs/etc/mkinitcpio.conf.d/20-stardustarch-early-kms.conf"
        ;;
    amdgpu)
        printf 'MODULES=(amdgpu)\n' > "${WORK}/profile/airootfs/etc/mkinitcpio.conf.d/20-stardustarch-early-kms.conf"
        ;;
    nvidia)
        printf 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)\n' \
            > "${WORK}/profile/airootfs/etc/mkinitcpio.conf.d/20-stardustarch-early-kms.conf"
        printf 'options nvidia_drm modeset=1 fbdev=1\n' \
            > "${WORK}/profile/airootfs/etc/modprobe.d/stardustarch-nvidia.conf"
        printf '%s\n' nvidia nvidia-utils >> "${WORK}/profile/packages.x86_64"
        ;;
    nvidia-open)
        printf 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)\n' \
            > "${WORK}/profile/airootfs/etc/mkinitcpio.conf.d/20-stardustarch-early-kms.conf"
        printf 'options nvidia_drm modeset=1 fbdev=1\n' \
            > "${WORK}/profile/airootfs/etc/modprobe.d/stardustarch-nvidia.conf"
        printf '%s\n' nvidia-open nvidia-utils >> "${WORK}/profile/packages.x86_64"
        ;;
    *)
        fatal "unsupported EARLY_KMS=${EARLY_KMS}; use none|intel|amdgpu|nvidia|nvidia-open"
        ;;
esac

if [[ "${INSTALL_SPEED_TWEAKS:-yes}" != "yes" || "${ENABLE_ZRAM:-yes}" != "yes" ]]; then
    rm -f "${WORK}/profile/airootfs/etc/systemd/zram-generator.conf"
    rm -f "${WORK}/profile/airootfs/etc/sysctl.d/99-stardustarch-zram.conf"
fi

# ---------------------------------------------------------------------------
# Build the local [customrepo]. Calamares is not in the official Arch repos,
# so this is mandatory. The package is cached on the Docker volume.
# ---------------------------------------------------------------------------
build_makepkg() {
    local source_dir="$1"
    local build_dir="${WORK}/pkgbuild/$(basename "${source_dir}")"
    local package

    rm -rf "${build_dir}"
    mkdir -p "${build_dir}/out"
    cp -a "${source_dir}/." "${build_dir}/"
    chown -R builder:builder "${build_dir}"
    chmod -R u+rwX "${build_dir}"
    sed -i 's/\r$//' "${build_dir}/PKGBUILD"

    info "building $(basename "${source_dir}") with makepkg"
    runuser -u builder -- env \
        HOME=/home/builder \
        MAKEFLAGS="${MAKEFLAGS}" \
        CCACHE_DIR="${CACHE}/ccache" \
        CCACHE_MAXSIZE="${CCACHE_MAXSIZE}" \
        SRCDEST="${CACHE}/srcdest" \
        PKGDEST="${build_dir}/out" \
        bash -lc "cd '${build_dir}' && makepkg --noconfirm --nodeps --cleanbuild --force" >&2

    package="$(find "${build_dir}/out" -maxdepth 1 -type f \
        -name '*.pkg.tar.zst' ! -name '*-debug-*' -print -quit)"
    [[ -n "${package}" ]] || fatal "makepkg produced no package in ${build_dir}/out"
    printf '%s\n' "${package}"
}

build_calamares() {
    local cached package
    cached="$(find "${CACHE}/customrepo" -maxdepth 1 -type f \
        -name 'calamares-3.4.2-*.pkg.tar.zst' ! -name '*-debug-*' -print -quit || true)"

    if [[ -n "${cached}" && "${FORCE_CALAMARES}" != "1" ]]; then
        info "using cached Calamares package: $(basename "${cached}")"
        package="${cached}"
    else
        package="$(build_makepkg "${SRC}/pkg/calamares")"
        install -m 0644 "${package}" "${CACHE}/customrepo/"
    fi
    cp -a "${package}" "${WORK}/customrepo/"
}

build_config_package() {
    local staging="${WORK}/pkgsrc/stardustarch-calamares-config"
    local stage="${staging}/rootfs"
    local package

    info "staging stardustarch-calamares-config"
    rm -rf "${staging}"
    mkdir -p \
        "${stage}/etc" \
        "${stage}/usr/share/stardustarch" \
        "${stage}/usr/lib/calamares/modules" \
        "${stage}/usr/bin" \
        "${stage}/usr/share/applications" \
        "${stage}/etc/xdg/autostart"

    cp -a "${WORK}/profile/airootfs/etc/calamares" "${stage}/etc/calamares"
    install -m 0755 "${WORK}/profile/airootfs/usr/share/stardustarch/post-install-syu.sh" \
        "${stage}/usr/share/stardustarch/post-install-syu.sh"
    install -m 0755 "${WORK}/profile/airootfs/usr/share/stardustarch/target-cleanup.sh" \
        "${stage}/usr/share/stardustarch/target-cleanup.sh"
    cp -a "${WORK}/profile/airootfs/usr/lib/calamares/modules/stardustarch_options" \
        "${stage}/usr/lib/calamares/modules/stardustarch_options"
    find "${stage}" -type d -name '__pycache__' -prune -exec rm -rf {} +
    find "${stage}" -type f -name '*.pyc' -delete
    install -m 0755 "${WORK}/profile/airootfs/usr/bin/stardustarch-launch-calamares" \
        "${stage}/usr/bin/stardustarch-launch-calamares"
    install -m 0644 "${WORK}/profile/airootfs/usr/share/applications/stardustarch-calamares.desktop" \
        "${stage}/usr/share/applications/stardustarch-calamares.desktop"
    install -m 0644 "${WORK}/profile/airootfs/etc/xdg/autostart/stardustarch-calamares.desktop" \
        "${stage}/etc/xdg/autostart/stardustarch-calamares.desktop"

    cp -a "${SRC}/pkg/stardustarch-calamares-config/PKGBUILD" "${staging}/PKGBUILD"
    tar -czf "${staging}/stardustarch-calamares-config.tar.gz" \
        -C "$(dirname "${stage}")" "$(basename "${stage}")"
    chown -R builder:builder "${staging}"

    package="$(build_makepkg "${staging}")"
    cp -a "${package}" "${WORK}/customrepo/"
}

info "building local custom repository"
build_calamares
build_config_package

if [[ "${INSTALL_PARU:-no}" == "yes" ]]; then
    info "INSTALL_PARU=yes: building paru-bin"
    paru_pkg="$(build_makepkg "${SRC}/pkg/paru-bin")"
    cp -a "${paru_pkg}" "${WORK}/customrepo/"
fi

# Make sure the package list really refers to the two locally built packages.
for required in calamares stardustarch-calamares-config; do
    grep -qx "${required}" "${WORK}/profile/packages.x86_64" \
        || fatal "${required} is missing from the assembled package list"
done

(
    cd "${WORK}/customrepo"
    shopt -s nullglob
    packages=( ./*.pkg.tar.zst )
    ((${#packages[@]})) || fatal "custom repository has no packages"
    repo-add -n -R customrepo.db.tar.gz "${packages[@]}"
)

# The config package is now built. Remove the same paths from the airootfs
# overlay so that /etc/calamares and the Live helper scripts have exactly one
# owner: stardustarch-calamares-config, installed by pacstrap.
rm -rf "${WORK}/profile/airootfs/etc/calamares"
rm -rf "${WORK}/profile/airootfs/usr/share/stardustarch"
rm -rf "${WORK}/profile/airootfs/usr/lib/calamares/modules/stardustarch_options"
rm -f "${WORK}/profile/airootfs/usr/bin/stardustarch-launch-calamares"
rm -f "${WORK}/profile/airootfs/usr/share/applications/stardustarch-calamares.desktop"
rm -f "${WORK}/profile/airootfs/etc/xdg/autostart/stardustarch-calamares.desktop"

# ---------------------------------------------------------------------------
# Build the ISO. mkarchiso must run as root and its work dir is inside /tmp.
# ---------------------------------------------------------------------------
info "building ISO with mkarchiso"
mkarchiso -v -w "${WORK}/iso-work" -o "${WORK}/iso-out" "${WORK}/profile"

iso="$(find "${WORK}/iso-out" -maxdepth 1 -type f -name 'stardustarch-*.iso' -print -quit)"
[[ -n "${iso}" ]] || fatal "mkarchiso produced no ISO"
[[ -s "${iso}" ]] || fatal "mkarchiso produced an empty ISO"

iso_name="$(basename "${iso}")"
(
    cd "$(dirname "${iso}")"
    sha256sum "${iso_name}" > "${iso_name}.sha256"
)

install -m 0644 "${iso}" "${OUT}/${iso_name}"
install -m 0644 "${iso}.sha256" "${OUT}/${iso_name}.sha256"

{
    printf 'StardustArch build information\n'
    printf 'Built (UTC): %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Profile: %s\n' "${PROFILE_SRC}"
    printf 'ISO: %s\n' "${iso_name}"
    printf 'Size: %s bytes\n' "$(stat -c '%s' "${iso}")"
    printf 'SHA256: %s\n' "$(cut -d' ' -f1 "${iso}.sha256")"
    printf 'Packages (custom):\n'
    for pkg in "${WORK}/customrepo/"*.pkg.tar.zst; do
        printf '  %s\n' "$(basename "${pkg}")"
    done
    printf '\nOptions:\n'
    printf '  INSTALL_DESKTOP=%s\n' "${INSTALL_DESKTOP:-yes}"
    printf '  INSTALL_SPEED_TWEAKS=%s\n' "${INSTALL_SPEED_TWEAKS:-yes}"
    printf '  ENABLE_ZRAM=%s\n' "${ENABLE_ZRAM:-yes}"
    printf '  INSTALL_PARU=%s\n' "${INSTALL_PARU:-no}"
    printf '  EARLY_KMS=%s\n' "${EARLY_KMS:-none}"
    printf '  MIRROR_COUNTRY=%s\n' "${MIRROR_COUNTRY:-}"
} > "${OUT}/stardustarch-build-info.txt"

info "ISO written to ${OUT}/${iso_name}"
info "checksum written to ${OUT}/${iso_name}.sha256"
ls -lh "${OUT}/${iso_name}" "${OUT}/${iso_name}.sha256" "${OUT}/stardustarch-build-info.txt"
