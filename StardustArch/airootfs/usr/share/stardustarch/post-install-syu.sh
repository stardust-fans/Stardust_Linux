#!/usr/bin/env bash
#
# StardustArch post-install full system upgrade.
#
# Calamares invokes this from the Live environment, before initcpiocfg and
# before the target unmount, with the Calamares root mount point as $1:
#
#   shellprocess (dontChroot: true):
#     -/usr/bin/bash .../post-install-syu.sh ${ROOT}
#
# The script never exits non-zero: a failed network/upgrade is logged and the
# installation continues, exactly like an offline Calamares install. The user
# is told to run "sudo pacman -Syu" after first boot.
#
# Required log path on the target:
#   /var/log/stardustarch-postinstall.log
#
set -u

TARGET="${1:-${STARDUST_TARGET:-/target}}"
TARGET="${TARGET%/}"
LOG="${TARGET}/var/log/stardustarch-postinstall.log"
STATUS_DIR="${TARGET}/etc/stardustarch"
STATUS_FILE="${STATUS_DIR}/postinstall.status"
RESULT="failed"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ -z "${TARGET}" || "${TARGET}" == "/" ]]; then
    printf 'stardustarch: refusing to operate on %q; pass the Calamares target root\n' "${TARGET}" >&2
    exit 0
fi

if [[ ! -d "${TARGET}/etc" ]]; then
    printf 'stardustarch: target root %q has no /etc; refusing to run\n' "${TARGET}" >&2
    exit 0
fi

mkdir -p "${TARGET}/var/log" "${STATUS_DIR}"
: > "${LOG}"
# Keep output visible to Calamares and in the target log at the same time.
exec > >(tee -a "${LOG}") 2>&1

log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

finish() {
    local rc=$?
    trap - EXIT
    if [[ "${RESULT}" == "success" ]]; then
        printf 'success\n' > "${STATUS_FILE}"
        log "RESULT=success"
    else
        printf 'failed\n' > "${STATUS_FILE}"
        log "RESULT=failed (installation is NOT aborted)"
        {
            printf '\n'
            printf 'WARNING: the automatic first-boot "pacman -Syu" did not complete.\n'
            printf 'Run: sudo pacman -Syu\n'
            printf 'Log: /var/log/stardustarch-postinstall.log\n'
        } >> "${TARGET}/etc/motd" 2>/dev/null || true
    fi
    log "finished with exit code ${rc}; log: /var/log/stardustarch-postinstall.log"
    sync || true
    exit 0
}
trap finish EXIT

run_target() {
    log "==> arch-chroot ${TARGET} $*"
    arch-chroot "${TARGET}" "$@" 2>&1
    local rc=$?
    log "<== exit ${rc}"
    return "${rc}"
}

log "StardustArch post-install starting"
log "target=${TARGET}"

# ---------------------------------------------------------------------------
# 1. Remove Live-only identity/security artifacts from the target.
#    This must happen before any account can be used in the installed system.
# ---------------------------------------------------------------------------
log "removing Live autologin, Live sudo rule and Live account"
rm -f "${TARGET}/etc/sddm.conf.d/autologin.conf"
rm -f "${TARGET}/etc/sudoers.d/10-stardust-live"
rm -f "${TARGET}/etc/xdg/autostart/stardustarch-calamares.desktop"
rm -f "${TARGET}/usr/share/applications/stardustarch-calamares.desktop"
rm -f "${TARGET}/usr/bin/stardustarch-launch-calamares"

if arch-chroot "${TARGET}" id stardust >/dev/null 2>&1; then
    arch-chroot "${TARGET}" userdel -r stardust 2>&1 || true
fi
rm -rf "${TARGET}/home/stardust"

# The Live ISO uses an archiso-specific initramfs drop-in. It must be gone
# before Calamares runs initcpiocfg/initcpio on the target.
rm -f "${TARGET}/etc/mkinitcpio.conf.d/archiso.conf"

# No empty-password accounts may survive. Live stardust is already deleted;
# this also protects against an image/customization mistake.
if [[ -r "${TARGET}/etc/shadow" ]]; then
    while IFS=: read -r account password _; do
        if [[ -z "${password}" ]]; then
            log "locking empty-password account: ${account}"
            arch-chroot "${TARGET}" passwd -l "${account}" 2>&1 || true
        fi
    done < "${TARGET}/etc/shadow"
fi

# ---------------------------------------------------------------------------
# 2. pacman keyring. Exactly the required sequence; then optional archlinuxcn.
# ---------------------------------------------------------------------------
if ! run_target pacman-key --init; then
    log "WARNING: pacman-key --init failed; continuing"
fi
if ! run_target pacman-key --populate archlinux; then
    log "WARNING: pacman-key --populate archlinux failed; continuing"
fi

ARCHLINUXCN=0
if [[ -r "${TARGET}/etc/stardustarch/install-options.conf" ]] &&
   grep -q '^ARCHLINUXCN=1$' "${TARGET}/etc/stardustarch/install-options.conf"; then
    ARCHLINUXCN=1
fi

if ((ARCHLINUXCN)); then
    log "archlinuxcn selected: installing and locally signing its keyring first"
    if run_target pacman -Sy --noconfirm archlinuxcn-keyring; then
        if ! run_target pacman-key --populate archlinuxcn; then
            log "WARNING: could not populate archlinuxcn keys; repository will be disabled"
            ARCHLINUXCN=0
        fi
    else
        log "WARNING: archlinuxcn-keyring install failed; repository will be disabled"
        ARCHLINUXCN=0
    fi

    if ((ARCHLINUXCN)); then
        # The temporary TrustAll was only needed to bootstrap the keyring.
        sed -i 's/^SigLevel = Optional TrustAll$/SigLevel = Required DatabaseOptional/' \
            "${TARGET}/etc/pacman.d/stardustarch-archlinuxcn.conf" 2>/dev/null || true
        log "archlinuxcn repository enabled with required signatures"
    else
        sed -i 's#^Include = /etc/pacman.d/stardustarch-archlinuxcn.conf#\# disabled by StardustArch post-install (keyring failed)#' \
            "${TARGET}/etc/pacman.conf" 2>/dev/null || true
    fi
fi

# The graphical target is required even if the upgrade fails.
run_target systemctl set-default graphical.target || true

# Remove the Live-overlay os-release before upgrading. Arch's package may
# want to create /etc/os-release as a symlink; keeping a regular file here
# can cause an "exists in filesystem" conflict. The branded file is written
# back below, after the upgrade.
rm -f "${TARGET}/etc/os-release"

# ---------------------------------------------------------------------------
# 3. The actual required operation: pacman -Syu inside arch-chroot.
# ---------------------------------------------------------------------------
if run_target pacman -Syu --noconfirm; then
    RESULT="success"
else
    RESULT="failed"
    log "WARNING: pacman -Syu failed. Installation continues; run it manually on first boot."
fi

# ---------------------------------------------------------------------------
# 4. Re-assert StardustArch identity after any filesystem/os-release package
#    upgrade. Arch's /etc/os-release is normally a symlink to
#    /usr/lib/os-release; the Live overlay ships a regular branded file, and
#    this rewrite makes the brand deterministic even if that symlink is
#    recreated by an upgrade.
# ---------------------------------------------------------------------------
cat > "${TARGET}/etc/os-release" <<'OSRELEASE'
NAME="StardustArch"
PRETTY_NAME="StardustArch (derived from Arch Linux)"
ID=stardustarch
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;120;180;255"
HOME_URL="https://example.org/stardustarch"
DOCUMENTATION_URL="https://example.org/stardustarch/docs"
SUPPORT_URL="https://example.org/stardustarch/support"
BUG_REPORT_URL="https://example.org/stardustarch/issues"
VARIANT="KDE Plasma"
VARIANT_ID=plasma
OSRELEASE
chmod 0644 "${TARGET}/etc/os-release" 2>/dev/null || true
log "StardustArch os-release re-asserted"

# If mkinitcpio itself was upgraded, its packaged /etc/mkinitcpio.conf may have
# replaced the StardustArch base file. Re-insert the LUKS/LVM hooks before
# filesystems so Calamares' encryption/LVM paths remain bootable.
MKCONF="${TARGET}/etc/mkinitcpio.conf"
if [[ -f "${MKCONF}" ]]; then
    if ! grep -qE '^HOOKS=.*\bencrypt\b' "${MKCONF}"; then
        sed -i 's/\(^HOOKS=.*\)filesystems/\1encrypt lvm2 filesystems/' "${MKCONF}" || true
        log "re-inserted encrypt/lvm2 initramfs hooks"
    elif ! grep -qE '^HOOKS=.*\blvm2\b' "${MKCONF}"; then
        sed -i 's/\(^HOOKS=.*\)filesystems/\1lvm2 filesystems/' "${MKCONF}" || true
        log "re-inserted lvm2 initramfs hook"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Final status and advice.
# ---------------------------------------------------------------------------
if [[ "${RESULT}" == "success" ]]; then
    log "pacman -Syu completed successfully"
else
    log "pacman -Syu did not complete; /var/log/stardustarch-postinstall.log is preserved"
fi

exit 0
